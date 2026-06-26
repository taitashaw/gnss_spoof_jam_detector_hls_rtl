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
typedef ap_fixed<34, 6, AP_RND_CONV, AP_SAT> fmul_t;

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

// Scaled radix-2 DIT FFT. inverse=false: forward (twiddle exp(-j...)). inverse=true:
// uses conjugate twiddles; the /N normalisation comes from the per-stage halving.
static void fft_fixed(const fdata_t in_re[FFT_N], const fdata_t in_im[FFT_N],
                      fdata_t out_re[FFT_N], fdata_t out_im[FFT_N], bool inverse) {
    // bit-reversed input load
LOAD: for (int i = 0; i < FFT_N; ++i) {
#pragma HLS PIPELINE II=1
        unsigned j = fft_bitrev((unsigned)i);
        out_re[j] = in_re[i];
        out_im[j] = in_im[i];
    }

STAGE: for (int s = 0; s < FFT_LOG2N; ++s) {
        int m       = 1 << (s + 1);   // butterfly span
        int half    = m >> 1;
        int tw_step = FFT_N / m;       // twiddle index step
    GROUP: for (int k = 0; k < FFT_N; k += m) {
        BFLY: for (int j = 0; j < half; ++j) {
#pragma HLS PIPELINE II=1
                int idx = j * tw_step;
                twid_t wr = FFT_W_RE[idx];
                twid_t wi = inverse ? (twid_t)(-FFT_W_IM[idx]) : FFT_W_IM[idx];

                fdata_t br = out_re[k + j + half];
                fdata_t bi = out_im[k + j + half];
                fmul_t tr = (fmul_t)(wr * br) - (fmul_t)(wi * bi);
                fmul_t ti = (fmul_t)(wr * bi) + (fmul_t)(wi * br);

                fmul_t ar = (fmul_t)out_re[k + j];
                fmul_t ai = (fmul_t)out_im[k + j];

                out_re[k + j]        = (fdata_t)((ar + tr) * (fmul_t)0.5);
                out_im[k + j]        = (fdata_t)((ai + ti) * (fmul_t)0.5);
                out_re[k + j + half] = (fdata_t)((ar - tr) * (fmul_t)0.5);
                out_im[k + j + half] = (fdata_t)((ai - ti) * (fmul_t)0.5);
            }
        }
    }
}

#endif // FFT_FIXED_HPP
