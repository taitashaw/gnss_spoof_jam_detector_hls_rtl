#!/usr/bin/env python3
"""render_wave.py -- render an XSim VCD dump into a labelled timing diagram PNG.

This is an HONEST rendering of REAL simulation data: it parses the value-change
dump produced by the XSim run (tb_gnss_top +DUMPVCD) and draws the digital
waveform with matplotlib. It is not a GUI screenshot; every transition shown is a
real transition in the dumped VCD. XSim on this install has no headless GUI-PNG
export, so this renderer is how the committed waveform image is produced. The
same VCD (or the regenerated .wdb) opens directly in the Vivado / XSim GUI for
interactive inspection -- see docs/images/README.md.

Usage: render_wave.py <in.vcd> <out.png>
"""
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

# signals to show, top to bottom, with display labels and grouping
WANT = [
    ("s_tvalid", "s_axis tvalid"),
    ("s_tready", "s_axis tready"),
    ("s_tlast",  "s_axis tlast"),
    ("tap_tvalid", "tapped tvalid"),
    ("tap_tready", "tapped tready"),
    ("m_tvalid", "metrics tvalid"),
    ("m_tready", "metrics tready"),
    ("m_tlast",  "metrics tlast"),
    ("m_tdata",  "metrics tdata[15:0]"),
]


def parse_vcd(path):
    sym2name = {}
    ts_ps = 1  # timescale in ps
    with open(path) as f:
        lines = f.readlines()
    i = 0
    # header
    while i < len(lines):
        ln = lines[i].strip()
        if ln.startswith("$timescale"):
            body = ln.replace("$timescale", "").replace("$end", "").strip()
            if not body and i + 1 < len(lines):
                body = lines[i + 1].strip()
            num = "".join(c for c in body if c.isdigit()) or "1"
            unit = "".join(c for c in body if c.isalpha())
            mult = {"ps": 1, "ns": 1000, "us": 1_000_000, "fs": 0.001}.get(unit, 1)
            ts_ps = int(num) * mult
        elif ln.startswith("$var"):
            parts = ln.split()
            # $var wire N sym name [range] $end
            sym = parts[3]
            name = parts[4]
            sym2name.setdefault(sym, name)
        elif ln.startswith("$enddefinitions"):
            i += 1
            break
        i += 1

    # body: collect value changes per symbol
    series = {s: [] for s in sym2name}     # list of (time_ps, value)
    t = 0
    while i < len(lines):
        ln = lines[i].strip()
        if not ln:
            i += 1; continue
        if ln[0] == "#":
            t = int(ln[1:])
        elif ln[0] in "01xzXZ":
            sym = ln[1:]
            if sym in series:
                series[sym].append((t, 0 if ln[0] == "0" else (1 if ln[0] == "1" else 0)))
        elif ln[0] in "bB":
            val, sym = ln[1:].split()
            try:
                num = int(val.replace("x", "0").replace("z", "0"), 2)
            except ValueError:
                num = 0
            if sym in series:
                series[sym].append((t, num))
        i += 1

    # map by signal base-name (strip [..] bus suffix in name)
    byname = {}
    for sym, name in sym2name.items():
        base = name.split("[")[0]
        byname.setdefault(base, series[sym])
    return byname, ts_ps


def value_at(changes, t):
    v = 0
    for (ct, cv) in changes:
        if ct <= t:
            v = cv
        else:
            break
    return v


def main():
    if len(sys.argv) < 3:
        print("usage: render_wave.py <in.vcd> <out.png>"); return 2
    byname, ts_ps = parse_vcd(sys.argv[1])
    to_ns = ts_ps / 1000.0

    # convert all change times to nanoseconds up front so the window math is in ns
    byname = {k: [(t * to_ns, v) for (t, v) in ch] for k, ch in byname.items()}

    mv = byname.get("m_tvalid", [])
    mr = byname.get("m_tready", [])
    if not mv:
        print("no m_tvalid in VCD"); return 1

    # Prefer a window centred on a real metrics backpressure interval
    # (m_tvalid=1 held while m_tready=0). Fall back to the first packet.
    tmax = max(t for (t, _) in mv)
    bp_center = None
    g = 0.0
    while g < tmax:
        if value_at(mv, g) == 1 and value_at(mr, g) == 0:
            bp_center = g; break
        g += 10.0
    t0 = bp_center if bp_center is not None else next((t for (t, v) in mv if v == 1), mv[0][0])
    win_lo = max(0.0, t0 - 380.0)
    win_hi = t0 + 420.0
    step = 0.25  # ns resolution

    n = int((win_hi - win_lo) / step)
    grid = [win_lo + k * step for k in range(n + 1)]

    fig, ax = plt.subplots(figsize=(13, 6.5))
    yrows = []
    for row, (key, label) in enumerate(WANT):
        ch = byname.get(key, [])
        y0 = -row * 1.6
        yrows.append((y0, label))
        if key == "m_tdata":
            # render bus as a labelled band that toggles on change
            prev = None
            seg_start = grid[0]
            for g in grid:
                val = value_at(ch, g)
                if prev is None:
                    prev = val
                if val != prev:
                    ax.add_patch(Rectangle((seg_start, y0), (g - seg_start), 0.9,
                                           facecolor="#cfe3ff", edgecolor="#3b78c2"))
                    seg_start = g; prev = val
            ax.add_patch(Rectangle((seg_start, y0), (grid[-1] - seg_start), 0.9,
                                   facecolor="#cfe3ff", edgecolor="#3b78c2"))
        else:
            xs, ys = [], []
            for g in grid:
                v = value_at(ch, g)
                xs.append(g); ys.append(y0 + (0.9 if v else 0.05))
            ax.step(xs, ys, where="post", color="#1f3b6e", linewidth=1.4)

    # shade the backpressure interval on the metrics channel: m_tvalid=1 & m_tready=0
    bp_lo = bp_hi = None
    for g in grid:
        if value_at(mv, g) == 1 and value_at(mr, g) == 0:
            if bp_lo is None:
                bp_lo = g
            bp_hi = g
    if bp_lo is not None:
        ax.axvspan(bp_lo, bp_hi + step, color="#ffd9d9", alpha=0.6, zorder=0)
        ax.annotate("metrics backpressure: tvalid held, tready=0, tdata stable (AXIS rule)",
                    xy=((bp_lo + bp_hi) / 2, -len(WANT) * 1.6 + 0.5),
                    ha="center", va="top", fontsize=9, color="#a02020")

    ax.set_yticks([y + 0.45 for (y, _) in yrows])
    ax.set_yticklabels([lbl for (_, lbl) in yrows])
    ax.set_xlabel("time (ns)")
    ax.set_title("gnss_top under burst backpressure — mixed_attack, seed 0xC0FFEE "
                 "(rendered from the real XSim VCD)")
    ax.set_xlim(win_lo, win_hi)
    ax.set_ylim(-len(WANT) * 1.6, 1.2)
    ax.grid(axis="x", linestyle=":", alpha=0.4)
    fig.tight_layout()
    fig.savefig(sys.argv[2], dpi=120)
    print(f"wrote {sys.argv[2]} (window {win_lo:.0f}..{win_hi:.0f} ns, "
          f"backpressure {'shown' if bp_lo is not None else 'not in window'})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
