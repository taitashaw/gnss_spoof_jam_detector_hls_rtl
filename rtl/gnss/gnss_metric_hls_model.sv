// ============================================================================
// gnss_metric_hls_model.sv -- BEHAVIORAL metric engine (simulation stand-in)
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// *** This is a behavioral SystemVerilog stand-in for the metric engine so that
// *** `make xsim` runs WITHOUT having first run Vitis HLS. The production
// *** hardware IP for this block is exported from Vitis HLS (gnss_metric_hls.cpp)
// *** and dropped in via the one-line switch in vivado/compile_order.tcl. This
// *** model presents the IDENTICAL port list to that exported IP.
//
// It is numerically faithful to the golden reference hls/src/gnss_metric_ref.cpp:
// it accumulates power, sub-block sums, E/P/L correlations and the doppler
// cross-product energy over a window of tapped beats, then at tlast computes the
// noise estimate, C/N0 proxy, symmetry, derived anomaly signals, the saturated
// spoof/jam scores, and emits one metrics bundle. power_prev / noise_prev are
// passed IN (no hidden state); the current power/noise are presented for the
// reg bank to latch for the next window. Active-low reset.
// ============================================================================
`default_nettype none

module gnss_metric_hls_model
    import gnss_top_pkg::*;
(
    input  wire        clk,
    input  wire        rst_n,

    // tapped stream in
    input  wire [TAP_W-1:0] s_tap_tdata,
    input  wire             s_tap_tlast,
    input  wire             s_tap_tvalid,
    output wire             s_tap_tready,

    // status feedback (from reg bank latches)
    input  wire [47:0] power_prev,
    input  wire [31:0] noise_prev,

    // metrics bundle out (one beat per window)
    output reg         m_valid,
    input  wire        m_ready,
    output reg  [31:0] window_id,
    output reg  [47:0] power_estimate,
    output reg  [31:0] noise_estimate,
    output reg  [31:0] cn0_proxy,
    output reg  [31:0] corr_prompt,
    output reg  [31:0] corr_early,
    output reg  [31:0] corr_late,
    output reg  [31:0] symmetry_error,
    output reg  [47:0] doppler_energy,
    output reg  [47:0] power_jump_metric,
    output reg  [31:0] spoof_score,
    output reg  [31:0] jam_score,
    output reg  [31:0] sample_count
);
    // ---------- helper functions (mirror fixed_types.hpp) ----------
    function automatic int unsigned gnss_log2fx(input logic [63:0] x);
        int unsigned msb; logic [63:0] xx; int unsigned frac;
        if (x == 0) return 0;
        msb = 0; xx = x;
        while (xx > 1) begin xx = xx >> 1; msb = msb + 1; end
        if (msb >= 4) frac = (x >> (msb - 4)) & 64'hF;
        else          frac = (x << (4 - msb)) & 64'hF;
        return (msb << 4) | frac;
    endfunction

    function automatic int unsigned gnss_norm(input logic [63:0] a, input int sh, input int nm);
        logic [63:0] n;
        n = a >> sh;
        return (n > nm) ? nm : n[31:0];
    endfunction

    function automatic logic [31:0] uabs32(input logic signed [40:0] v);
        return v[40] ? (-v) : v;
    endfunction

    // ---------- unpack tapped beat ----------
    wire signed [15:0] mi = s_tap_tdata[15:0];
    wire signed [15:0] mq = s_tap_tdata[31:16];
    wire signed [1:0]  ce = s_tap_tdata[32] ? 2'sd1 : -2'sd1;
    wire signed [1:0]  cp = s_tap_tdata[33] ? 2'sd1 : -2'sd1;
    wire signed [1:0]  cl = s_tap_tdata[34] ? 2'sd1 : -2'sd1;
    wire [10:0]        sidx = s_tap_tdata[45:35];

    // ---------- accumulators ----------
    reg [47:0] power_acc;
    reg [40:0] blk_sum [0:NUM_SUBBLOCKS-1];
    reg signed [40:0] IcorrE, QcorrE, IcorrP, QcorrP, IcorrL, QcorrL;
    reg [47:0] dopp_acc;
    reg signed [15:0] prev_i, prev_q;
    reg        first;            // first beat of window -> prev = 0
    reg [31:0] cnt;
    reg [31:0] win_count;        // window_id

    wire fire = s_tap_tvalid && s_tap_tready;
    assign s_tap_tready = !m_valid || m_ready;

    // per-beat contributions (combinational)
    wire [31:0] p_beat = (mi * mi) + (mq * mq);
    wire signed [15:0] pi = first ? 16'sd0 : prev_i;
    wire signed [15:0] pq = first ? 16'sd0 : prev_q;
    wire signed [40:0] cross_prod = (mq * pi) - (mi * pq);
    wire [31:0] cross_abs = uabs32(cross_prod);
    wire [2:0]  blk = sidx[9:7];

    // ---------- final metric computation at tlast (combinational from acc+beat) ----------
    // accumulator values INCLUDING this (tlast) beat
    logic [47:0] f_power;
    logic [40:0] f_blk [0:NUM_SUBBLOCKS-1];
    logic signed [40:0] f_IE,f_QE,f_IP,f_QP,f_IL,f_QL;
    logic [47:0] f_dopp;
    integer bi;
    always @(*) begin
        f_power = power_acc + p_beat;
        for (bi=0; bi<NUM_SUBBLOCKS; bi=bi+1) f_blk[bi] = blk_sum[bi];
        f_blk[blk] = blk_sum[blk] + p_beat;
        f_IE = IcorrE + mi*ce; f_QE = QcorrE + mq*ce;
        f_IP = IcorrP + mi*cp; f_QP = QcorrP + mq*cp;
        f_IL = IcorrL + mi*cl; f_QL = QcorrL + mq*cl;
        f_dopp = dopp_acc + cross_abs;
    end

    // derived final metrics
    logic [31:0] blk_min;
    logic [31:0] n_corr_e, n_corr_p, n_corr_l, n_sym, n_cn0, n_cn0ab;
    logic [31:0] n_noise;
    logic signed [40:0] np_s, bm_s, nn_s; // signed IIR scratch (no unsigned mixing)
    logic [63:0] n_replica, n_collapse;
    logic [47:0] n_pjump;
    logic [31:0] n_spoof, n_jam;
    integer mb;
    always @(*) begin
        // noise: min sub-block mean, smoothed.
        // The IIR is computed in signed locals ONLY -- mixing the unsigned
        // noise_prev into the expression would make >>> a logical shift and
        // wrap the negative delta. (Mirrors the int64 math in gnss_metric_ref.cpp.)
        blk_min = f_blk[0] >> SUBBLOCK_LOG2;
        for (mb=1; mb<NUM_SUBBLOCKS; mb=mb+1)
            if ((f_blk[mb] >> SUBBLOCK_LOG2) < blk_min) blk_min = f_blk[mb] >> SUBBLOCK_LOG2;
        np_s = $signed({9'd0, noise_prev});
        bm_s = $signed({9'd0, blk_min});
        nn_s = np_s + ((bm_s - np_s) >>> NOISE_SMOOTH_SHIFT);
        if (noise_prev == 0) n_noise = blk_min;
        else                 n_noise = nn_s[31:0];

        n_corr_e = uabs32(f_IE) + uabs32(f_QE);
        n_corr_p = uabs32(f_IP) + uabs32(f_QP);
        n_corr_l = uabs32(f_IL) + uabs32(f_QL);
        n_sym    = (n_corr_e > n_corr_l) ? (n_corr_e - n_corr_l) : (n_corr_l - n_corr_e);
        n_pjump  = (f_power > power_prev) ? (f_power - power_prev) : (power_prev - f_power);

        // cn0 proxy (log-domain)
        begin
            int unsigned lc, ln; int diff; int cn0v;
            lc = gnss_log2fx({32'd0, n_corr_p});
            ln = gnss_log2fx({32'd0, n_noise});
            diff = CN0_K * ($signed(lc) - $signed(ln)) + CN0_OFFSET;
            if (diff < 0) cn0v = 0; else if (diff > CN0_MAX) cn0v = CN0_MAX; else cn0v = diff;
            n_cn0 = cn0v;
            if (CN0_HEALTHY_REF - cn0v < 0) n_cn0ab = 0;
            else n_cn0ab = (CN0_HEALTHY_REF - cn0v > CN0_ABNORMAL_MAX) ? CN0_ABNORMAL_MAX : (CN0_HEALTHY_REF - cn0v);
        end

        n_replica  = ($signed({32'd0,n_corr_e}) + $signed({32'd0,n_corr_l}) - $signed({32'd0,n_corr_p}) < 0)
                     ? 64'd0 : (n_corr_e + n_corr_l - n_corr_p);
        n_collapse = ($signed(CORR_PROMPT_REF) - $signed({32'd0,n_corr_p}) < 0)
                     ? 64'd0 : (CORR_PROMPT_REF - n_corr_p);

        // scores
        begin
            int unsigned nSym,nDop,nC,nRepl,nPwr,nCol,nTone; int unsigned sp, jm;
            nSym  = gnss_norm({32'd0,n_sym},  SYM_NORM_SHIFT,  NORM_MAX);
            nDop  = gnss_norm(f_dopp,         DOPP_NORM_SHIFT, NORM_MAX);
            nC    = gnss_norm({32'd0,n_cn0ab},CN0ABN_NORM_SHIFT,NORM_MAX);
            nRepl = gnss_norm(n_replica,      REPL_NORM_SHIFT, NORM_MAX);
            nPwr  = gnss_norm(f_power,        PWR_NORM_SHIFT,  NORM_MAX);
            nCol  = gnss_norm(n_collapse,     COLLAPSE_NORM_SHIFT, NORM_MAX);
            nTone = gnss_norm({32'd0,n_noise},TONE_NORM_SHIFT, NORM_MAX);
            sp = W_SYM*nSym + W_DOP*nDop + W_CN0*nC + W_REPL*nRepl;
            jm = W_PWR*nPwr + W_LOWCN0*nC + W_COLLAPSE*nCol + W_TONE*nTone;
            n_spoof = (sp > SCORE_MAX) ? SCORE_MAX : sp;
            n_jam   = (jm > SCORE_MAX) ? SCORE_MAX : jm;
        end
    end

    integer ci;
    always @(posedge clk) begin
        if (!rst_n) begin
            power_acc <= 48'd0; dopp_acc <= 48'd0;
            IcorrE<=0; QcorrE<=0; IcorrP<=0; QcorrP<=0; IcorrL<=0; QcorrL<=0;
            prev_i<=0; prev_q<=0; first<=1'b1; cnt<=32'd0; win_count<=32'd0;
            m_valid<=1'b0;
            for (ci=0; ci<NUM_SUBBLOCKS; ci=ci+1) blk_sum[ci] <= 41'd0;
        end else begin
            if (m_valid && m_ready) m_valid <= 1'b0;

            if (fire) begin
                if (s_tap_tlast) begin
`ifdef ME_DEBUG
                    $display("[me] win=%0d noise_prev=%0d blk_min=%0d n_noise=%0d power_prev=%0d f_power=%0d",
                             win_count, noise_prev, blk_min, n_noise, power_prev, f_power);
`endif
                    // latch the full-window metrics
                    window_id         <= win_count;
                    power_estimate    <= f_power;
                    noise_estimate    <= n_noise;
                    cn0_proxy         <= n_cn0;
                    corr_prompt       <= n_corr_p;
                    corr_early        <= n_corr_e;
                    corr_late         <= n_corr_l;
                    symmetry_error    <= n_sym;
                    doppler_energy    <= f_dopp;
                    power_jump_metric <= n_pjump;
                    spoof_score       <= n_spoof;
                    jam_score         <= n_jam;
                    sample_count      <= cnt + 1'b1;
                    m_valid           <= 1'b1;
                    win_count         <= win_count + 1'b1;
                    // reset accumulators for next window
                    power_acc <= 48'd0; dopp_acc <= 48'd0;
                    IcorrE<=0; QcorrE<=0; IcorrP<=0; QcorrP<=0; IcorrL<=0; QcorrL<=0;
                    prev_i<=0; prev_q<=0; first<=1'b1; cnt<=32'd0;
                    for (ci=0; ci<NUM_SUBBLOCKS; ci=ci+1) blk_sum[ci] <= 41'd0;
                end else begin
                    power_acc <= f_power;
                    blk_sum[blk] <= blk_sum[blk] + p_beat;
                    IcorrE<=f_IE; QcorrE<=f_QE; IcorrP<=f_IP; QcorrP<=f_QP; IcorrL<=f_IL; QcorrL<=f_QL;
                    dopp_acc <= f_dopp;
                    prev_i <= mi; prev_q <= mq; first <= 1'b0;
                    cnt <= cnt + 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
