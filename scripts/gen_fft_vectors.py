#!/usr/bin/env python3
"""gen_fft_vectors.py -- test vectors + numpy.fft golden for the fixed-point FFT.

For each case writes vectors/fft_test/in_<case>.txt (re im per line) and
gold_<case>.txt (re im per line). The fixed-point FFT is the scaled variant
(divide by 2 per stage, total /N), so its output approximates numpy.fft(x)/N --
the golden is therefore numpy.fft(x)/N, compared directly by tb_fft_fixed.cpp.

Cases: impulse, shifted impulse, single tone, complex random, real C/A block.

Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
"""
import os

import numpy as np

from gps_ca import upsample_ca

N = 2048
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "vectors", "fft_test")


def write_case(name, x):
    os.makedirs(OUT, exist_ok=True)
    x = x.astype(complex)
    gold = np.fft.fft(x) / N            # scaled to match the /N fixed-point FFT
    with open(os.path.join(OUT, f"in_{name}.txt"), "w") as f:
        for v in x:
            f.write(f"{v.real:.9f} {v.imag:.9f}\n")
    with open(os.path.join(OUT, f"gold_{name}.txt"), "w") as f:
        for v in gold:
            f.write(f"{v.real:.9e} {v.imag:.9e}\n")
    print(f"  {name:<12} |x|max={np.max(np.abs(x)):.3f}  |gold|max={np.max(np.abs(gold)):.3e}")


def main():
    rng = np.random.default_rng(42)
    print("fixed-point FFT test vectors + numpy golden (N=2048):")

    imp = np.zeros(N); imp[0] = 0.5
    write_case("impulse", imp)

    sh = np.zeros(N); sh[7] = 0.5
    write_case("impulse7", sh)

    n = np.arange(N)
    write_case("tone", 0.5 * np.exp(2j * np.pi * 137 * n / N))

    write_case("random", 0.4 * (rng.standard_normal(N) + 1j * rng.standard_normal(N)) / np.sqrt(2))

    ca = np.zeros(N); ca[:2046] = 0.5 * upsample_ca(5, 2046)
    write_case("ca_block", ca)

    # list for the testbench to iterate
    with open(os.path.join(OUT, "cases.txt"), "w") as f:
        f.write("impulse\nimpulse7\ntone\nrandom\nca_block\n")


if __name__ == "__main__":
    main()
