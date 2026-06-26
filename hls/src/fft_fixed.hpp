// ============================================================================
// fft_fixed.hpp -- from-scratch synthesizable fixed-point radix-2 DIT FFT
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// A self-contained fixed-point FFT to replace the Xilinx hls_fft.h path (whose
// bit-accurate C-model aborts csim with an integer-divide SIGFPE). NO hls_fft.h,
// NO vendor FFT model, NO floating point in the synthesizable body.
//
//   * Radix-2 decimation-in-time, length FFT_N = 2048 (FFT_LOG2N = 11 stages).
//   * Twiddles W[k] = exp(-j 2 pi k / N) live in a compile-time ROM
//     (fft_twiddle_{re,im}.inc): the double literals are converted to fixed point
//     by the compiler, so the hardware sees only constants.
//   * Per-stage scaling: each butterfly output is halved (divide by 2 per stage,
//     total /N) so the values stay in range -- the classic "scaled" FFT. Output is
//     ~ DFT/N. For acquisition the peak location and the early/late distortion ratio
//     are scale-invariant, so the /N factor is harmless.
//   * Rounding: AP_RND_CONV (convergent) on every fixed-point result to minimise
//     bias; saturation on overflow.
//
// Verified standalone against numpy.fft with a hard accuracy bound before use
// (hls/tb/tb_fft_fixed.cpp).
// ============================================================================
#ifndef FFT_FIXED_HPP
#define FFT_FIXED_HPP

#include "ap_fixed.h"
#include "ap_int.h"

#define FFT_LOG2N 11
#define FFT_N     2048

// data: 4 integer bits (range ~ +/-8 headroom), 20 fractional bits, convergent
// rounding + saturation. twiddle: |W| <= 1, 16 fractional bits. product accumulator
// is wider to keep the complex-multiply exact before rounding back to fdata_t.
typedef ap_fixed<24, 4, AP_RND_CONV, AP_SAT> fdata_t;
typedef ap_fixed<18, 2, AP_RND_CONV, AP_SAT> twid_t;
// products/sums: plain truncate+wrap (no saturate/round logic on the hot butterfly
// path -- numerically negligible at 28 fractional bits; rounding stays on fdata_t).
typedef ap_fixed<34, 6> fmul_t;

static const twid_t FFT_W_RE[FFT_N / 2] = {
#include "fft_twiddle_re.inc"
};
static const twid_t FFT_W_IM[FFT_N / 2] = {
#include "fft_twiddle_im.inc"
};

static inline unsigned fft_bitrev(unsigned x) {
    unsigned r = 0;
BR: for (int i = 0; i < FFT_LOG2N; ++i) {
#pragma HLS UNROLL
        r = (r << 1) | (x & 1u);
        x >>= 1;
    }
    return r;
}

// One radix-2 stage: reads src[], writes dst[] (DISTINCT memories, so two reads
// from src + two writes to dst are conflict-free -> the flattened butterfly closes
// II=1). The four real multiplies are bound to pipelined DSP48E2 (latency 3 -> A/B,
// M and P internal registers, the fast-butterfly technique).
static void fft_stage(int s, bool inverse,
                      const fdata_t src_re[FFT_N], const fdata_t src_im[FFT_N],
                      fdata_t dst_re[FFT_N], fdata_t dst_im[FFT_N]) {
    int half  = 1 << s;
    int shamt = FFT_LOG2N - 1 - s;   // tw_step = 2^shamt -> idx = j << shamt (no mul)
BFLY: for (int bf = 0; bf < FFT_N / 2; ++bf) {
#pragma HLS PIPELINE II=1
        int j     = bf & (half - 1);
        int g     = bf >> s;
        int a_idx = (g << (s + 1)) + j;
        int b_idx = a_idx + half;
        int idx   = j << shamt;

        twid_t wr = FFT_W_RE[idx];
        twid_t wi = inverse ? (twid_t)(-FFT_W_IM[idx]) : FFT_W_IM[idx];

        fdata_t br = src_re[b_idx];
        fdata_t bi = src_im[b_idx];

        fmul_t prr = wr * br;
        fmul_t pii = wi * bi;
        fmul_t prb = wr * bi;
        fmul_t pib = wi * br;
#pragma HLS BIND_OP variable=prr op=mul impl=dsp latency=3
#pragma HLS BIND_OP variable=pii op=mul impl=dsp latency=3
#pragma HLS BIND_OP variable=prb op=mul impl=dsp latency=3
#pragma HLS BIND_OP variable=pib op=mul impl=dsp latency=3

        fmul_t tr = prr - pii;
        fmul_t ti = prb + pib;
        fmul_t ar = (fmul_t)src_re[a_idx];
        fmul_t ai = (fmul_t)src_im[a_idx];

        dst_re[a_idx] = (fdata_t)((ar + tr) * (fmul_t)0.5);
        dst_im[a_idx] = (fdata_t)((ai + ti) * (fmul_t)0.5);
        dst_re[b_idx] = (fdata_t)((ar - tr) * (fmul_t)0.5);
        dst_im[b_idx] = (fdata_t)((ai - ti) * (fmul_t)0.5);
    }
}

// Scaled radix-2 DIT FFT. Ping-pong between two physical buffers (A, B): even stages
// read A write B, odd stages read B write A. Because each fft_stage call binds src
// and dst to DISTINCT arrays, the per-stage butterfly is conflict-free and pipelines
// at II=1 -- the key to timing closure. inverse=true uses conjugate twiddles; /N
// normalisation comes from the per-stage halving.
static void fft_fixed(const fdata_t in_re[FFT_N], const fdata_t in_im[FFT_N],
                      fdata_t out_re[FFT_N], fdata_t out_im[FFT_N], bool inverse) {
    static fdata_t A_re[FFT_N], A_im[FFT_N], B_re[FFT_N], B_im[FFT_N];

    // bit-reversed input load into A
LOAD: for (int i = 0; i < FFT_N; ++i) {
#pragma HLS PIPELINE II=1
        unsigned j = fft_bitrev((unsigned)i);
        A_re[j] = in_re[i];
        A_im[j] = in_im[i];
    }

STAGE: for (int s = 0; s < FFT_LOG2N; ++s) {
        if ((s & 1) == 0) fft_stage(s, inverse, A_re, A_im, B_re, B_im);
        else              fft_stage(s, inverse, B_re, B_im, A_re, A_im);
    }

    // LOG2N=11 (odd): last stage (s=10, even) wrote B -> result is in B
OUT: for (int i = 0; i < FFT_N; ++i) {
#pragma HLS PIPELINE II=1
        out_re[i] = B_re[i];
        out_im[i] = B_im[i];
    }
}

#endif // FFT_FIXED_HPP
