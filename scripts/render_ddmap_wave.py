#!/usr/bin/env python3
"""render_ddmap_wave.py -- render the CURRENT own-FFT ddMap/SQM kernel's AXIS
waveform from a real XSim VCD (cosim of hls/src/ddmap_sqm_hls.cpp).

Parses a VCD dumped over a short window of the C/RTL co-simulation and draws the
kernel's `iq_in` AXI4-Stream handshake (TVALID/TREADY/TLAST/TDATA) together with the
ap_start/ap_done control, as a timing diagram. Every transition shown is a real
transition in the VCD -- not a mock-up.

Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
"""
import re
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

VCD = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ddmap_axis.vcd"
OUT = sys.argv[2] if len(sys.argv) > 2 else "docs/images/waveform_ddmap_axis.png"

# signal short-name -> display label, top to bottom
WANT = [
    ("ap_start", "ap_start"),
    ("iq_in_TVALID", "iq_in TVALID"),
    ("iq_in_TREADY", "iq_in TREADY"),
    ("iq_in_TLAST", "iq_in TLAST"),
    ("iq_in_TDATA", "iq_in TDATA[31:0]"),
    ("ap_done", "ap_done"),
]


def parse_vcd(path):
    ts, scope = 1.0, []
    id2name, id2scope = {}, {}
    # pass 1: declarations
    for line in open(path):
        line = line.strip()
        if line.startswith("$timescale"):
            m = re.search(r"(\d+)\s*(\w?s)", line)
        elif line.startswith("$scope"):
            scope.append(line.split()[2])
        elif line.startswith("$upscope"):
            if scope:
                scope.pop()
        elif line.startswith("$var"):
            p = line.split()
            vid, name = p[3], p[4]
            id2name.setdefault(vid, name)
            id2scope.setdefault(vid, "/".join(scope))
        elif line.startswith("$enddefinitions"):
            break
    # choose, per wanted signal, the shallowest scope (the DUT top instance)
    chosen = {}
    for short, _ in WANT:
        cands = [(vid, id2scope[vid]) for vid, n in id2name.items() if n == short]
        if not cands:
            continue
        cands.sort(key=lambda c: len(c[1]))
        chosen[short] = cands[0][0]
    ids = set(chosen.values())
    # pass 2: value changes
    changes = {vid: [] for vid in ids}
    t = 0
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        if line[0] == "#":
            t = int(line[1:])
        elif line[0] in "01xz":
            vid = line[1:]
            if vid in ids:
                changes[vid].append((t, line[0]))
        elif line[0] == "b":
            v, vid = line.split()
            if vid in ids:
                changes[vid].append((t, v[1:]))
    return chosen, changes


def step(ax, changes, y, scalar=True, tmax=0):
    if not changes:
        return
    xs, ys, labels = [], [], []
    prev = 0
    for t, v in changes:
        if scalar:
            lvl = 1 if v == "1" else 0
            xs += [t, t]; ys += [prev, lvl]; prev = lvl
        else:
            xs.append(t); labels.append((t, v))
    if scalar:
        xs.append(tmax); ys.append(prev)
        ax.plot(np.array(xs) / 1000.0, np.array(ys) * 0.7 + y, drawstyle="steps-post",
                color="#1565C0", lw=1.4)
    else:
        # bus: draw a band and annotate a few values
        ax.add_patch(plt.Rectangle((0, y), tmax / 1000.0, 0.7, fill=False, ec="#6A1B9A", lw=1.0))
        last = None
        for t, v in changes[::max(1, len(changes) // 8)]:
            if v != last:
                ax.text(t / 1000.0, y + 0.35, hex(int(v, 2) & 0xffffffff)[2:],
                        fontsize=6, va="center", color="#6A1B9A")
                last = v


def main():
    chosen, changes = parse_vcd(VCD)
    tmax = max((c[-1][0] for c in changes.values() if c), default=16000)
    # zoom to the block-read burst: the ~5 us window ending at iq_in_TLAST (one
    # 2048-beat C/A block streaming in), so the handshake is legible rather than
    # compressed against the long gen_ca + code-FFT compute that precedes it.
    tl = changes.get(chosen.get("iq_in_TLAST"), [])
    tlast_hi = [t for t, v in tl if v == "1"]
    if tlast_hi:
        tend = tlast_hi[-1]
        x0 = (tend - 6000000) / 1000.0   # 6 us before TLAST
        x1 = (tend + 800000) / 1000.0    # 0.8 us after
    else:
        x0, x1 = -3.0, tmax / 1000.0
    fig, ax = plt.subplots(figsize=(13, 4.6))
    rows = [w for w in WANT if w[0] in chosen]
    for i, (short, label) in enumerate(rows):
        y = (len(rows) - 1 - i) * 1.0
        scalar = short != "iq_in_TDATA"
        step(ax, changes[chosen[short]], y, scalar, tmax)
        ax.text(x0 - 0.02 * (x1 - x0), y + 0.35, label, ha="right", va="center", fontsize=9)
    ax.set_xlim(x0 - 0.10 * (x1 - x0), x1)
    ax.set_ylim(-0.3, len(rows))
    ax.set_yticks([])
    ax.set_xlabel("time (ns)")
    ax.set_title("Own-FFT ddMap/SQM kernel -- iq_in AXI4-Stream handshake "
                 "(real XSim cosim VCD)\nblock read: TVALID/TREADY high, TLAST at "
                 "end; TREADY deasserts while the kernel computes the FFTs",
                 fontsize=10)
    fig.tight_layout()
    fig.savefig(OUT, dpi=130)
    print(f"wrote {OUT}  (tmax={tmax} ps, signals={list(chosen)})")


if __name__ == "__main__":
    main()
