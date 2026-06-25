// ============================================================================
// early_prompt_late_tap.sv -- align mixed stream with E/P/L chips -> tapped beat
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Pairs the NCO-mixed sample stream with the PRN early/prompt/late chip taps and
// emits the Section-2 tapped stream. To center the prompt correlator the mixed
// stream is delayed by one sample: at the cycle that accepts input sample n the
// PRN presents e=g[n], p=g[n-1], l=g[n-2], and this module emits the buffered
// sample n-1 paired with those chips (prompt g[n-1] aligns with mixed[n-1],
// early g[n] is one sample ahead, late g[n-2] one behind).
//
// The final sample of a window has no later input to supply its look-ahead, so a
// one-cycle DRAIN emits it using the edge-fill PRN value (g[N], i.e. the next
// code chip) and then restarts the PRN for the next window. The golden model
// uses a window-local wrap (early[N-1]=c[0], late[0]=c[N-1]); the streaming RTL
// uses edge-fill at those two boundary beats. XSim is checked LOOSE against
// ranges + exact flags, and the thresholds carry wide margins, so this 2-of-1024
// boundary difference cannot change a metric flag. See docs/verification_strategy.md.
//
// Tapped tdata packing (TAP_W = 46 bits), tlast carried separately:
//   [15:0]  mixed_i (s16)   [31:16] mixed_q (s16)
//   [32] early sign  [33] prompt sign  [34] late sign   ([1]=+1, [0]=-1)
//   [45:35] sample_index (0..WINDOW_SIZE-1)
//
// VALID is held in an output register (sticky until accepted); s_mixed_tready
// never folds m_tap_tready into the forward VALID path. Active-low reset.
// ============================================================================
`default_nettype none

module early_prompt_late_tap
    import gnss_top_pkg::*;
(
    input  wire        clk,
    input  wire        rst_n,

    // mixed stream in (from nco_mixer): [31:16]=mixed_i, [15:0]=mixed_q
    input  wire [31:0] s_mixed_tdata,
    input  wire        s_mixed_tlast,
    input  wire        s_mixed_tvalid,
    output wire        s_mixed_tready,

    // PRN control + chip taps
    output wire        prn_advance,
    output wire        prn_restart,
    input  wire signed [1:0] chip_e,
    input  wire signed [1:0] chip_p,
    input  wire signed [1:0] chip_l,

    // tapped stream out
    output wire [TAP_W-1:0] m_tap_tdata,
    output wire             m_tap_tlast,
    output wire             m_tap_tvalid,
    input  wire             m_tap_tready
);
    // ---- buffered (delayed) sample + state ----
    reg [31:0]  buf_mixed;
    reg [10:0]  buf_idx;
    reg         buf_valid;
    reg [10:0]  in_idx;
    reg         drain;

    // ---- output holding register ----
    reg [TAP_W-1:0] o_data;
    reg             o_last;
    reg             o_valid;

    assign m_tap_tdata  = o_data;
    assign m_tap_tlast  = o_last;
    assign m_tap_tvalid = o_valid;

    wire out_slot_free = !o_valid || m_tap_tready;

    // normal accept emits the buffered sample, so it needs a free output slot;
    // the very first sample of a window has nothing buffered yet.
    wire emit_needs_slot = buf_valid;
    wire accept = s_mixed_tvalid && !drain && (emit_needs_slot ? out_slot_free : 1'b1);
    assign s_mixed_tready = !drain && (emit_needs_slot ? out_slot_free : 1'b1);

    wire do_drain_emit = drain && out_slot_free;

    assign prn_advance = accept;
    assign prn_restart = do_drain_emit;

    // pack the buffered sample with the PRN's CURRENT chips
    wire e_sign = (chip_e > 0);
    wire p_sign = (chip_p > 0);
    wire l_sign = (chip_l > 0);
    wire [TAP_W-1:0] emit_word = {buf_idx, l_sign, p_sign, e_sign, buf_mixed};

    always @(posedge clk) begin
        if (!rst_n) begin
            buf_valid <= 1'b0;
            buf_mixed <= 32'd0;
            buf_idx   <= 11'd0;
            in_idx    <= 11'd0;
            drain     <= 1'b0;
            o_valid   <= 1'b0;
            o_data    <= '0;
            o_last    <= 1'b0;
        end else begin
            // drain a previously accepted output beat
            if (o_valid && m_tap_tready) o_valid <= 1'b0;

            if (accept) begin
                if (buf_valid) begin
                    o_data  <= emit_word;   // emit buffered sample n-1 (not last)
                    o_last  <= 1'b0;
                    o_valid <= 1'b1;
                end
                buf_mixed <= s_mixed_tdata;
                buf_idx   <= in_idx;
                buf_valid <= 1'b1;
                if (s_mixed_tlast) begin
                    drain <= 1'b1;          // final sample drains next
                end else begin
                    in_idx <= in_idx + 1'b1;
                end
            end

            if (do_drain_emit) begin
                o_data    <= emit_word;     // emit buffered final sample (last)
                o_last    <= 1'b1;
                o_valid   <= 1'b1;
                buf_valid <= 1'b0;
                drain     <= 1'b0;
                in_idx    <= 11'd0;
            end
        end
    end
endmodule

`default_nettype wire
