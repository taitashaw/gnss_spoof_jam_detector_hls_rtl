#!/usr/bin/env python3
"""check_gnss_results.py -- validate actual metrics against expected ranges/flags.

Reads results/<scenario>/actual_metrics.txt (key=value, blank-line per window)
and vectors/<scenario>/expected_metrics.json, then for EVERY window checks:

  * alert_flags match the expected flags EXACTLY            (the hard assertion)
  * spoof_score / jam_score / cn0_proxy / symmetry_error within loose ranges
  * latency_cycles present and positive
  * packet_status == OK and sample_count == WINDOW_SIZE
  * number of windows matches expected_num_windows

Prints PASS/FAIL per scenario and exits non-zero if any scenario fails.

This works on results from EITHER the software golden sim or the XSim flow,
because both write the same key=value actual_metrics.txt format.

Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
"""
import argparse
import json
import os
import sys

from gnss_cfg import load_config

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CFG = load_config()

SCENARIOS = ["clean", "wideband_jam", "tone_jam", "delayed_spoof",
             "doppler_shift", "cn0_drop", "mixed_attack", "backpressure"]


def parse_windows(path):
    blocks = []
    cur = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                if cur:
                    blocks.append(cur); cur = {}
                continue
            if "=" in line:
                k, v = line.split("=", 1)
                cur[k] = int(v)
    if cur:
        blocks.append(cur)
    return blocks


def check_scenario(name, verbose=True):
    rdir = os.path.join(REPO, "results", name)
    apath = os.path.join(rdir, "actual_metrics.txt")
    epath = os.path.join(REPO, "vectors", name, "expected_metrics.json")
    if not os.path.isfile(apath):
        print(f"[FAIL] {name:<14} no results ({apath} missing)")
        return False
    if not os.path.isfile(epath):
        print(f"[FAIL] {name:<14} no expected_metrics.json")
        return False

    exp = json.load(open(epath))
    wins = parse_windows(apath)
    errs = []

    if len(wins) != exp.get("expected_num_windows", len(wins)):
        errs.append(f"window count {len(wins)} != expected {exp['expected_num_windows']}")
    if len(wins) == 0:
        errs.append("no metric packets produced")

    ef = exp["expected_alert_flags"]
    for i, w in enumerate(wins):
        if w.get("alert_flags") != ef:
            errs.append(f"win{i}: alert_flags {w.get('alert_flags')} != expected {ef}")
        if not (exp["spoof_score_min"] <= w.get("spoof_score", -1) <= exp["spoof_score_max"]):
            errs.append(f"win{i}: spoof_score {w.get('spoof_score')} out of "
                        f"[{exp['spoof_score_min']},{exp['spoof_score_max']}]")
        if not (exp["jam_score_min"] <= w.get("jam_score", -1) <= exp["jam_score_max"]):
            errs.append(f"win{i}: jam_score {w.get('jam_score')} out of "
                        f"[{exp['jam_score_min']},{exp['jam_score_max']}]")
        if not (exp["cn0_proxy_min"] <= w.get("cn0_proxy", -1) <= exp["cn0_proxy_max"]):
            errs.append(f"win{i}: cn0_proxy {w.get('cn0_proxy')} out of "
                        f"[{exp['cn0_proxy_min']},{exp['cn0_proxy_max']}]")
        if not (exp["symmetry_error_min"] <= w.get("symmetry_error", -1) <= exp["symmetry_error_max"]):
            errs.append(f"win{i}: symmetry_error {w.get('symmetry_error')} out of range")
        if w.get("latency_cycles", 0) <= 0:
            errs.append(f"win{i}: latency_cycles not positive ({w.get('latency_cycles')})")
        if w.get("sample_count") != CFG["WINDOW_SIZE"]:
            errs.append(f"win{i}: sample_count {w.get('sample_count')} != {CFG['WINDOW_SIZE']}")
        if w.get("packet_status") != CFG["PKT_STATUS_OK"]:
            errs.append(f"win{i}: packet_status {w.get('packet_status')} != OK")

    if errs:
        print(f"[FAIL] {name:<14} {len(wins)} window(s)")
        for e in errs[:8]:
            print(f"         - {e}")
        return False
    if verbose:
        w = wins[-1]
        print(f"[PASS] {name:<14} flags={ef:>2} windows={len(wins)} "
              f"spoof={w['spoof_score']} jam={w['jam_score']} cn0={w['cn0_proxy']} "
              f"lat={w['latency_cycles']}")
    return True


def main():
    ap = argparse.ArgumentParser(description="Check GNSS results vs expected")
    ap.add_argument("--scenario", default="all")
    args = ap.parse_args()
    todo = SCENARIOS if args.scenario == "all" else [args.scenario]

    npass = 0
    for s in todo:
        if check_scenario(s):
            npass += 1
    total = len(todo)
    print(f"\n{npass}/{total} scenario(s) passed.")
    if npass != total:
        sys.exit(1)


if __name__ == "__main__":
    main()
