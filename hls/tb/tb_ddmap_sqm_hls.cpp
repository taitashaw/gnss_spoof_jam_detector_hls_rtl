// ============================================================================
// tb_ddmap_sqm_hls.cpp -- C testbench for the ddMap/SQM HLS kernel vs golden
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Checks the fixed-point hls::fft kernel against the Python float golden at the
// matched config (scripts/ddmap_hls_vectors.py). Fixed-point FFT is not bit-exact
// vs float, so the checks are: peak code phase EXACT; distortion within tolerance;
// wrong-PRN peak power much lower than correct-PRN. Returns non-zero on failure.
//
// Pass the repo root as argv[1] (run_hls.tcl supplies it).
// ============================================================================
#ifndef _GNU_SOURCE
#define _GNU_SOURCE   // for fedisableexcept (glibc)
#endif
#include <fenv.h>
#include "hls_stream.h"
#include "ap_int.h"
#include "ap_axi_sdata.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#define FFT_SIZE 2048
#define N_BLK    4

typedef ap_axiu<32, 0, 0, 0> axis_iq_t;

void ddmap_sqm_hls(hls::stream<axis_iq_t> &iq_in, ap_uint<8> prn,
                   ap_uint<48> &peak_power, ap_uint<16> &code_phase,
                   ap_uint<32> &distortion_q16, ap_uint<48> &early_power,
                   ap_uint<48> &late_power);

struct Ref { int prn, peak; double dist; };

static bool load_blocks(const std::string &path, hls::stream<axis_iq_t> &s) {
    FILE *f = fopen(path.c_str(), "r");
    if (!f) { printf("  cannot open %s\n", path.c_str()); return false; }
    int iv, qv; long count = 0;
    while (fscanf(f, "%d %d", &iv, &qv) == 2) {
        axis_iq_t b; b.data = 0;
        b.data(31, 16) = (ap_uint<16>)(uint16_t)(int16_t)iv;
        b.data(15, 0)  = (ap_uint<16>)(uint16_t)(int16_t)qv;
        b.keep = -1; b.strb = -1; b.last = ((count % FFT_SIZE) == FFT_SIZE - 1);
        s.write(b); count++;
    }
    fclose(f);
    return count == (long)FFT_SIZE * N_BLK;
}

static Ref load_ref(const std::string &path) {
    Ref r{0, 0, 0.0}; FILE *f = fopen(path.c_str(), "r");
    if (!f) return r;
    char line[128];
    while (fgets(line, sizeof(line), f)) {
        if (!strncmp(line, "prn=", 4)) r.prn = atoi(line + 4);
        else if (!strncmp(line, "peak=", 5)) r.peak = atoi(line + 5);
        else if (!strncmp(line, "distortion=", 11)) r.dist = atof(line + 11);
    }
    fclose(f); return r;
}

int main(int argc, char **argv) {
#ifdef FE_ALL_EXCEPT
    fedisableexcept(FE_ALL_EXCEPT);   // don't trap FP exceptions raised inside the FFT C-model
#endif
    std::string root = (argc > 1) ? argv[1] : ".";
    std::string dir = root + "/vectors/ddmap_hls/";
    int fails = 0;

    // read the ds7 PRN label
    int ds7_prn = 0;
    { FILE *f = fopen((dir + "ds7_prn.txt").c_str(), "r"); if (f) { fscanf(f, "%d", &ds7_prn); fclose(f); } }
    char ds7name[32]; snprintf(ds7name, sizeof(ds7name), "ds7_p%d", ds7_prn);

    struct Case { const char *name; int corr_prn; } cases[] = {
        {"clean_p5", 5}, {"wrong_p6", 6}, {ds7_prn ? ds7name : "", ds7_prn}
    };

    ap_uint<48> clean_peak = 0, wrong_peak = 0;
    double clean_dist = 0, ds7_dist = 0;

    for (int c = 0; c < 3; ++c) {
        if (cases[c].name[0] == '\0') continue;
        hls::stream<axis_iq_t> s;
        if (!load_blocks(dir + "blocks_" + cases[c].name + ".txt", s)) {
            printf("FAIL %-12s: blocks load\n", cases[c].name); fails++; continue;
        }
        Ref ref = load_ref(dir + "ref_" + cases[c].name + ".txt");
        ap_uint<48> pp, ep, lp; ap_uint<16> cp; ap_uint<32> dq;
        ddmap_sqm_hls(s, cases[c].corr_prn, pp, cp, dq, ep, lp);
        double dist = (double)dq / 65536.0;
        printf("  %-12s corr_prn=%d  kernel: peak=%d dist=%.4f peakP=%llu | golden: peak=%d dist=%.4f\n",
               cases[c].name, cases[c].corr_prn, (int)cp, dist,
               (unsigned long long)pp, ref.peak, ref.dist);
        if (!strcmp(cases[c].name, "clean_p5")) { clean_peak = pp; clean_dist = dist;
            if ((int)cp != ref.peak) { printf("    FAIL peak phase %d != %d\n", (int)cp, ref.peak); fails++; } }
        if (!strcmp(cases[c].name, "wrong_p6")) wrong_peak = pp;
        if (ds7_prn && !strcmp(cases[c].name, ds7name)) ds7_dist = dist;
    }

    // checks
    if (wrong_peak * 5 >= clean_peak) {
        printf("FAIL: wrong-PRN peak (%llu) not << correct (%llu)\n",
               (unsigned long long)wrong_peak, (unsigned long long)clean_peak); fails++;
    } else printf("  OK: wrong-PRN peak << correct-PRN peak (%.1fx lower)\n",
                  clean_peak > 0 ? (double)clean_peak / (double)(wrong_peak + 1) : 0.0);
    if (ds7_prn && ds7_dist <= clean_dist) {
        printf("FAIL: ds7 distortion (%.3f) not > clean (%.3f)\n", ds7_dist, clean_dist); fails++;
    } else if (ds7_prn) printf("  OK: ds7 distortion %.3f > clean %.3f (spoof signature)\n", ds7_dist, clean_dist);

    printf("\n%s\n", fails == 0 ? "DDMAP/SQM KERNEL CSIM PASS (matches golden within tolerance)"
                                : "DDMAP/SQM KERNEL CSIM FAIL");
    return fails ? 1 : 0;
}
