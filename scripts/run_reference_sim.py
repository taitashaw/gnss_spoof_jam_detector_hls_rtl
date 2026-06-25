#!/usr/bin/env python3
"""run_reference_sim.py -- software-only golden simulation (no Xilinx tools).

Builds the C golden model (hls/src/gnss_metric_ref.cpp) if needed and runs it
over each scenario's input_iq.txt, writing:

    results/<scenario>/actual_metrics.txt   (key=value, blank-line per window)

The C model also cross-checks each scenario's tapped_stream.txt against its own
mix+PRN front-end and exits non-zero on any mismatch, so this step proves the
Python generator and the golden model agree bit-for-bit.

This is the backbone of `make selfcheck`: it runs on plain Linux with only g++
and produces the results that check_gnss_results.py validates.

Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
"""
import argparse
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF_SRC = os.path.join(REPO, "hls", "src", "gnss_metric_ref.cpp")
REF_BIN = os.path.join(REPO, "build", "gnss_ref_sim")
INCLUDE = os.path.join(REPO, "hls", "include")

SCENARIOS = ["clean", "wideband_jam", "tone_jam", "delayed_spoof",
             "doppler_shift", "cn0_drop", "mixed_attack", "backpressure"]


def build_ref():
    os.makedirs(os.path.dirname(REF_BIN), exist_ok=True)
    cmd = ["g++", "-O2", "-std=c++14", "-DGNSS_NATIVE_TYPES", "-DGNSS_REF_MAIN",
           f"-I{INCLUDE}", REF_SRC, "-o", REF_BIN]
    print("  building golden model: " + " ".join(cmd[:1]) + " ... -o build/gnss_ref_sim")
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        raise SystemExit("ERROR: failed to compile golden reference model")


def run_scenario(name):
    sdir = os.path.join(REPO, "vectors", name)
    rdir = os.path.join(REPO, "results", name)
    os.makedirs(rdir, exist_ok=True)
    out = os.path.join(rdir, "actual_metrics.txt")
    if not os.path.isfile(os.path.join(sdir, "input_iq.txt")):
        raise SystemExit(f"ERROR: missing vectors/{name}/input_iq.txt -- run 'make vectors'")
    r = subprocess.run([REF_BIN, sdir, out], capture_output=True, text=True)
    cc = "front-end OK" if "crosscheck OK" in r.stderr else r.stderr.strip().splitlines()[-1] if r.stderr else ""
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        print(f"  {name:<14} FAILED (rc={r.returncode})")
        return False
    print(f"  {name:<14} -> results/{name}/actual_metrics.txt  [{cc}]")
    return True


def main():
    ap = argparse.ArgumentParser(description="Run the software golden GNSS sim")
    ap.add_argument("--scenario", default="all")
    ap.add_argument("--no-build", action="store_true",
                    help="assume build/gnss_ref_sim already exists")
    args = ap.parse_args()

    if not args.no_build or not os.path.isfile(REF_BIN):
        build_ref()

    todo = SCENARIOS if args.scenario == "all" else [args.scenario]
    ok = True
    for s in todo:
        ok &= run_scenario(s)
    if not ok:
        raise SystemExit("ERROR: reference simulation failed")
    print(f"Reference sim complete for {len(todo)} scenario(s).")


if __name__ == "__main__":
    main()
