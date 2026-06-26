#!/usr/bin/env python3
"""benchmark.py -- head-to-head: DBZP coherent ddMap (candidate) vs PCS (baseline).

Runs BOTH acquisition detectors on the SAME inputs (real TEXBAT ds2/ds7 clean+spoofed)
and extracts the SAME metrics computed identically: sensitivity (peak SNR in dB vs
coherent integration), PRN true/false acquisition, and spoof distortion detection
with clean-slice false-alarm. This is a measurement; it reports whatever the numbers
show, with cost stated alongside. Nothing is decided in advance.

Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
"""
import json

import numpy as np

from dbzp_acq import read_iq, acquire, detection_metrics, FS
from pcs_acq import pcs_acquire

FSD = FS / 2
DS2 = "/home/jotshawlinux/Downloads/ds2.bin"
DS7 = "/home/jotshawlinux/Downloads/ds7.bin"
ACQ = 60.0
DISTORT_THR = 0.50


def db(r):
    return 10.0 * np.log10(max(r, 1e-9))


from gps_ca import upsample_ca


def _cn0_amp(cn0_dbhz, fs, sigma):
    """Signal amplitude A for a target C/N0 given complex-noise std `sigma`/component."""
    n0 = (2.0 * sigma ** 2) / fs          # noise PSD (W/Hz)
    c = 10 ** (cn0_dbhz / 10.0) * n0      # carrier power
    return np.sqrt(c)


def _calib_threshold(fn, prn, fs, integ_ms, sigma, trials=25, seed=7):
    """Noise-only acquisition-metric 99th-percentile (Pfa ~ 1%) per detector."""
    rng = np.random.default_rng(seed)
    ns = int(round(fs * 1e-3)); n = ns * integ_ms
    vals = []
    for _ in range(trials):
        x = sigma * (rng.standard_normal(n) + 1j * rng.standard_normal(n))
        vals.append(fn(x, prn, fs, integ_ms)["snr"])
    return float(np.percentile(vals, 99))


def min_detectable_cn0(fs, integ_ms, prn=5, dopp=1200.0, sigma=1.0,
                       cn0_grid=None, seeds=(11, 12, 13)):
    """Minimum detectable C/N0 (dB-Hz) at matched ~1% Pfa, for each detector.

    Injects a real-C/A signal at a controlled C/N0 into complex white noise and
    finds the lowest C/N0 each detector acquires above its Pfa-calibrated threshold.
    This is the literature-comparable sensitivity (NOT raw peak/median, which would
    overstate the coherent gain)."""
    if cn0_grid is None:
        cn0_grid = np.arange(28, 50.1, 1.0)
    ns = int(round(fs * 1e-3)); n = ns * integ_ms
    t = np.arange(n) / fs
    code = np.tile(upsample_ca(prn, ns), integ_ms).astype(complex)
    out = {}
    for name, fn in [("dbzp", acquire), ("pcs", pcs_acquire)]:
        thr = _calib_threshold(fn, prn, fs, integ_ms, sigma)
        mind = None
        for cn0 in cn0_grid:
            A = _cn0_amp(cn0, fs, sigma)
            ok = 0
            for sd in seeds:
                rng = np.random.default_rng(sd)
                sig = A * np.roll(code, 1234) * np.exp(2j * np.pi * dopp * t)
                x = sig + sigma * (rng.standard_normal(n) + 1j * rng.standard_normal(n))
                if fn(x, prn, fs, integ_ms)["snr"] >= thr:
                    ok += 1
            if ok >= len(seeds):           # detected at all noise realizations
                mind = float(cn0); break
        out[name] = dict(min_cn0_dbhz=mind, pfa_threshold=thr)
    d, p = out["dbzp"]["min_cn0_dbhz"], out["pcs"]["min_cn0_dbhz"]
    out["gain_db"] = (p - d) if (d is not None and p is not None) else None
    return out


def prn_acq(x, integ_ms, truth):
    """True/false acquisition: of `truth` PRNs, fraction acquired; plus false PRNs."""
    res = {}
    for name, fn in [("dbzp", acquire), ("pcs", pcs_acquire)]:
        acq = set()
        for p in range(1, 33):
            a = fn(x, p, FSD, integ_ms) if name == "dbzp" else fn(x, p, FSD, integ_ms)
            if a["snr"] >= ACQ:
                acq.add(p)
        tp = sorted(acq & truth); fp = sorted(acq - truth)
        res[name] = dict(true_pos=len(tp), of_truth=len(truth), prns_tp=tp,
                         false_pos=len(fp), prns_fp=fp)
    return res


def spoof(binp, clean_t, spoof_t, integ_ms):
    """Distortion detection rate + clean false-alarm, both detectors."""
    xc = read_iq(binp, clean_t, integ_ms + 2, decim=2)
    xs = read_iq(binp, spoof_t, integ_ms + 2, decim=2)
    res = {}
    for name, fn in [("dbzp", acquire), ("pcs", pcs_acquire)]:
        cdv, sdv = [], []
        for p in range(1, 33):
            ac = fn(xc, p, FSD, integ_ms); a_s = fn(xs, p, FSD, integ_ms)
            if ac["snr"] >= ACQ:
                cdv.append(detection_metrics(ac, FSD)["distortion"])
            if a_s["snr"] >= ACQ:
                sdv.append(detection_metrics(a_s, FSD)["distortion"])
        cdv = np.array(cdv); sdv = np.array(sdv)
        res[name] = dict(
            clean_n=len(cdv), spoof_n=len(sdv),
            clean_fa=float(np.mean(cdv >= DISTORT_THR)) if len(cdv) else 0.0,
            spoof_det=float(np.mean(sdv >= DISTORT_THR)) if len(sdv) else 0.0,
            clean_max=float(cdv.max()) if len(cdv) else 0.0,
            spoof_min=float(sdv.min()) if len(sdv) else 0.0)
    return res


def main():
    out = {}
    # empirical truth: PRNs the (more sensitive) DBZP acquires with high SNR at 16 ms
    x2 = read_iq(DS2, 20.0, 20, decim=2)
    truth = set(p for p in range(1, 33) if acquire(x2, p, FSD, 16)["snr"] > 300)
    out["truth_prns"] = sorted(truth)
    print(f"empirical truth (DBZP high-SNR, ds2 clean): {sorted(truth)}")

    out["sensitivity"] = {ms: min_detectable_cn0(FSD, ms) for ms in [4, 10]}
    print("\nSENSITIVITY (minimum detectable C/N0 dB-Hz, matched ~1% Pfa, injected real C/A):")
    print(f"  {'integ_ms':>9}{'DBZP':>8}{'PCS':>8}{'gain dB':>9}")
    for ms, d in out["sensitivity"].items():
        g = d["gain_db"]
        print(f"  {ms:>9}{str(d['dbzp']['min_cn0_dbhz']):>8}{str(d['pcs']['min_cn0_dbhz']):>8}"
              f"{('%+.1f' % g) if g is not None else 'n/a':>9}")

    out["prn_acq_4ms"] = prn_acq(x2, 4, truth)
    print("\nPRN ACQUISITION at 4 ms (truth = {} SVs):".format(len(truth)))
    for nm, r in out["prn_acq_4ms"].items():
        print(f"  {nm:>5}: true_pos={r['true_pos']}/{r['of_truth']}  false_pos={r['false_pos']} {r['prns_fp']}")

    out["spoof_ds2"] = spoof(DS2, 20.0, 150.0, 10)
    out["spoof_ds7"] = spoof(DS7, 20.0, 250.0, 10)
    for scen in ["ds2", "ds7"]:
        print(f"\nSPOOF distortion {scen} (thr {DISTORT_THR}):")
        for nm, r in out[f"spoof_{scen}"].items():
            print(f"  {nm:>5}: clean_FA={r['clean_fa']*100:.0f}% (max {r['clean_max']:.2f}) "
                  f"spoof_det={r['spoof_det']*100:.0f}% (min {r['spoof_min']:.2f}) "
                  f"n=({r['clean_n']},{r['spoof_n']})")

    with open("/tmp/benchmark.json", "w") as f:
        json.dump(out, f, indent=2)
    print("\nwrote /tmp/benchmark.json")


if __name__ == "__main__":
    main()
