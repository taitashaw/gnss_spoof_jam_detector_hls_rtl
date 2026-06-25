#!/usr/bin/env python3
"""texbat_probe.py -- empirically verify the byte layout of a TEXBAT .bin file.

TEXBAT (UT Austin Radionavigation Lab) recordings are documented as interleaved
complex I/Q, signed 16-bit, little-endian. This script does NOT trust that blindly:
it reads only the first ~1 MB, decodes under candidate sample rates / endianness /
interleave, and confirms the layout whose implied duration is physically sensible
(a few hundred seconds) with sane int16 sample statistics.

Reads at most 1 MB. Never loads the multi-GB file into memory.

Usage: texbat_probe.py <path-to-.bin>
Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
"""
import os
import sys

import numpy as np

# candidate complex sample rates (Hz). 25 Msps is the documented TEXBAT rate;
# 46.08 Msps is the Humphreys ION-GNSS-2012 front-end figure (tested for contrast).
CANDIDATE_RATES = [25.0e6, 46.08e6, 25.0e6 * 0.5]
BYTES_PER_COMPLEX = 4  # int16 I + int16 Q
PROBE_BYTES = 1 << 20  # 1 MiB


def decode(buf, dtype):
    a = np.frombuffer(buf, dtype=dtype)
    a = a[: (len(a) // 2) * 2]
    i = a[0::2].astype(np.float64)
    q = a[1::2].astype(np.float64)
    return i, q


def stats(i, q):
    mag = np.sqrt(i * i + q * q)
    power = float(np.mean(i * i + q * q))
    sat = float(np.mean((np.abs(i) >= 32767) | (np.abs(q) >= 32767)))
    return dict(power=power, rms=float(np.sqrt(power)),
                imin=float(i.min()), imax=float(i.max()),
                qmin=float(q.min()), qmax=float(q.max()),
                magmax=float(mag.max()), sat_frac=sat)


def main():
    if len(sys.argv) < 2:
        print("usage: texbat_probe.py <path-to-.bin>"); return 2
    path = sys.argv[1]
    size = os.path.getsize(path)
    n_complex = size // BYTES_PER_COMPLEX

    print(f"file: {path}")
    print(f"size_bytes: {size}")
    print(f"complex_samples (int16 I/Q): {n_complex}")

    # duration under each candidate rate
    print("\ncandidate sample rates -> implied duration:")
    best_rate = None
    for r in CANDIDATE_RATES:
        dur = n_complex / r
        flag = ""
        if 300.0 <= dur <= 520.0:
            flag = "  <- physically plausible (~few hundred s)"
            if best_rate is None:
                best_rate = r
        print(f"  {r/1e6:8.3f} Msps -> {dur:8.2f} s{flag}")

    with open(path, "rb") as f:
        buf = f.read(PROBE_BYTES)

    print("\nsample-statistics by endianness (first 1 MiB, I/Q interleaved):")
    le_i, le_q = decode(buf, "<i2")
    be_i, be_q = decode(buf, ">i2")
    le = stats(le_i, le_q)
    be = stats(be_i, be_q)
    print(f"  little-endian: rms={le['rms']:8.1f} magmax={le['magmax']:8.0f} "
          f"sat_frac={le['sat_frac']:.4f} I[{le['imin']:.0f},{le['imax']:.0f}]")
    print(f"  big-endian:    rms={be['rms']:8.1f} magmax={be['magmax']:8.0f} "
          f"sat_frac={be['sat_frac']:.4f} I[{be['imin']:.0f},{be['imax']:.0f}]")
    # little-endian on an x86 recording should show non-saturated, non-zero power;
    # a wrong endianness typically inflates the dynamic range / saturation.
    endian = "<i2" if (le["power"] > 0 and le["sat_frac"] <= be["sat_frac"]) else ">i2"
    endian_name = "little-endian" if endian == "<i2" else "big-endian"

    di, dq = decode(buf, endian)
    print("\nfirst 8 decoded I/Q pairs (%s, I-then-Q interleave):" % endian_name)
    for k in range(8):
        print(f"  [{k}] I={int(di[k]):7d}  Q={int(dq[k]):7d}")

    power = float(np.mean(di * di + dq * dq))
    ok = (best_rate is not None) and (power > 0.0)
    print()
    if ok:
        dur = n_complex / best_rate
        print(f"CONFIRMED FORMAT: int16 complex, {endian_name}, I/Q interleaved "
              f"(I first), sample_rate={best_rate/1e6:.3f} Msps, "
              f"width=16-bit, duration={dur:.2f} s, mean_power={power:.1f}")
        return 0
    else:
        print("FORMAT NOT CONFIRMED: no candidate rate gives a plausible duration, "
              "or decoded power is zero. STOP -- do not process with a guessed format.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
