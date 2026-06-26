#!/usr/bin/env python3
"""gps_ca.py -- GPS L1 C/A Gold-code generator (real PRN codes).

Clean-room re-implementation from the public IS-GPS-200 specification, faithful to
the algorithm in the source receiver's gen_ca_code.m (John Bagshaw, Prof. Sunil
Bisnath, York University -- "Fast GNSS Receiver MATLAB"). The PRN-like LFSR used by
the streaming front-end elsewhere in this repo is NOT a C/A code; this module
generates the actual G1/G2 Gold codes so the delay-Doppler acquisition correlates
against real satellite codes.

Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
"""
import numpy as np

# G2 phase-selector shift per PRN (1-indexed PRN -> g2 shift), IS-GPS-200.
G2_SHIFT = [
    5, 6, 7, 8, 17, 18, 139, 140, 141, 251,
    252, 254, 255, 256, 257, 258, 469, 470, 471, 472,
    473, 474, 509, 512, 513, 514, 515, 516, 859, 860,
    861, 862,
]
CA_LEN = 1023


def ca_code(prn):
    """Return the length-1023 C/A code for PRN (1..32) as +/-1 (float)."""
    if not (1 <= prn <= 32):
        raise ValueError("PRN must be 1..32")
    g1 = np.zeros(CA_LEN, dtype=np.int8)
    g2 = np.zeros(CA_LEN, dtype=np.int8)
    reg1 = -np.ones(10, dtype=np.int8)
    reg2 = -np.ones(10, dtype=np.int8)
    for i in range(CA_LEN):
        g1[i] = reg1[9]
        g2[i] = reg2[9]
        fb1 = reg1[2] * reg1[9]
        fb2 = reg2[1] * reg2[2] * reg2[5] * reg2[7] * reg2[8] * reg2[9]
        reg1 = np.roll(reg1, 1); reg1[0] = fb1
        reg2 = np.roll(reg2, 1); reg2[0] = fb2
    shift = G2_SHIFT[prn - 1]
    code = -(g1 * np.roll(g2, shift))
    return code.astype(np.float64)


def upsample_ca(prn, samples_per_code):
    """Digitize the C/A code to samples_per_code samples spanning one 1 ms period.

    samples_per_code samples map across the 1023 chips: chip index for sample k
    (1-based) = ceil(k * 1023 / N), last clamped to 1023 (MATLAB make_ca_table).
    """
    code = ca_code(prn)
    k = np.arange(1, samples_per_code + 1)
    idx = np.ceil(k * CA_LEN / samples_per_code).astype(int)
    idx[-1] = CA_LEN
    idx = np.clip(idx - 1, 0, CA_LEN - 1)  # 0-based
    return code[idx]


if __name__ == "__main__":
    # self-test: C/A autocorrelation peaks at 1023, off-peak in {-1, 63, -65}
    import sys
    prn = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    c = ca_code(prn)
    ac = np.array([np.sum(c * np.roll(c, k)) for k in range(CA_LEN)])
    vals = sorted(set(ac.astype(int)))
    print(f"PRN {prn}: code len={len(c)}, sum={int(c.sum())} (balance)")
    print(f"  autocorr peak={int(ac[0])}, off-peak distinct values={vals[:6]}...")
    ok = ac[0] == 1023 and set(np.unique(ac.astype(int))).issubset({1023, -1, 63, -65})
    print("  CA AUTOCORRELATION OK (peak 1023, off-peak in {-1,63,-65})" if ok
          else "  CA CODE CHECK FAILED")
