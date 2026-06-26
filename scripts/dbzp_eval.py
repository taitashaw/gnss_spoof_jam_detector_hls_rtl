#!/usr/bin/env python3
"""dbzp_eval.py -- single-pass spoof detection eval on real TEXBAT ds2 + ds7.

For each scenario (ds2, ds7) and slice (clean, spoofed) it acquires the visible
PRNs with DBZP coherent integration and computes the detection statistics from the
acquisition ddMap (one pass). It reports, per metric, the spoofed detection rate
AND the clean-slice false-alarm rate at the same threshold -- a metric that only
flags spoofed by also flagging clean is reported as failed.

Honest expectation (documented physics): ds2 has a separable (overpowered,
dragged-off) spoofer peak that single-pass detection can flag; ds7 SCER is
coherent/matched (code phase, carrier, Doppler replicated), so single-antenna
single-pass separation is partial-to-impossible.

Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
"""
import json
import sys

import numpy as np

from dbzp_acq import read_iq, acquire, detection_metrics, FS

DECIM = 2
FS_DEC = FS / DECIM
COH_MS = 10
ACQ_SNR = 60.0          # acquisition threshold (peak/median floor)
SLICES = {
    "ds2": dict(bin="/home/jotshawlinux/Downloads/ds2.bin", clean=20.0, spoofed=150.0),
    "ds7": dict(bin="/home/jotshawlinux/Downloads/ds7.bin", clean=20.0, spoofed=250.0),
}
# detection thresholds (gated on clean false-alarm, reported either way)
T_PEAKCOUNT = 2         # >=2 distinct peaks
T_PEAKRATIO = 0.40      # secondary/main power
T_DISTORT = 0.50        # early/late asymmetry (gated: 0% clean FA, 100% ds7 det)


def eval_slice(binpath, start_s):
    x = read_iq(binpath, start_s, COH_MS + 2, decim=DECIM)
    rows = []
    for prn in range(1, 33):
        a = acquire(x, prn, FS_DEC, COH_MS)
        if a["snr"] >= ACQ_SNR:
            m = detection_metrics(a, FS_DEC)
            rows.append((prn, m))
    return rows


def summarize(rows):
    n = len(rows)
    if n == 0:
        return dict(n=0)
    pc = np.array([m["peak_count"] for _, m in rows])
    pr = np.array([m["peak_ratio"] for _, m in rows])
    di = np.array([m["distortion"] for _, m in rows])
    return dict(
        n=n,
        prns=[p for p, _ in rows],
        peakcount_flag=float(np.mean(pc >= T_PEAKCOUNT)),
        peakratio_flag=float(np.mean(pr >= T_PEAKRATIO)),
        distort_flag=float(np.mean(di >= T_DISTORT)),
        peak_ratio_mean=float(pr.mean()), peak_ratio_max=float(pr.max()),
        peak_count_mean=float(pc.mean()), peak_count_max=int(pc.max()),
        distort_mean=float(di.mean()),
    )


def main():
    out = {}
    for scen, cfg in SLICES.items():
        clean = summarize(eval_slice(cfg["bin"], cfg["clean"]))
        spoof = summarize(eval_slice(cfg["bin"], cfg["spoofed"]))
        out[scen] = dict(clean=clean, spoofed=spoof)
        print(f"\n===== {scen} (single-pass detection from ddMap) =====")
        print(f"  acquired PRNs: clean={clean['n']} spoofed={spoof['n']}")
        print(f"  {'metric':<16}{'clean FA':>12}{'spoofed det':>14}{'separates?':>12}")
        for key, lbl in [("peakcount_flag", "peak_count>=2"),
                          ("peakratio_flag", "peak_ratio>=.4"),
                          ("distort_flag", "distortion>=.35")]:
            fa = clean.get(key, 0.0); det = spoof.get(key, 0.0)
            sep = "YES" if (det - fa) > 0.25 and fa < 0.2 else "no"
            print(f"  {lbl:<16}{fa*100:>10.0f}%{det*100:>12.0f}%{sep:>12}")
        print(f"  peak_ratio mean/max: clean {clean.get('peak_ratio_mean',0):.2f}/"
              f"{clean.get('peak_ratio_max',0):.2f}  spoofed "
              f"{spoof.get('peak_ratio_mean',0):.2f}/{spoof.get('peak_ratio_max',0):.2f}")

    with open(sys.argv[1] if len(sys.argv) > 1 else "/tmp/dbzp_eval.json", "w") as f:
        json.dump(out, f, indent=2)
    print(f"\nwrote {sys.argv[1] if len(sys.argv)>1 else '/tmp/dbzp_eval.json'}")


if __name__ == "__main__":
    main()
