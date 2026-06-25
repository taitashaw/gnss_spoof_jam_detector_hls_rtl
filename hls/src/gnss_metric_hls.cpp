// ============================================================================
// gnss_metric_hls.cpp  --  HLS metric engine kernel (synthesizable)
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Top function: gnss_metric_hls. Consumes the tapped stream (mixed I/Q + E/P/L
// chip signs + sample index + tlast) for ONE window and emits one packed metrics
// bundle (axis_metric_pkt_t). Implements every Section 3 metric using ap_int with
// the Section 5 fixed-point widths -- the SAME integer math as the golden model
// gnss_metric_ref.cpp, so the kernel output matches the reference TIGHT (the C
// testbench tb_gnss_metric_hls.cpp checks within a small documented tolerance).
//
// power_prev / noise_prev are passed IN via s_axilite (pass-in design, no hidden
// static for power_jump); the current power/noise are returned for the host/reg
// bank to latch for the next window.
//
// NO FLOATING POINT. The accumulation loop targets II=1.
// ============================================================================
#include "gnss_config.hpp"
#include "fixed_types.hpp"
#include "axis_types.hpp"
#include "ap_int.h"

// ---- shared integer helpers (identical results to fixed_types.hpp) ----------
static int hls_msb_index(ap_uint<64> x) {
#pragma HLS INLINE
    int idx = 0;
    for (int b = 63; b > 0; --b) {     // priority-encoder style
#pragma HLS UNROLL
        if (x[b]) { idx = b; break; }
    }
    return idx;
}

static int hls_log2_fx(ap_uint<64> x) {
#pragma HLS INLINE
    if (x == 0) return 0;
    int msb = hls_msb_index(x);
    int frac;
    if (msb >= 4) frac = (int)((x >> (msb - 4)) & 0xF);
    else          frac = (int)((x << (4 - msb)) & 0xF);
    return (msb << 4) | frac;
}

static int hls_norm(ap_uint<64> v, int shift, int norm_max) {
#pragma HLS INLINE
    ap_uint<64> n = v >> shift;
    if (n > (ap_uint<64>)norm_max) return norm_max;
    return (int)n;
}

static ap_uint<32> abs_i64(ap_int<64> v) {
#pragma HLS INLINE
    return (v < 0) ? (ap_uint<32>)(-v) : (ap_uint<32>)v;
}

// ----------------------------------------------------------------------------
void gnss_metric_hls(
    hls::stream<axis_tapped_t>     &tap_in,
    hls::stream<axis_metric_pkt_t> &metric_out,
    ap_uint<32>  window_id,
    ap_uint<48>  power_prev,
    ap_uint<32>  noise_prev,
    ap_uint<48> &power_cur,
    ap_uint<32> &noise_cur)
{
#pragma HLS INTERFACE axis port=tap_in
#pragma HLS INTERFACE axis port=metric_out
#pragma HLS INTERFACE s_axilite port=window_id  bundle=ctrl
#pragma HLS INTERFACE s_axilite port=power_prev bundle=ctrl
#pragma HLS INTERFACE s_axilite port=noise_prev bundle=ctrl
#pragma HLS INTERFACE s_axilite port=power_cur  bundle=ctrl
#pragma HLS INTERFACE s_axilite port=noise_cur  bundle=ctrl
#pragma HLS INTERFACE s_axilite port=return     bundle=ctrl

    ap_uint<48> power_acc = 0;
    ap_uint<41> blk_sum[NUM_SUBBLOCKS];
#pragma HLS ARRAY_PARTITION variable=blk_sum complete dim=1
    for (int b = 0; b < NUM_SUBBLOCKS; ++b) {
#pragma HLS UNROLL
        blk_sum[b] = 0;
    }

    ap_int<32> IcorrE = 0, QcorrE = 0, IcorrP = 0, QcorrP = 0, IcorrL = 0, QcorrL = 0;
    ap_int<48> dopp_acc = 0;
    ap_int<16> prev_i = 0, prev_q = 0;
    bool first = true;
    ap_uint<32> cnt = 0;

ACC_LOOP:
    for (bool last = false; !last; ) {
#pragma HLS PIPELINE II=1
        axis_tapped_t t = tap_in.read();
        ap_uint<64> w = t.data;
        last = (t.last != 0);

        ap_int<16> mi = (ap_int<16>)(ap_uint<16>)w(15, 0);
        ap_int<16> mq = (ap_int<16>)(ap_uint<16>)w(31, 16);
        ap_int<2>  ce = w[32] ? (ap_int<2>)1 : (ap_int<2>)-1;
        ap_int<2>  cp = w[33] ? (ap_int<2>)1 : (ap_int<2>)-1;
        ap_int<2>  cl = w[34] ? (ap_int<2>)1 : (ap_int<2>)-1;
        ap_uint<11> sidx = (ap_uint<11>)w(45, 35);

        ap_uint<32> p = (ap_uint<32>)(mi * mi) + (ap_uint<32>)(mq * mq);
        power_acc += p;
        ap_uint<3> blk = sidx(9, 7);
        blk_sum[blk] += p;

        IcorrE += mi * ce; QcorrE += mq * ce;
        IcorrP += mi * cp; QcorrP += mq * cp;
        IcorrL += mi * cl; QcorrL += mq * cl;

        ap_int<16> pi = first ? (ap_int<16>)0 : prev_i;
        ap_int<16> pq = first ? (ap_int<16>)0 : prev_q;
        ap_int<41> cross = (ap_int<41>)(mq * pi) - (ap_int<41>)(mi * pq);
        dopp_acc += (cross < 0) ? (ap_int<48>)(-cross) : (ap_int<48>)cross;

        prev_i = mi; prev_q = mq; first = false;
        cnt++;
    }

    // ---- noise: min sub-block mean, smoothed ----
    ap_uint<34> blk_min = (ap_uint<34>)(blk_sum[0] >> SUBBLOCK_LOG2);
    for (int b = 1; b < NUM_SUBBLOCKS; ++b) {
        ap_uint<34> m = (ap_uint<34>)(blk_sum[b] >> SUBBLOCK_LOG2);
        if (m < blk_min) blk_min = m;
    }
    ap_uint<32> noise_est;
    if (noise_prev == 0) {
        noise_est = (ap_uint<32>)blk_min;
    } else {
        ap_int<41> diff = (ap_int<41>)blk_min - (ap_int<41>)noise_prev;
        noise_est = (ap_uint<32>)((ap_int<41>)noise_prev + (diff >> NOISE_SMOOTH_SHIFT));
    }

    ap_uint<32> corr_e = abs_i64(IcorrE) + abs_i64(QcorrE);
    ap_uint<32> corr_p = abs_i64(IcorrP) + abs_i64(QcorrP);
    ap_uint<32> corr_l = abs_i64(IcorrL) + abs_i64(QcorrL);
    ap_uint<32> sym = (corr_e > corr_l) ? (corr_e - corr_l) : (corr_l - corr_e);

    ap_uint<48> pjump = (power_acc > power_prev) ? (ap_uint<48>)(power_acc - power_prev)
                                                 : (ap_uint<48>)(power_prev - power_acc);

    int lc = hls_log2_fx((ap_uint<64>)corr_p);
    int ln = hls_log2_fx((ap_uint<64>)noise_est);
    int cn0v = CN0_K * (lc - ln) + CN0_OFFSET;
    if (cn0v < 0) cn0v = 0; else if (cn0v > CN0_MAX) cn0v = CN0_MAX;
    int cn0ab = CN0_HEALTHY_REF - cn0v;
    if (cn0ab < 0) cn0ab = 0; else if (cn0ab > CN0_ABNORMAL_MAX) cn0ab = CN0_ABNORMAL_MAX;

    ap_int<34> repl_s = (ap_int<34>)corr_e + (ap_int<34>)corr_l - (ap_int<34>)corr_p;
    ap_uint<33> replica = (repl_s < 0) ? (ap_uint<33>)0 : (ap_uint<33>)repl_s;
    ap_int<64> coll_s = (ap_int<64>)CORR_PROMPT_REF - (ap_int<64>)corr_p;
    ap_uint<64> collapse = (coll_s < 0) ? (ap_uint<64>)0 : (ap_uint<64>)coll_s;

    int nSym  = hls_norm((ap_uint<64>)sym,       SYM_NORM_SHIFT,    NORM_MAX);
    int nDop  = hls_norm((ap_uint<64>)dopp_acc,  DOPP_NORM_SHIFT,   NORM_MAX);
    int nCn0  = hls_norm((ap_uint<64>)cn0ab,     CN0ABN_NORM_SHIFT, NORM_MAX);
    int nRepl = hls_norm((ap_uint<64>)replica,   REPL_NORM_SHIFT,   NORM_MAX);
    int nPwr  = hls_norm((ap_uint<64>)power_acc, PWR_NORM_SHIFT,    NORM_MAX);
    int nCol  = hls_norm(collapse,               COLLAPSE_NORM_SHIFT, NORM_MAX);
    int nTone = hls_norm((ap_uint<64>)noise_est, TONE_NORM_SHIFT,   NORM_MAX);

    int spoof = W_SYM*nSym + W_DOP*nDop + W_CN0*nCn0 + W_REPL*nRepl;
    int jam   = W_PWR*nPwr + W_LOWCN0*nCn0 + W_COLLAPSE*nCol + W_TONE*nTone;
    if (spoof > SCORE_MAX) spoof = SCORE_MAX;
    if (jam   > SCORE_MAX) jam   = SCORE_MAX;

    // ---- pack metric bundle ----
    ap_uint<512> out = 0;
    out(B_WINDOW_O + 31, B_WINDOW_O) = window_id;
    out(B_POWER_O  + 47, B_POWER_O)  = power_acc;
    out(B_NOISE_O  + 31, B_NOISE_O)  = noise_est;
    out(B_CN0_O    + 31, B_CN0_O)    = (ap_uint<32>)cn0v;
    out(B_CP_O     + 31, B_CP_O)     = corr_p;
    out(B_CE_O     + 31, B_CE_O)     = corr_e;
    out(B_CL_O     + 31, B_CL_O)     = corr_l;
    out(B_SYM_O    + 31, B_SYM_O)    = sym;
    out(B_DOPP_O   + 47, B_DOPP_O)   = (ap_uint<48>)dopp_acc;
    out(B_PJUMP_O  + 47, B_PJUMP_O)  = pjump;
    out(B_SPOOF_O  + 31, B_SPOOF_O)  = (ap_uint<32>)spoof;
    out(B_JAM_O    + 31, B_JAM_O)    = (ap_uint<32>)jam;
    out(B_SCNT_O   + 31, B_SCNT_O)   = cnt;

    axis_metric_pkt_t obeat;
    obeat.data = out;
    obeat.last = 1;
    obeat.keep = -1;
    obeat.strb = -1;
    metric_out.write(obeat);

    power_cur = power_acc;
    noise_cur = noise_est;
}
