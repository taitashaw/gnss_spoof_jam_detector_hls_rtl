#!/usr/bin/env python3
"""plot_gnss_metrics.py -- optional matplotlib visualization (not a pass/fail gate).

Writes per-scenario bar charts of the headline metrics and a scenario-comparison
chart to results/plots/*.png. Safe to skip; the verification gate is
check_gnss_results.py, not these plots.

Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
"""
import os
import sys

from check_gnss_results import parse_windows, SCENARIOS

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except Exception as e:  # noqa: BLE001
        print(f"matplotlib unavailable ({e}); skipping plots")
        return 0

    pdir = os.path.join(REPO, "results", "plots")
    os.makedirs(pdir, exist_ok=True)

    spoof, jam, names = [], [], []
    for s in SCENARIOS:
        apath = os.path.join(REPO, "results", s, "actual_metrics.txt")
        if not os.path.isfile(apath):
            continue
        wins = parse_windows(apath)
        if not wins:
            continue
        w = wins[-1]
        names.append(s)
        spoof.append(w.get("spoof_score", 0))
        jam.append(w.get("jam_score", 0))

    if not names:
        print("no results to plot; run 'make selfcheck' first")
        return 0

    x = range(len(names))
    fig, ax = plt.subplots(figsize=(11, 5))
    ax.bar([i - 0.2 for i in x], spoof, width=0.4, label="spoof_score")
    ax.bar([i + 0.2 for i in x], jam, width=0.4, label="jam_score")
    ax.set_xticks(list(x))
    ax.set_xticklabels(names, rotation=30, ha="right")
    ax.set_ylabel("score (0..65535 saturated)")
    ax.set_title("GNSS Spoof/Jam Detector -- scores per scenario (John Bagshaw)")
    ax.legend()
    fig.tight_layout()
    out = os.path.join(pdir, "scores_by_scenario.png")
    fig.savefig(out, dpi=110)
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
