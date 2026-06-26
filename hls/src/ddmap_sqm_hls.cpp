// ============================================================================
// ddmap_sqm_hls.cpp -- synthesizable hls::fft ddMap / SQM detector kernel
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Computes one delay-Doppler-map cell for a real GPS C/A PRN: it FFT-correlates
// each pre-wiped 1 ms block against the locally generated C/A code, coherently
// accumulates the complex correlation across N_BLK blocks (the DBZP coherent-gain
// step), and reads the spoof statistic off the resulting code-phase profile --
// the early/prompt/late signal-quality-monitoring (SQM) distortion. This is the
// synthesizable core of scripts/dbzp_acq.py; the carrier-Doppler wipeoff and the
// outer PRN/Doppler search loop are the host's job (one cell per call).
//
//   FFT_SIZE = 2048 (max_nfft = 11), SAMP_PER_CHIP = 2  -> NS = 2046 used samples.
//   hls::fft, scaled, natural order, 16-bit fixed point.
//
// Verified against the Python golden at the matched 2-samples/chip config
// (tb_ddmap_sqm_hls.cpp). NO floating point. axis input, s_axilite control.
// ============================================================================
#include "hls_fft.h"
#include "ap_fixed.h"
#include "ap_int.h"
#include "hls_stream.h"
#include "ap_axi_sdata.h"
#include <complex>

#define FFT_NFFT      11
#define FFT_SIZE      2048
#define CA_LEN        1023
#define SAMP_PER_CHIP 2
#define NS            2046      // SAMP_PER_CHIP * CA_LEN
#define N_BLK         4         // coherent blocks (ms) per ddMap cell

// ---- FFT configuration (16-bit, scaled, natural order) ----------------------
struct fft_cfg : hls::ip_fft::params_t {
    static const unsigned max_nfft       = FFT_NFFT;
    static const unsigned input_width    = 16;
    static const unsigned output_width   = 16;
    static const unsigned config_width   = 16;
    static const unsigned scaling_opt    = hls::ip_fft::scaled;
    static const unsigned ordering_opt   = hls::ip_fft::natural_order;
    static const unsigned phase_factor_width = 16;
};

// the hls::fft fixed-point data type is ap_fixed<16,1> (range ~ +/-1)
typedef ap_fixed<16, 1>  fft_data_t;
typedef std::complex<fft_data_t> cpx_t;
typedef ap_fixed<48, 24> acc_t;            // coherent accumulator (wide)
typedef std::complex<acc_t> cpxacc_t;

typedef ap_axiu<32, 0, 0, 0> axis_iq_t;    // 16b I in [31:16], 16b Q in [15:0]

// scaling schedule (scaled mode): ~divide by 2 per radix-2 stage so the FFT
// outputs stay inside +/-1. Magnitudes are scaled uniformly; the peak location
// and the early/late distortion RATIO are scale-invariant (the verified outputs).
#define SCALE_SCHED 0x2AB

static void run_fft(bool forward, cpx_t in[FFT_SIZE], cpx_t out[FFT_SIZE]) {
#pragma HLS INLINE off
    bool ovflo = false;
    unsigned blk_exp = 0;
    hls::fft<fft_cfg>(in, out, forward, SCALE_SCHED, -1, &ovflo, &blk_exp);
}

// ---- real GPS C/A code (G1/G2 LFSR, IS-GPS-200) -> upsampled +/-1 -----------
static void gen_ca_upsampled(int prn, fft_data_t code_up[FFT_SIZE]) {
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
    // chip[i] = -(g1[i] * g2[(i+shift) mod 1023]); upsample (2 samples/chip)
UP: for (int k = 0; k < FFT_SIZE; ++k) {
        if (k < NS) {
            int ci = ((long)(k + 1) * CA_LEN + NS - 1) / NS - 1;   // ceil((k+1)*1023/NS)-1
            if (ci < 0) ci = 0; if (ci >= CA_LEN) ci = CA_LEN - 1;
            int gi = (ci + shift) % CA_LEN;
            ap_int<2> chip = -(g1[ci] * g2[gi]);
            code_up[k] = (chip > 0) ? fft_data_t(0.5) : fft_data_t(-0.5);  // headroom
        } else {
            code_up[k] = fft_data_t(0);   // zero-pad NS..FFT_SIZE
        }
    }
}

// ============================================================================
void ddmap_sqm_hls(
    hls::stream<axis_iq_t> &iq_in,   // N_BLK * FFT_SIZE pre-wiped complex samples
    ap_uint<8>   prn,
    ap_uint<48> &peak_power,         // |coherent corr|^2 at the peak
    ap_uint<16> &code_phase,
    ap_uint<32> &distortion_q16,     // early/late distortion in Q16 (0..65536)
    ap_uint<48> &early_power,
    ap_uint<48> &late_power)
{
#pragma HLS INTERFACE axis port=iq_in
#pragma HLS INTERFACE s_axilite port=prn         bundle=ctrl
#pragma HLS INTERFACE s_axilite port=peak_power  bundle=ctrl
#pragma HLS INTERFACE s_axilite port=code_phase  bundle=ctrl
#pragma HLS INTERFACE s_axilite port=distortion_q16 bundle=ctrl
#pragma HLS INTERFACE s_axilite port=early_power bundle=ctrl
#pragma HLS INTERFACE s_axilite port=late_power  bundle=ctrl
#pragma HLS INTERFACE s_axilite port=return      bundle=ctrl

    static fft_data_t code_up[FFT_SIZE];
    static cpx_t code_cpx[FFT_SIZE], code_fd[FFT_SIZE];
    static cpx_t blk[FFT_SIZE], blk_fd[FFT_SIZE], prod[FFT_SIZE], corr[FFT_SIZE];
    static cpxacc_t accum[FFT_SIZE];
#pragma HLS BIND_STORAGE variable=accum type=ram_2p impl=bram

    // local code -> frequency domain (once)
    gen_ca_upsampled(prn, code_up);
    for (int i = 0; i < FFT_SIZE; ++i) code_cpx[i] = cpx_t(code_up[i], fft_data_t(0));
    run_fft(true, code_cpx, code_fd);

    for (int i = 0; i < FFT_SIZE; ++i) accum[i] = cpxacc_t(acc_t(0), acc_t(0));

BLOCKS: for (int b = 0; b < N_BLK; ++b) {
        // read one pre-wiped block, normalize int16 -> ~[-0.5,0.5)
        for (int i = 0; i < FFT_SIZE; ++i) {
#pragma HLS PIPELINE II=1
            axis_iq_t s = iq_in.read();
            ap_int<16> ii = s.data(31, 16);
            ap_int<16> qq = s.data(15, 0);
            blk[i].real(fft_data_t(ii) / fft_data_t(65536));
            blk[i].imag(fft_data_t(qq) / fft_data_t(65536));
        }
        run_fft(true, blk, blk_fd);
        // circular cross-correlation: blk_fd * conj(code_fd)
        for (int i = 0; i < FFT_SIZE; ++i) {
#pragma HLS PIPELINE II=1
            ap_fixed<32, 4> ar = blk_fd[i].real(), ai = blk_fd[i].imag();
            ap_fixed<32, 4> br = code_fd[i].real(), bi = code_fd[i].imag();  // conj -> -bi
            prod[i] = cpx_t(fft_data_t(ar * br + ai * bi),
                            fft_data_t(ai * br - ar * bi));
        }
        run_fft(false, prod, corr);             // IFFT -> 1 ms correlation
        for (int i = 0; i < FFT_SIZE; ++i) {
#pragma HLS PIPELINE II=1
            accum[i] = cpxacc_t(accum[i].real() + acc_t(corr[i].real()),
                                accum[i].imag() + acc_t(corr[i].imag()));
        }
    }

    // |coherent corr|^2 profile -> peak + early/late SQM (fixed-point power)
    typedef ap_ufixed<64, 32> pw_t;
    pw_t best = 0; ap_uint<16> bi = 0;
SQM: for (int i = 0; i < NS; ++i) {
#pragma HLS PIPELINE II=1
        acc_t re = accum[i].real(), im = accum[i].imag();
        pw_t p = (pw_t)(re * re) + (pw_t)(im * im);
        if (p > best) { best = p; bi = i; }
    }
    int e = (bi - SAMP_PER_CHIP / 2 + NS) % NS;   // +/-0.5 chip
    int l = (bi + SAMP_PER_CHIP / 2) % NS;
    acc_t er = accum[e].real(), ei = accum[e].imag();
    acc_t lr = accum[l].real(), li = accum[l].imag();
    pw_t ep = (pw_t)(er * er) + (pw_t)(ei * ei);
    pw_t lp = (pw_t)(lr * lr) + (pw_t)(li * li);

    pw_t sum = ep + lp;
    pw_t diff = (ep > lp) ? (ep - lp) : (lp - ep);
    ap_uint<32> dist = 0;
    if (sum > 0) dist = (ap_uint<32>)((ap_ufixed<64, 32>)(diff / sum) * 65536);  // Q16

    // output: power scaled to integer range (relative comparison; ratios invariant)
    peak_power = (ap_uint<48>)(best * pw_t(1 << 20));
    code_phase = bi;
    distortion_q16 = dist;
    early_power = (ap_uint<48>)(ep * pw_t(1 << 20));
    late_power  = (ap_uint<48>)(lp * pw_t(1 << 20));
}
