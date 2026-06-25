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

    names, spoof, jam = [], [], []
    power, cn0, sym, dopp = [], [], [], []
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
        power.append(w.get("power_estimate", 0))
        cn0.append(w.get("cn0_proxy", 0))
        sym.append(max(w.get("symmetry_error", 0), 1))
        dopp.append(max(w.get("doppler_energy", 0), 1))

    if not names:
        print("no results to plot; run 'make selfcheck' first")
        return 0

    x = list(range(len(names)))

    # ---- Chart 1: spoof / jam scores per scenario, with the alert threshold ----
    fig, ax = plt.subplots(figsize=(11, 5))
    ax.bar([i - 0.2 for i in x], spoof, width=0.4, label="spoof_score")
    ax.bar([i + 0.2 for i in x], jam, width=0.4, label="jam_score")
    ax.axhline(500, color="crimson", linestyle="--", linewidth=1,
               label="score threshold (500)")
    ax.set_xticks(x); ax.set_xticklabels(names, rotation=30, ha="right")
    ax.set_ylabel("score (0..65535 saturated)")
    ax.set_title("GNSS Spoof/Jam Detector — spoof and jam scores per scenario (John Bagshaw)")
    ax.legend()
    fig.tight_layout()
    out1 = os.path.join(pdir, "scores_by_scenario.png")
    fig.savefig(out1, dpi=120); plt.close(fig)
    print(f"wrote {out1}")

    # ---- Chart 2: clean-vs-attack metric signatures (log scale) ----
    fig, (axL, axR) = plt.subplots(1, 2, figsize=(13, 5))
    axL.bar([i - 0.2 for i in x], power, width=0.4, label="power_estimate")
    axL.bar([i + 0.2 for i in x], dopp, width=0.4, label="doppler_energy")
    axL.set_yscale("log")
    axL.axhline(150_000_000_000, color="purple", linestyle="--", linewidth=1, label="power jam thr")
    axL.axhline(20_000_000_000, color="green", linestyle=":", linewidth=1, label="doppler thr")
    axL.set_xticks(x); axL.set_xticklabels(names, rotation=35, ha="right")
    axL.set_ylabel("metric (log scale)"); axL.set_title("Power and Doppler energy")
    axL.legend(fontsize=8)

    axR.bar([i - 0.2 for i in x], sym, width=0.4, color="darkorange", label="symmetry_error")
    axR.set_yscale("log")
    axR.axhline(2_000_000, color="crimson", linestyle="--", linewidth=1, label="symmetry thr")
    axR.set_xticks(x); axR.set_xticklabels(names, rotation=35, ha="right")
    axR.set_ylabel("symmetry_error (log)"); axR.set_title("Correlation symmetry (spoof signature)")
    ax2 = axR.twinx()
    ax2.plot(x, cn0, "o-", color="navy", label="cn0_proxy")
    ax2.axhline(180, color="navy", linestyle=":", linewidth=1, label="cn0 drop thr")
    ax2.set_ylabel("cn0_proxy")
    h1, l1 = axR.get_legend_handles_labels(); h2, l2 = ax2.get_legend_handles_labels()
    axR.legend(h1 + h2, l1 + l2, fontsize=8, loc="upper left")
    fig.suptitle("GNSS Spoof/Jam Detector — clean vs attack metric signatures (John Bagshaw)")
    fig.tight_layout()
    out2 = os.path.join(pdir, "metrics_by_scenario.png")
    fig.savefig(out2, dpi=120); plt.close(fig)
    print(f"wrote {out2}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
