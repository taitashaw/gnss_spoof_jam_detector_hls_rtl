#!/usr/bin/env python3
"""gen_fft_twiddle.py -- generate the fixed-point FFT twiddle ROM (compile-time).

Emits hls/include/fft_twiddle_re.inc and fft_twiddle_im.inc as comma-separated
double literals W[k] = exp(-j 2 pi k / N), k = 0..N/2-1. fft_fixed.hpp includes
them inside an ap_fixed const-array initializer, so the values are converted to
fixed-point at COMPILE time (a ROM); there is no runtime floating point.

Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
"""
import os

import numpy as np

N = 2048
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "hls", "include")


def main():
    k = np.arange(N // 2)
    w = np.exp(-2j * np.pi * k / N)
    for name, arr in [("re", w.real), ("im", w.imag)]:
        path = os.path.join(OUT, f"fft_twiddle_{name}.inc")
        with open(path, "w") as f:
            for i in range(0, len(arr), 8):
                f.write(", ".join(f"{v:.12g}" for v in arr[i:i + 8]))
                f.write(",\n" if i + 8 < len(arr) else "\n")
        print(f"wrote {path} ({len(arr)} entries)")


if __name__ == "__main__":
    main()
