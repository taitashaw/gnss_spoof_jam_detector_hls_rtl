#!/usr/bin/env python3
"""ddmap_hls_vectors.py -- test vectors + float golden for the ddMap/SQM HLS kernel.

Generates pre-wiped 1 ms blocks (int16 I/Q) and the float reference (peak code
phase, early/late SQM distortion) at the kernel's matched config (2 samples/chip,
2048-pt FFT, coherent sum over N_BLK blocks), so hls/tb/tb_ddmap_sqm_hls.cpp can
check the fixed-point kernel against the golden. Cases: clean correct PRN, wrong
PRN, and a real TEXBAT ds7 spoofed slice (carrier-wiped at the acquired Doppler).

Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
"""
import os
import sys

import numpy as np

from gps_ca import upsample_ca

NS = 2046
FFT = 2048
SPC = 2
N_BLK = 4
FS = NS * 1000.0          # 2.046 Msps (2 samples/chip)
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "vectors", "ddmap_hls")


def code_fd(prn):
    c = np.zeros(FFT); c[:NS] = upsample_ca(prn, NS)
    return np.fft.fft(c)


def golden(blocks, corr_prn):
    """Float reference: coherent FFT-correlation + SQM over the int16 blocks."""
    cfd = code_fd(corr_prn)
    accum = np.zeros(FFT, dtype=complex)
    for blk in blocks:
        x = (blk[:, 0] + 1j * blk[:, 1]) / 32768.0
        accum += np.fft.ifft(np.fft.fft(x) * np.conj(cfd))
    P = np.abs(accum) ** 2
    peak = int(np.argmax(P[:NS]))
    e = (peak - SPC // 2) % NS
    l = (peak + SPC // 2) % NS
    dist = abs(P[e] - P[l]) / (P[e] + P[l] + 1e-30)
    return dict(peak=peak, dist=dist, peak_power=float(P[peak]),
                e_power=float(P[e]), l_power=float(P[l]))


def write_case(name, blocks, corr_prn):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, f"blocks_{name}.txt"), "w") as f:
        for blk in blocks:
            for i in range(FFT):
                iv = int(blk[i, 0]) if i < len(blk) else 0
                qv = int(blk[i, 1]) if i < len(blk) else 0
                f.write(f"{iv} {qv}\n")
    g = golden(blocks, corr_prn)
    with open(os.path.join(OUT, f"ref_{name}.txt"), "w") as f:
        f.write(f"prn={corr_prn}\npeak={g['peak']}\ndistortion={g['dist']:.6f}\n"
                f"peak_power={g['peak_power']:.6e}\n")
    print(f"  {name:<14} corr_prn={corr_prn} peak={g['peak']} distortion={g['dist']:.4f} "
          f"peak_power={g['peak_power']:.3e}")
    return g


def synth_blocks(prn, phase, amp, noise, seed):
    rng = np.random.default_rng(seed)
    code = upsample_ca(prn, NS)
    sig = amp * np.roll(code, phase)
    blocks = []
    for b in range(N_BLK):
        blk = np.zeros((FFT, 2))
        blk[:NS, 0] = np.clip(np.round(sig + rng.normal(0, noise, NS)), -32767, 32767)
        blk[:NS, 1] = np.clip(np.round(rng.normal(0, noise, NS)), -32767, 32767)
        blocks.append(blk)
    return blocks


def texbat_ds7_blocks():
    """N_BLK real ds7-spoofed blocks, decimated to 2.046 Msps, wiped at acq Doppler."""
    from dbzp_acq import read_iq, acquire, FS as FS25
    x25 = read_iq("/home/jotshawlinux/Downloads/ds7.bin", 250.0, N_BLK + 2, decim=2)
    # find a strong PRN + its Doppler with the full-rate acquisition
    fs12 = FS25 / 2
    cand = sorted(((acquire(x25, p, fs12, N_BLK)["snr"], p) for p in range(1, 33)),
                  reverse=True)
    prn = cand[0][1]; a = acquire(x25, prn, fs12, N_BLK)
    dopp = a["doppler"]
    # re-read and decimate to 2 samples/chip (NS per ms), wipe carrier
    xr = read_iq("/home/jotshawlinux/Downloads/ds7.bin", 250.0, N_BLK + 2, decim=1)
    # decimate 25 Msps -> 2.046 Msps by averaging in NS-per-ms grid
    spc_full = int(round(25e6 * 1e-3))  # 25000 samples/ms
    blocks = []
    for b in range(N_BLK):
        seg = xr[b * spc_full:(b + 1) * spc_full]
        # resample to NS samples (simple decimation by index)
        idx = (np.arange(NS) * spc_full / NS).astype(int)
        s = seg[idx]
        t = (b * spc_full + idx) / 25e6
        s = s * np.exp(-2j * np.pi * dopp * t)
        blk = np.zeros((FFT, 2))
        sc = 32767 / (np.max(np.abs(s)) + 1e-9) * 0.5
        blk[:NS, 0] = np.clip(np.round(s.real * sc), -32767, 32767)
        blk[:NS, 1] = np.clip(np.round(s.imag * sc), -32767, 32767)
        blocks.append(blk)
    return blocks, prn


def main():
    print("ddMap/SQM HLS test vectors + float golden (2 samp/chip, 2048 FFT):")
    write_case("clean_p5", synth_blocks(5, 600, 8000, 400, 1), 5)        # correct PRN
    write_case("wrong_p6", synth_blocks(5, 600, 8000, 400, 1), 6)        # wrong code
    try:
        blks, prn = texbat_ds7_blocks()
        write_case(f"ds7_p{prn}", blks, prn)
        with open(os.path.join(OUT, "ds7_prn.txt"), "w") as f:
            f.write(str(prn))
    except Exception as ex:                                              # noqa
        print(f"  ds7 case skipped: {ex}")


if __name__ == "__main__":
    main()
