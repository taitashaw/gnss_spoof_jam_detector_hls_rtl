// ============================================================================
// ddmap_sqm_hls.cpp -- ddMap / SQM detector kernel (own fixed-point FFT)
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Computes one delay-Doppler-map cell for a real GPS C/A PRN: it FFT-correlates
// each pre-wiped 1 ms block against the locally generated C/A code, coherently
// accumulates the complex correlation across N_BLK blocks (the DBZP coherent-gain
// step), and reads the spoof statistic off the resulting code-phase profile --
// the early/prompt/late signal-quality-monitoring (SQM) distortion. Synthesizable
// core of scripts/dbzp_acq.py; carrier wipeoff + PRN/Doppler search are the host's.
//
// The FFT is our own from-scratch fixed-point radix-2 DIT (fft_fixed.hpp), numpy-
// verified (>= 50 dB SNR). It replaces the Xilinx hls_fft.h path, whose bit-accurate
// C-model aborted csim with an integer-divide SIGFPE -- with our FFT, csim runs.
// NO hls_fft.h, NO vendor FFT model, NO floating point in the body.
//
//   FFT_N = 2048, SAMP_PER_CHIP = 2 -> NS = 2046 used samples, N_BLK = 4 blocks.
//   axis input (16b I / 16b Q), s_axilite control.
// ============================================================================
#include "fft_fixed.hpp"
#include "ap_int.h"
#include "hls_stream.h"
#include "ap_axi_sdata.h"

#define CA_LEN        1023
#define SAMP_PER_CHIP 2
#define NS            2046      // SAMP_PER_CHIP * CA_LEN
#define N_BLK         4         // coherent blocks (ms) per ddMap cell
#define PROD_GAIN     16384.0   // 2^14 spectral-product rescale (see correlation loop)

typedef ap_fixed<48, 24> acc_t;            // coherent accumulator (wide)
typedef ap_ufixed<64, 32> pw_t;            // power
typedef ap_axiu<32, 0, 0, 0> axis_iq_t;    // 16b I in [31:16], 16b Q in [15:0]

// ---- real GPS C/A code (G1/G2 LFSR, IS-GPS-200) -> upsampled +/-0.5 ----------
static void gen_ca_upsampled(int prn, fdata_t code_re[FFT_N], fdata_t code_im[FFT_N]) {
    static const int g2s[32] = {
        5,6,7,8,17,18,139,140,141,251,252,254,255,256,257,258,
        469,470,471,472,473,474,509,512,513,514,515,516,859,860,861,862};
    ap_int<2> g1[CA_LEN], g2[CA_LEN];
    ap_int<2> r1[10], r2[10];
    for (int i = 0; i < 10; ++i) { r1[i] = -1; r2[i] = -1; }
GEN: for (int i = 0; i < CA_LEN; ++i) {
        g1[i] = r1[9];
        g2[i] = r2[9];
        ap_int<2> fb1 = r1[2] * r1[9];
        ap_int<2> fb2 = r2[1] * r2[2] * r2[5] * r2[7] * r2[8] * r2[9];
        for (int k = 9; k > 0; --k) { r1[k] = r1[k-1]; r2[k] = r2[k-1]; }
        r1[0] = fb1; r2[0] = fb2;
    }
    int shift = g2s[prn - 1];
UP: for (int k = 0; k < FFT_N; ++k) {
        code_im[k] = fdata_t(0);
        if (k < NS) {
            int ci = ((long)(k + 1) * CA_LEN + NS - 1) / NS - 1;   // ceil((k+1)*1023/NS)-1
            if (ci < 0) ci = 0; if (ci >= CA_LEN) ci = CA_LEN - 1;
            // g2 phase select matches numpy roll(g2, shift): g2[(ci - shift) mod 1023]
            int gi = (ci - shift + CA_LEN) % CA_LEN;
            ap_int<2> chip = -(g1[ci] * g2[gi]);
            code_re[k] = (chip > 0) ? fdata_t(0.5) : fdata_t(-0.5);
        } else {
            code_re[k] = fdata_t(0);   // zero-pad NS..FFT_N
        }
    }
}

// ============================================================================
void ddmap_sqm_hls(
    hls::stream<axis_iq_t> &iq_in,   // N_BLK * FFT_N pre-wiped complex samples
    ap_uint<8>   prn,
    ap_uint<48> &peak_power,         // |coherent corr|^2 at the peak
    ap_uint<16> &code_phase,
    ap_uint<32> &distortion_q16,     // early/late distortion in Q16 (0..65536)
    ap_uint<48> &early_power,
    ap_uint<48> &late_power)
{
#pragma HLS INTERFACE axis port=iq_in
#pragma HLS INTERFACE s_axilite port=prn            bundle=ctrl
#pragma HLS INTERFACE s_axilite port=peak_power     bundle=ctrl
#pragma HLS INTERFACE s_axilite port=code_phase     bundle=ctrl
#pragma HLS INTERFACE s_axilite port=distortion_q16 bundle=ctrl
#pragma HLS INTERFACE s_axilite port=early_power    bundle=ctrl
#pragma HLS INTERFACE s_axilite port=late_power     bundle=ctrl
#pragma HLS INTERFACE s_axilite port=return         bundle=ctrl

    static fdata_t code_re[FFT_N], code_im[FFT_N], code_fd_re[FFT_N], code_fd_im[FFT_N];
    static fdata_t blk_re[FFT_N], blk_im[FFT_N], blk_fd_re[FFT_N], blk_fd_im[FFT_N];
    static fdata_t prod_re[FFT_N], prod_im[FFT_N], corr_re[FFT_N], corr_im[FFT_N];
    static acc_t accum_re[FFT_N], accum_im[FFT_N];
#pragma HLS BIND_STORAGE variable=accum_re type=ram_2p impl=bram
#pragma HLS BIND_STORAGE variable=accum_im type=ram_2p impl=bram

    // local code -> frequency domain (once)
    gen_ca_upsampled(prn, code_re, code_im);
    fft_fixed(code_re, code_im, code_fd_re, code_fd_im, false);

    for (int i = 0; i < FFT_N; ++i) { accum_re[i] = acc_t(0); accum_im[i] = acc_t(0); }

BLOCKS: for (int b = 0; b < N_BLK; ++b) {
        // read one pre-wiped block, normalize int16 -> ~[-0.5,0.5)
        for (int i = 0; i < FFT_N; ++i) {
#pragma HLS PIPELINE II=1
            axis_iq_t s = iq_in.read();
            ap_int<16> ii = s.data(31, 16);
            ap_int<16> qq = s.data(15, 0);
            blk_re[i] = fdata_t(ii) / fdata_t(65536);
            blk_im[i] = fdata_t(qq) / fdata_t(65536);
        }
        fft_fixed(blk_re, blk_im, blk_fd_re, blk_fd_im, false);
        // circular cross-correlation: blk_fd * conj(code_fd), rescaled up.
        // The two scaled (/N) FFTs and the spectral product shrink magnitudes to
        // ~1e-5; PROD_GAIN brings the product back to O(1) so the IFFT keeps full
        // fixed-point precision. A uniform gain is scale-invariant for the peak
        // location and the early/late distortion ratio (the outputs we use).
        for (int i = 0; i < FFT_N; ++i) {
#pragma HLS PIPELINE II=1
            fmul_t ar = (fmul_t)blk_fd_re[i], ai = (fmul_t)blk_fd_im[i];
            fmul_t br = (fmul_t)code_fd_re[i], bi = (fmul_t)code_fd_im[i];  // conj -> -bi
            prod_re[i] = (fdata_t)((ar * br + ai * bi) * (fmul_t)PROD_GAIN);
            prod_im[i] = (fdata_t)((ai * br - ar * bi) * (fmul_t)PROD_GAIN);
        }
        fft_fixed(prod_re, prod_im, corr_re, corr_im, true);   // IFFT -> 1 ms corr
        for (int i = 0; i < FFT_N; ++i) {
#pragma HLS PIPELINE II=1
            accum_re[i] = accum_re[i] + acc_t(corr_re[i]);
            accum_im[i] = accum_im[i] + acc_t(corr_im[i]);
        }
    }

    // |coherent corr|^2 profile -> peak + early/late SQM
    pw_t best = 0; ap_uint<16> bi = 0;
SQM: for (int i = 0; i < NS; ++i) {
#pragma HLS PIPELINE II=1
        acc_t re = accum_re[i], im = accum_im[i];
        pw_t p = (pw_t)(re * re) + (pw_t)(im * im);
        if (p > best) { best = p; bi = i; }
    }
    int e = (bi - SAMP_PER_CHIP / 2 + NS) % NS;   // +/-0.5 chip
    int l = (bi + SAMP_PER_CHIP / 2) % NS;
    acc_t er = accum_re[e], ei = accum_im[e];
    acc_t lr = accum_re[l], li = accum_im[l];
    pw_t ep = (pw_t)(er * er) + (pw_t)(ei * ei);
    pw_t lp = (pw_t)(lr * lr) + (pw_t)(li * li);

    pw_t sum = ep + lp;
    pw_t diff = (ep > lp) ? (ep - lp) : (lp - ep);
    ap_uint<32> dist = 0;
    if (sum > 0) dist = (ap_uint<32>)((ap_ufixed<64, 32>)(diff / sum) * 65536);  // Q16

    peak_power = (ap_uint<48>)(best * pw_t(1 << 20));
    code_phase = bi;
    distortion_q16 = dist;
    early_power = (ap_uint<48>)(ep * pw_t(1 << 20));
    late_power  = (ap_uint<48>)(lp * pw_t(1 << 20));
}
