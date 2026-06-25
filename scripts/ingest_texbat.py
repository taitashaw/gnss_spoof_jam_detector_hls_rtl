#!/usr/bin/env python3
"""ingest_texbat.py -- extract a real TEXBAT I/Q slice into a repo vector set.

Reads ONLY the byte range it needs from a multi-GB TEXBAT .bin (via seek; never
loads the whole file) and writes a vector set in the same format as the synthetic
scenarios: input_iq.txt + tapped_stream.txt + metadata.json. The mix/PRN front-end
is the repo's own (reused from gen_gnss_vectors), so the HLS C-sim path stays
consistent with the RTL path.

Format is the one CONFIRMED empirically by scripts/texbat_probe.py:
  int16 complex, little-endian, I/Q interleaved (I first), 25.000 Msps, 16-bit.

The repo is a rate-agnostic streaming accelerator (no fixed input rate), so the
native TEXBAT 25 Msps int16 samples are fed directly -- they already match the s16
AXIS contract (tdata[31:16]=I, tdata[15:0]=Q) and sit well inside int16 range, so
NO decimation and NO rescaling are applied (documented in metadata).

Usage: ingest_texbat.py <bin_path> <ds2|ds7> <clean|spoofed> <start_time_sec> <window_count>
Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
"""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gnss_cfg import load_config
from gen_gnss_vectors import build_tapped_window, PRN_SEED

# ---- CONFIRMED TEXBAT format (scripts/texbat_probe.py) ----
SAMPLE_RATE = 25.0e6
BYTES_PER_COMPLEX = 4      # int16 I + int16 Q
DTYPE = "<i2"              # little-endian int16
INTERLEAVE = "I-then-Q"

CFG = load_config()
N = CFG["WINDOW_SIZE"]

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CITATION = ("T. E. Humphreys, J. A. Bhatti, D. P. Shepard, K. D. Wesson, "
            "\"The Texas Spoofing Test Battery: Toward a Standard for Evaluating "
            "GPS Signal Authentication Techniques,\" Proc. ION GNSS+ 2012.")
SOURCE_URL = "radionavlab.ae.utexas.edu/texbat"

SCEN_DESC = {
    "ds2": "Static receiver, overpowered time-push spoofing (carrier-phase "
           "unaligned, ~10 dB power advantage) -- an intermediate-difficulty attack.",
    "ds7": "Static receiver, matched-power security-code-estimation-and-replay "
           "(SCER) spoofing -- the hardest TEXBAT class (power-matched, code-aligned).",
}


def cached_sha256(bin_path):
    """Return the SHA256 from a sibling .sha256 cache if present, else compute it."""
    base = os.path.basename(bin_path)
    for cand in (f"/tmp/{base.replace('.bin','')}.sha256", bin_path + ".sha256"):
        if os.path.isfile(cand):
            txt = open(cand).read().split()
            if txt:
                return txt[0]
    # fall back: stream the file (slow; reads all bytes once)
    import hashlib
    h = hashlib.sha256()
    with open(bin_path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 24), b""):
            h.update(chunk)
    return h.hexdigest()


def read_slice(bin_path, start_time, window_count):
    n_complex = window_count * N
    start_sample = int(round(start_time * SAMPLE_RATE))
    byte_off = start_sample * BYTES_PER_COMPLEX
    nbytes = n_complex * BYTES_PER_COMPLEX
    with open(bin_path, "rb") as f:
        f.seek(byte_off)
        buf = f.read(nbytes)
    a = np.frombuffer(buf, dtype=DTYPE)
    a = a[: (len(a) // 2) * 2]
    i = a[0::2]
    q = a[1::2]
    m = min(len(i), len(q), n_complex)
    i = np.clip(i[:m].astype(np.int32), -32767, 32767).astype(np.int16)
    q = np.clip(q[:m].astype(np.int32), -32767, 32767).astype(np.int16)
    return i, q, byte_off, m


def main():
    if len(sys.argv) < 6:
        print("usage: ingest_texbat.py <bin_path> <ds2|ds7> <clean|spoofed> "
              "<start_time_sec> <window_count>"); return 2
    bin_path = sys.argv[1]
    scen = sys.argv[2]
    slc = sys.argv[3]
    start_time = float(sys.argv[4])
    window_count = int(sys.argv[5])

    if not os.path.isfile(bin_path):
        print(f"ERROR: {bin_path} not found"); return 1

    raw_i, raw_q, byte_off, m = read_slice(bin_path, start_time, window_count)
    nwin = m // N
    if nwin == 0:
        print("ERROR: slice too short"); return 1
    raw_i = raw_i[: nwin * N]; raw_q = raw_q[: nwin * N]

    name = f"texbat_{scen}_{slc}"
    sdir = os.path.join(REPO, "vectors", name)
    os.makedirs(sdir, exist_ok=True)

    # input_iq.txt (idx i q tlast), tlast every window
    with open(os.path.join(sdir, "input_iq.txt"), "w") as f:
        for k in range(nwin * N):
            last = 1 if ((k % N) == N - 1) else 0
            f.write(f"{k % N} {int(raw_i[k])} {int(raw_q[k])} {last}\n")

    # tapped_stream.txt via the repo's own front-end (mix + PRN), per window
    with open(os.path.join(sdir, "tapped_stream.txt"), "w") as f:
        f.write("# window sample_index mixed_i mixed_q chip_e chip_p chip_l last\n")
        for w in range(nwin):
            wi = raw_i[w * N:(w + 1) * N]
            wq = raw_q[w * N:(w + 1) * N]
            for (idx, mi, mq, ce, cp, cl, last) in build_tapped_window(wi, wq, PRN_SEED):
                f.write(f"{w} {idx} {mi} {mq} {ce} {cp} {cl} {last}\n")

    sha = cached_sha256(bin_path)
    meta = dict(
        source=SOURCE_URL,
        citation=CITATION,
        scenario=scen,
        scenario_description=SCEN_DESC.get(scen, ""),
        slice=slc,
        real_recorded_attack_data=True,
        synthetic=False,
        source_file=os.path.abspath(bin_path),
        source_sha256=sha,
        confirmed_format=dict(sample_rate_hz=SAMPLE_RATE, sample_width_bits=16,
                              dtype="int16", endianness="little-endian",
                              interleave=INTERLEAVE),
        decimation="none (repo is rate-agnostic streaming; native 25 Msps int16 fed directly)",
        rescaling="none (TEXBAT int16 already matches the s16 AXIS contract)",
        slice_start_time_sec=start_time,
        slice_byte_offset=byte_off,
        slice_window_count=nwin,
        slice_complex_samples=nwin * N,
        slice_duration_sec=nwin * N / SAMPLE_RATE,
        window_size=N,
    )
    with open(os.path.join(sdir, "metadata.json"), "w") as f:
        json.dump(meta, f, indent=2)

    print(f"  vectors/{name}: {nwin} windows from t={start_time}s "
          f"(byte {byte_off}), {nwin*N} complex samples, "
          f"{nwin*N/SAMPLE_RATE*1000:.2f} ms, sha={sha[:12]}...")
    return 0


if __name__ == "__main__":
    sys.exit(main())
