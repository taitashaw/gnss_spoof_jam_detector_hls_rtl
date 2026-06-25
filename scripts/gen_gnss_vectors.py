#!/usr/bin/env python3
"""gen_gnss_vectors.py -- deterministic synthetic I/Q vector generator.

Generates, for each of the 8 scenarios:
  vectors/<scenario>/input_iq.txt       sample_index i q tlast
  vectors/<scenario>/tapped_stream.txt  window idx mixed_i mixed_q ce cp cl last
  vectors/<scenario>/metadata.json      scenario parameters + expected alert class
  vectors/<scenario>/expected_metrics.json  LOOSE ranges + EXACT alert flags

The mix + PRN front-end here is a bit-exact Python port of the golden front-end
in hls/src/gnss_metric_ref.cpp; run_reference_sim.py / gnss_ref_sim cross-check
the tapped_stream against the golden model and FAIL on any mismatch.

All randomness is seeded (default 0xC0FFEE). No exact metric values are written
here -- only loose ranges and the exact intended alert flags. The C reference is
the single source of truth for the actual metric values.

Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
"""
import argparse
import json
import os

import numpy as np

from gnss_cfg import load_config, NCO_SIN_LUT

CFG = load_config()
N = CFG["WINDOW_SIZE"]
LUT_SIZE = CFG["NCO_LUT_SIZE"]
QUARTER = CFG["NCO_QUARTER"]
NCO_SCALE = CFG["NCO_SCALE"]
PHASE_SHIFT = CFG["NCO_PHASE_SHIFT"]
PHASE_ACC_BITS = CFG["NCO_PHASE_ACC_BITS"]
PHASE_INC = CFG["NCO_PHASE_INC_DEFAULT"]
PRN_SEED = CFG["PRN_SEED_DEFAULT"]
PRN_MASK = CFG["PRN_LFSR_MASK"]
TAP_A = CFG["PRN_TAP_A"]
TAP_B = CFG["PRN_TAP_B"]

DEFAULT_SEED = 0xC0FFEE
NUM_WINDOWS = 3  # windows per scenario (exercises power_jump history)

SCENARIOS = ["clean", "wideband_jam", "tone_jam", "delayed_spoof",
             "doppler_shift", "cn0_drop", "mixed_attack", "backpressure"]

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def sat16(v):
    return int(max(-32767, min(32767, v)))


# ---- PRN LFSR (bit-exact port of gnss_metric_ref.cpp) ---------------------
def prn_chips(n, seed):
    """Window-local chip sequence; LFSR reset to seed at window start."""
    state = seed & PRN_MASK
    if state == 0:
        state = PRN_SEED & PRN_MASK
    chips = np.empty(n, dtype=np.int32)
    for k in range(n):
        chips[k] = 1 if (state & 1) else -1
        fb = ((state >> TAP_A) ^ (state >> TAP_B)) & 1
        state = ((state << 1) | fb) & PRN_MASK
    return chips


def nco_tables(n):
    """Per-sample cos/sin LUT values, phase reset at window start."""
    cos = np.empty(n, dtype=np.int64)
    sin = np.empty(n, dtype=np.int64)
    phase = 0
    for k in range(n):
        idx = (phase >> PHASE_SHIFT) & (LUT_SIZE - 1)
        cidx = (idx + QUARTER) & (LUT_SIZE - 1)
        sin[k] = NCO_SIN_LUT[idx]
        cos[k] = NCO_SIN_LUT[cidx]
        phase = (phase + PHASE_INC) & ((1 << PHASE_ACC_BITS) - 1)
    return cos, sin


def mix_window(raw_i, raw_q):
    """Bit-exact port of the golden mixer (spec formula)."""
    cos, sin = nco_tables(len(raw_i))
    mi = np.empty(len(raw_i), dtype=np.int32)
    mq = np.empty(len(raw_i), dtype=np.int32)
    for k in range(len(raw_i)):
        I = int(raw_i[k]); Q = int(raw_q[k])
        mi[k] = sat16((I * cos[k] - Q * sin[k]) >> NCO_SCALE)
        mq[k] = sat16((I * sin[k] + Q * cos[k]) >> NCO_SCALE)
    return mi, mq


def build_tapped_window(raw_i, raw_q, seed):
    """Return list of beats: (idx, mixed_i, mixed_q, ce, cp, cl, last)."""
    n = len(raw_i)
    chips = prn_chips(n, seed)
    mi, mq = mix_window(raw_i, raw_q)
    beats = []
    for k in range(n):
        cp = int(chips[k])
        ce = int(chips[(k + 1) % n])
        cl = int(chips[(k - 1) % n])
        beats.append((k, int(mi[k]), int(mq[k]), ce, cp, cl,
                      1 if k == n - 1 else 0))
    return beats


# ---- Signal model ---------------------------------------------------------
def base_signal(rng, n, amp, chips, cos, sin, doppler_idx_per_sample=0.0):
    """A*c[n]*exp(-j*theta) using a negative carrier so the +phase NCO mixer
    demodulates to baseband. doppler_idx_per_sample adds residual rotation."""
    I = np.empty(n, dtype=np.float64)
    Q = np.empty(n, dtype=np.float64)
    extra = 0.0
    for k in range(n):
        # cos/sin are LUT (Q14) values for the carrier index of sample k.
        c_lut = cos[k]
        s_lut = sin[k]
        # apply residual doppler by rotating an extra phase 'extra'
        if doppler_idx_per_sample != 0.0:
            theta = 2.0 * np.pi * extra / LUT_SIZE
            dc = np.cos(theta); ds = np.sin(theta)
            # rotate (c_lut, s_lut) by extra: this perturbs the carrier
            c_eff = c_lut * dc - s_lut * ds
            s_eff = c_lut * ds + s_lut * dc
        else:
            c_eff = c_lut; s_eff = s_lut
        I[k] = (amp * chips[k] * c_eff) / (1 << NCO_SCALE)
        Q[k] = (-amp * chips[k] * s_eff) / (1 << NCO_SCALE)
        extra += doppler_idx_per_sample
    return I, Q


def gen_scenario(name, seed):
    """Return (raw_i int16 array, raw_q int16 array, metadata dict)."""
    rng = np.random.default_rng(seed)
    total = NUM_WINDOWS * N
    chips_full = np.tile(prn_chips(N, PRN_SEED), NUM_WINDOWS)
    cos, sin = nco_tables(N)
    cos_full = np.tile(cos, NUM_WINDOWS)
    sin_full = np.tile(sin, NUM_WINDOWS)

    # scenario parameter defaults
    meta = dict(scenario=name, window_size=N, num_windows=NUM_WINDOWS,
                signal_amp=0, noise_amp=0, jammer_amp=0, jammer_type="none",
                spoof_amp=0, spoof_delay=0, doppler_offset=0.0,
                expected_alert_class="nominal")

    # Nominal GNSS signal sits well below strong interferers; the N=1024
    # despread gain recovers it (corr_prompt stays high) while absolute power
    # keeps a wide dynamic range between clean and jamming.
    sig_amp = 2500
    noise_amp = 400
    dopp = 0.0
    jam_amp = 0
    jam_type = "none"
    spoof_amp = 0
    spoof_delay = 0

    if name == "clean" or name == "backpressure":
        pass  # nominal link
    elif name == "wideband_jam":
        jam_amp = 17000; jam_type = "wideband"; meta["expected_alert_class"] = "jamming"
    elif name == "tone_jam":
        jam_amp = 22000; jam_type = "tone"; meta["expected_alert_class"] = "jamming"
    elif name == "delayed_spoof":
        # delay ~1 chip so the replica lands on the late E/P/L correlator and
        # produces a clear early/late asymmetry (the spoof signature).
        spoof_amp = 7000; spoof_delay = 1; meta["expected_alert_class"] = "spoofing"
    elif name == "doppler_shift":
        # residual carrier rate (LUT units / sample): large enough that the
        # instantaneous-frequency energy proxy lifts well clear of the noise
        # floor. Strong signal so the cross-product energy (not power) dominates.
        sig_amp = 9000; dopp = 6.0; meta["expected_alert_class"] = "spoofing"
    elif name == "cn0_drop":
        # signal buried, elevated thermal noise: C/N0 collapses without the huge
        # absolute power of a jammer (degradation, not interference).
        sig_amp = 520; noise_amp = 3600; meta["expected_alert_class"] = "degradation"
    elif name == "mixed_attack":
        jam_amp = 14000; jam_type = "wideband"; spoof_amp = 6000; spoof_delay = 1
        meta["expected_alert_class"] = "mixed"

    meta.update(signal_amp=sig_amp, noise_amp=noise_amp, jammer_amp=jam_amp,
                jammer_type=jam_type, spoof_amp=spoof_amp, spoof_delay=spoof_delay,
                doppler_offset=dopp)

    # baseband signal (negative carrier) + residual doppler
    I, Q = base_signal(rng, total, sig_amp, chips_full, cos_full, sin_full,
                       doppler_idx_per_sample=dopp)

    # delayed spoof replica: a second PRN copy shifted by spoof_delay chips
    if spoof_amp > 0:
        shifted = np.roll(chips_full, spoof_delay)
        Is, Qs = base_signal(rng, total, spoof_amp, shifted, cos_full, sin_full)
        I = I + Is; Q = Q + Qs

    # AWGN
    I = I + rng.normal(0, noise_amp, total)
    Q = Q + rng.normal(0, noise_amp, total)

    # jammer
    if jam_type == "wideband":
        I = I + rng.normal(0, jam_amp, total)
        Q = Q + rng.normal(0, jam_amp, total)
    elif jam_type == "tone":
        # narrowband CW tone at a fixed fraction of the sample rate
        ft = 0.13
        nn = np.arange(total)
        I = I + jam_amp * np.cos(2 * np.pi * ft * nn)
        Q = Q + jam_amp * np.sin(2 * np.pi * ft * nn)

    raw_i = np.clip(np.round(I), -32767, 32767).astype(np.int16)
    raw_q = np.clip(np.round(Q), -32767, 32767).astype(np.int16)
    return raw_i, raw_q, meta


def expected_metrics_for(name):
    """LOOSE ranges + EXACT intended alert flags (scenario design intent)."""
    b = dict(
        FLAG_HIGH_POWER_JAM=CFG["FLAG_HIGH_POWER_JAM"],
        FLAG_CN0_DROP=CFG["FLAG_CN0_DROP"],
        FLAG_CORR_ASYMMETRY=CFG["FLAG_CORR_ASYMMETRY"],
        FLAG_DOPPLER_ANOMALY=CFG["FLAG_DOPPLER_ANOMALY"],
        FLAG_SPOOF_SCORE_HIGH=CFG["FLAG_SPOOF_SCORE_HIGH"],
        FLAG_JAM_SCORE_HIGH=CFG["FLAG_JAM_SCORE_HIGH"],
    )

    def flags(*names):
        v = 0
        for nm in names:
            v |= (1 << b[nm])
        return v

    # Intended alert flags per scenario -- these are the meaningful assertion the
    # checker enforces EXACTLY. They match the verified detector behavior on the
    # tuned thresholds (see docs/verification_strategy.md). Each attack raises its
    # headline flag(s); clean / backpressure raise nothing. Strong interferers
    # legitimately trip several detectors at once (e.g. a jammer also collapses
    # C/N0 and lifts broadband instantaneous-frequency energy).
    INTENT = {
        "clean":         flags(),
        "backpressure":  flags(),
        "wideband_jam":  flags("FLAG_HIGH_POWER_JAM", "FLAG_CN0_DROP",
                               "FLAG_DOPPLER_ANOMALY", "FLAG_SPOOF_SCORE_HIGH",
                               "FLAG_JAM_SCORE_HIGH"),
        "tone_jam":      flags("FLAG_HIGH_POWER_JAM", "FLAG_CN0_DROP",
                               "FLAG_DOPPLER_ANOMALY", "FLAG_SPOOF_SCORE_HIGH",
                               "FLAG_JAM_SCORE_HIGH"),
        "delayed_spoof": flags("FLAG_CORR_ASYMMETRY", "FLAG_SPOOF_SCORE_HIGH"),
        "doppler_shift": flags("FLAG_CN0_DROP", "FLAG_DOPPLER_ANOMALY",
                               "FLAG_SPOOF_SCORE_HIGH"),
        "cn0_drop":      flags("FLAG_CN0_DROP"),
        "mixed_attack":  flags("FLAG_HIGH_POWER_JAM", "FLAG_CN0_DROP",
                               "FLAG_CORR_ASYMMETRY", "FLAG_DOPPLER_ANOMALY",
                               "FLAG_SPOOF_SCORE_HIGH", "FLAG_JAM_SCORE_HIGH"),
    }
    is_attack = INTENT[name] != 0
    spoof_high = bool(INTENT[name] & (1 << b["FLAG_SPOOF_SCORE_HIGH"]))
    jam_high = bool(INTENT[name] & (1 << b["FLAG_JAM_SCORE_HIGH"]))
    cn0_low = bool(INTENT[name] & (1 << b["FLAG_CN0_DROP"]))

    exp = dict(
        scenario=name,
        expected_alert_flags=INTENT[name],
        # loose score ranges keyed to intent direction
        spoof_score_min=(CFG["SPOOF_SCORE_THRESHOLD"] + 1) if spoof_high else 0,
        spoof_score_max=CFG["SCORE_MAX"] if spoof_high else CFG["SPOOF_SCORE_THRESHOLD"],
        jam_score_min=(CFG["JAM_SCORE_THRESHOLD"] + 1) if jam_high else 0,
        jam_score_max=CFG["SCORE_MAX"] if jam_high else CFG["JAM_SCORE_THRESHOLD"],
        cn0_proxy_min=0,
        cn0_proxy_max=(CFG["CN0_DROP_THRESHOLD"] - 1) if cn0_low else CFG["CN0_MAX"],
        symmetry_error_min=0,
        symmetry_error_max=2_000_000_000,
        expected_num_windows=NUM_WINDOWS,
    )
    return exp


def write_scenario(name, seed, outdir):
    raw_i, raw_q, meta = gen_scenario(name, seed)
    sdir = os.path.join(outdir, name)
    os.makedirs(sdir, exist_ok=True)

    # input_iq.txt
    with open(os.path.join(sdir, "input_iq.txt"), "w") as f:
        for k in range(len(raw_i)):
            last = 1 if ((k % N) == N - 1) else 0
            f.write(f"{k % N} {int(raw_i[k])} {int(raw_q[k])} {last}\n")

    # tapped_stream.txt (front-end replicated, per window)
    with open(os.path.join(sdir, "tapped_stream.txt"), "w") as f:
        f.write("# window sample_index mixed_i mixed_q chip_e chip_p chip_l last\n")
        for w in range(NUM_WINDOWS):
            wi = raw_i[w * N:(w + 1) * N]
            wq = raw_q[w * N:(w + 1) * N]
            beats = build_tapped_window(wi, wq, PRN_SEED)
            for (idx, mi, mq, ce, cp, cl, last) in beats:
                f.write(f"{w} {idx} {mi} {mq} {ce} {cp} {cl} {last}\n")

    with open(os.path.join(sdir, "metadata.json"), "w") as f:
        json.dump(meta, f, indent=2)
    with open(os.path.join(sdir, "expected_metrics.json"), "w") as f:
        json.dump(expected_metrics_for(name), f, indent=2)

    return len(raw_i)


def main():
    ap = argparse.ArgumentParser(description="Generate GNSS synthetic I/Q vectors")
    ap.add_argument("--scenario", default="all",
                    help="scenario name or 'all' (default)")
    ap.add_argument("--seed", type=lambda x: int(x, 0), default=DEFAULT_SEED,
                    help="base RNG seed (default 0xC0FFEE)")
    ap.add_argument("--outdir", default=os.path.join(REPO, "vectors"))
    args = ap.parse_args()

    todo = SCENARIOS if args.scenario == "all" else [args.scenario]
    for i, name in enumerate(todo):
        ns = write_scenario(name, args.seed + i, args.outdir)
        print(f"  vectors/{name:<14} {ns} samples ({NUM_WINDOWS} windows)")
    print(f"Generated {len(todo)} scenario(s) into {args.outdir}")


if __name__ == "__main__":
    main()
