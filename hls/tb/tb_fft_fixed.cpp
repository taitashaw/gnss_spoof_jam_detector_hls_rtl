// ============================================================================
// tb_fft_fixed.cpp -- accuracy gate for the from-scratch fixed-point FFT vs numpy
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Runs fft_fixed (forward) on each test vector and compares against the numpy.fft
// golden (scripts/gen_fft_vectors.py). Reports max bin error, RMS error, effective
// SNR and ENOB per case, plus an inverse-FFT round-trip check. HARD PASS BOUND:
// every case must reach >= MIN_SNR_DB (documented below). Runs in plain HLS csim /
// g++ -- NO vendor FFT model, so it actually executes. Returns non-zero on failure.
//
// Pass the repo root as argv[1].
// ============================================================================
#include "../src/fft_fixed.hpp"
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <string>
#include <vector>

// Hard accuracy gate. For GNSS code correlation the FFT must preserve the
// correlation peak and the early/late samples well; ~8 effective bits (>= 50 dB)
// is comfortable headroom over the ~5-6 bit input quantisation. We require 50 dB.
static const double MIN_SNR_DB = 50.0;

static bool load_cplx(const std::string &path, std::vector<double> &re,
                      std::vector<double> &im) {
    FILE *f = fopen(path.c_str(), "r");
    if (!f) { printf("  cannot open %s\n", path.c_str()); return false; }
    double r, i;
    while (fscanf(f, "%lf %lf", &r, &i) == 2) { re.push_back(r); im.push_back(i); }
    fclose(f);
    return (int)re.size() == FFT_N;
}

static double run_case(const std::string &dir, const std::string &name,
                       double &enob, double &maxerr) {
    std::vector<double> xr, xi, gr, gi;
    if (!load_cplx(dir + "in_" + name + ".txt", xr, xi)) return -1;
    if (!load_cplx(dir + "gold_" + name + ".txt", gr, gi)) return -1;

    static fdata_t in_re[FFT_N], in_im[FFT_N], out_re[FFT_N], out_im[FFT_N];
    for (int k = 0; k < FFT_N; ++k) { in_re[k] = (fdata_t)xr[k]; in_im[k] = (fdata_t)xi[k]; }
    fft_fixed(in_re, in_im, out_re, out_im, false);

    double serr = 0, ssig = 0; maxerr = 0;
    for (int k = 0; k < FFT_N; ++k) {
        double er = (double)out_re[k] - gr[k];
        double ei = (double)out_im[k] - gi[k];
        double e2 = er * er + ei * ei;
        serr += e2;
        ssig += gr[k] * gr[k] + gi[k] * gi[k];
        if (std::sqrt(e2) > maxerr) maxerr = std::sqrt(e2);
    }
    double err_rms = std::sqrt(serr / FFT_N);
    double sig_rms = std::sqrt(ssig / FFT_N);
    double snr = 20.0 * std::log10(sig_rms / (err_rms + 1e-30));
    enob = (snr - 1.76) / 6.02;
    printf("  %-10s  maxErr=%.2e  rmsErr=%.2e  SNR=%6.2f dB  ENOB=%4.1f  %s\n",
           name.c_str(), maxerr, err_rms, snr, enob, snr >= MIN_SNR_DB ? "PASS" : "FAIL");
    return snr;
}

int main(int argc, char **argv) {
    std::string root = (argc > 1) ? argv[1] : ".";
    std::string dir = root + "/vectors/fft_test/";
    const char *cases[] = {"impulse", "impulse7", "tone", "random", "ca_block"};
    int n = 5, fails = 0;

    printf("fixed-point FFT accuracy vs numpy.fft (hard gate: SNR >= %.0f dB):\n", MIN_SNR_DB);
    for (int i = 0; i < n; ++i) {
        double enob = 0, maxerr = 0;
        double snr = run_case(dir, cases[i], enob, maxerr);
        if (snr < MIN_SNR_DB) fails++;
    }

    // inverse round-trip: ifft(fft(x)) ~ x / N (both transforms scaled by /N)
    {
        std::vector<double> xr, xi, gr, gi;
        load_cplx(dir + "in_ca_block.txt", xr, xi);
        static fdata_t a_re[FFT_N], a_im[FFT_N], b_re[FFT_N], b_im[FFT_N], c_re[FFT_N], c_im[FFT_N];
        for (int k = 0; k < FFT_N; ++k) { a_re[k] = (fdata_t)xr[k]; a_im[k] = (fdata_t)xi[k]; }
        fft_fixed(a_re, a_im, b_re, b_im, false);
        fft_fixed(b_re, b_im, c_re, c_im, true);
        double serr = 0, ssig = 0;
        for (int k = 0; k < FFT_N; ++k) {
            double recov = (double)c_re[k] * FFT_N;   // undo the /N
            double er = recov - xr[k];
            serr += er * er; ssig += xr[k] * xr[k];
        }
        double snr = 20.0 * std::log10(std::sqrt(ssig / FFT_N) / (std::sqrt(serr / FFT_N) + 1e-30));
        printf("  %-10s  round-trip ifft(fft(x))*N vs x:  SNR=%6.2f dB  %s\n",
               "roundtrip", snr, snr >= MIN_SNR_DB ? "PASS" : "FAIL");
        if (snr < MIN_SNR_DB) fails++;
    }

    printf("\n%s\n", fails == 0 ? "FFT ACCURACY GATE: PASS (all cases meet the SNR bound)"
                                : "FFT ACCURACY GATE: FAIL");
    return fails ? 1 : 0;
}
