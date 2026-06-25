// ============================================================================
// tb_gnss_metric_hls.cpp  --  HLS C testbench: kernel vs golden reference
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Reads each scenario's vectors/<scenario>/tapped_stream.txt (the front-end
// output the Python generator produced and that gnss_ref_sim validated against
// the golden front-end), feeds it window-by-window through the HLS kernel
// gnss_metric_hls, and compares every metric field against the golden model
// (ref_compute_metrics) within a small documented fixed-point tolerance. Prints
// PASS/FAIL per scenario and returns non-zero on any failure.
//
// Pass the repo root as argv[1] (run_hls.tcl supplies it); defaults try a few
// relative locations so it also runs from the solution csim build dir.
// ============================================================================
#include "gnss_config.hpp"
#include "fixed_types.hpp"
#include "gnss_types.hpp"
#include "axis_types.hpp"
#include "ap_int.h"

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

// golden model (compiled in; its main() is guarded by GNSS_REF_MAIN)
#include "../src/gnss_metric_ref.cpp"

// DUT prototype
void gnss_metric_hls(
    hls::stream<axis_tapped_t>     &tap_in,
    hls::stream<axis_metric_pkt_t> &metric_out,
    ap_uint<32>  window_id,
    ap_uint<48>  power_prev,
    ap_uint<32>  noise_prev,
    ap_uint<48> &power_cur,
    ap_uint<32> &noise_cur);

static const char *SCENARIOS[] = {
    "clean", "wideband_jam", "tone_jam", "delayed_spoof",
    "doppler_shift", "cn0_drop", "mixed_attack", "backpressure"
};

// Tolerance: kernel and reference use identical integer math, so they should
// match exactly. We allow a tiny slack to absorb any width/rounding edge.
static const long METRIC_TOL = 2;

static FILE *open_tapped(const std::string &root, const char *scen) {
    std::string p = root + "/vectors/" + scen + "/tapped_stream.txt";
    return fopen(p.c_str(), "r");
}

static bool close_enough(long a, long b, long tol) {
    long d = a - b; if (d < 0) d = -d; return d <= tol;
}

int main(int argc, char **argv) {
    std::string root = (argc > 1) ? argv[1] : ".";
    // try a few roots so csim works from the solution build dir too
    {
        FILE *probe = open_tapped(root, "clean");
        if (!probe) { root = "../../../.."; probe = open_tapped(root, "clean"); }
        if (!probe) { root = "../../../../.."; probe = open_tapped(root, "clean"); }
        if (probe) fclose(probe);
    }

    int total_fail = 0;
    for (unsigned s = 0; s < sizeof(SCENARIOS)/sizeof(SCENARIOS[0]); ++s) {
        const char *scen = SCENARIOS[s];
        FILE *f = open_tapped(root, scen);
        if (!f) { printf("FAIL %-14s : cannot open tapped_stream.txt\n", scen); total_fail++; continue; }

        // group beats by window
        std::vector<std::vector<tapped_beat_t> > windows;
        char line[256];
        int w, idx, mi, mq, ce, cp, cl, lb;
        while (fgets(line, sizeof(line), f)) {
            if (line[0] == '#' || line[0] == '\n') continue;
            if (sscanf(line, "%d %d %d %d %d %d %d %d", &w, &idx, &mi, &mq, &ce, &cp, &cl, &lb) != 8) continue;
            if ((int)windows.size() <= w) windows.resize(w + 1);
            tapped_beat_t b;
            b.mixed_i = (int16_t)mi; b.mixed_q = (int16_t)mq;
            b.chip_e = ce; b.chip_p = cp; b.chip_l = cl;
            b.sample_index = idx; b.last = lb;
            windows[w].push_back(b);
        }
        fclose(f);

        int fails = 0;
        ap_uint<48> power_prev = 0; ap_uint<32> noise_prev = 0;
        uint64_t ref_power_prev = 0; uint32_t ref_noise_prev = 0;

        for (size_t wi = 0; wi < windows.size(); ++wi) {
            std::vector<tapped_beat_t> &bs = windows[wi];
            if (bs.empty()) continue;

            // ---- run DUT ----
            hls::stream<axis_tapped_t> tin; hls::stream<axis_metric_pkt_t> tout;
            for (size_t k = 0; k < bs.size(); ++k) {
                axis_tapped_t t;
                t.data = pack_tapped(bs[k].mixed_i, bs[k].mixed_q,
                                     bs[k].chip_e, bs[k].chip_p, bs[k].chip_l,
                                     bs[k].sample_index);
                t.keep = -1; t.strb = -1;
                t.last = (k == bs.size()-1) ? 1 : 0;
                tin.write(t);
            }
            ap_uint<48> power_cur; ap_uint<32> noise_cur;
            gnss_metric_hls(tin, tout, (ap_uint<32>)wi, power_prev, noise_prev, power_cur, noise_cur);
            axis_metric_pkt_t ob = tout.read();
            ap_uint<512> o = ob.data;

            // ---- golden ----
            gnss_metrics_t ref;
            ref_compute_metrics(bs, (uint32_t)wi, ref_power_prev, ref_noise_prev, ref);

            // ---- compare ----
            struct { const char *name; long dut; long ref; } cmp[] = {
                {"power",  (long)(ap_uint<48>)o(B_POWER_O+47,B_POWER_O),  (long)ref.power_estimate},
                {"noise",  (long)(ap_uint<32>)o(B_NOISE_O+31,B_NOISE_O),  (long)ref.noise_estimate},
                {"cn0",    (long)(ap_uint<32>)o(B_CN0_O+31,B_CN0_O),      (long)ref.cn0_proxy},
                {"corr_p", (long)(ap_uint<32>)o(B_CP_O+31,B_CP_O),        (long)ref.corr_prompt},
                {"corr_e", (long)(ap_uint<32>)o(B_CE_O+31,B_CE_O),        (long)ref.corr_early},
                {"corr_l", (long)(ap_uint<32>)o(B_CL_O+31,B_CL_O),        (long)ref.corr_late},
                {"sym",    (long)(ap_uint<32>)o(B_SYM_O+31,B_SYM_O),      (long)ref.symmetry_error},
                {"dopp",   (long)(ap_uint<48>)o(B_DOPP_O+47,B_DOPP_O),    (long)ref.doppler_energy},
                {"pjump",  (long)(ap_uint<48>)o(B_PJUMP_O+47,B_PJUMP_O),  (long)ref.power_jump_metric},
                {"spoof",  (long)(ap_uint<32>)o(B_SPOOF_O+31,B_SPOOF_O),  (long)ref.spoof_score},
                {"jam",    (long)(ap_uint<32>)o(B_JAM_O+31,B_JAM_O),      (long)ref.jam_score},
                {"scnt",   (long)(ap_uint<32>)o(B_SCNT_O+31,B_SCNT_O),    (long)ref.sample_count},
            };
            for (unsigned c = 0; c < sizeof(cmp)/sizeof(cmp[0]); ++c) {
                if (!close_enough(cmp[c].dut, cmp[c].ref, METRIC_TOL)) {
                    printf("  %s win%zu %-7s dut=%ld ref=%ld\n", scen, wi, cmp[c].name, cmp[c].dut, cmp[c].ref);
                    fails++;
                }
            }
            power_prev = power_cur; noise_prev = noise_cur;
            ref_power_prev = ref.power_estimate; ref_noise_prev = ref.noise_estimate;
        }

        if (fails == 0) printf("PASS %-14s : kernel matches golden (%zu windows)\n", scen, windows.size());
        else { printf("FAIL %-14s : %d field mismatches\n", scen, fails); total_fail++; }
    }

    printf("\n%s\n", total_fail == 0 ? "ALL HLS C-SIM SCENARIOS PASS" : "HLS C-SIM FAILURES PRESENT");
    return total_fail ? 1 : 0;
}
