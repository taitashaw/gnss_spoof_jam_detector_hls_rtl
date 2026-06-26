#!/usr/bin/env python3
"""pcs_acq.py -- parallel-code-search (PCS) acquisition baseline.

Faithful re-implementation (clean-room, MIT) of the PCS baseline in the source
receiver's norm_acq_parcode.m (John Bagshaw, Prof. Sunil Bisnath, York University):
for each Doppler bin, wipe off the carrier, do one 1 ms FFT circular correlation
per code period, and accumulate |corr|^2 NON-coherently across the blocks. This is
the standard baseline against which the DBZP coherent ddMap (scripts/dbzp_acq.py)
is benchmarked. It returns the SAME result dict shape as dbzp_acq.acquire so the
identical detection_metrics run on both.

Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
"""
import numpy as np

from dbzp_acq import code_fft, DOPP_MAX

PCS_DOPP_STEP = 250.0   # fine Doppler step (Hz); PCS has no cross-block FFT


def pcs_acquire(x, prn, fs, integ_ms):
    """Non-coherent parallel-code-search acquisition over integ_ms 1 ms blocks."""
    ns = int(round(fs * 1e-3))
    nblk = integ_ms
    need = ns * nblk
    if len(x) < need:
        nblk = len(x) // ns
        need = ns * nblk
    blocks = x[:need].reshape(nblk, ns)
    t = np.arange(ns) / fs
    cf = np.conj(code_fft(prn, ns))

    dopp_grid = np.arange(-DOPP_MAX, DOPP_MAX + 1, PCS_DOPP_STEP)
    ddmap = np.zeros((len(dopp_grid), ns))     # non-coherent code-Doppler map
    for di, fd in enumerate(dopp_grid):
        wipe = np.exp(-2j * np.pi * fd * t)
        bw = blocks * wipe[None, :]
        Bf = np.fft.fft(bw, axis=1)
        corr = np.fft.ifft(Bf * cf[None, :], axis=1)
        ddmap[di] = np.sum(np.abs(corr) ** 2, axis=0)   # |.|^2 non-coherent accum
    bi = np.unravel_index(np.argmax(ddmap), ddmap.shape)
    noise = float(np.median(ddmap))
    return dict(power=float(ddmap[bi]), doppler=float(dopp_grid[bi[0]]),
                code_phase=int(bi[1]), profile=ddmap[bi[0]].copy(),
                noise=noise, snr=float(ddmap[bi]) / noise if noise > 0 else 0.0,
                nblk=nblk, ns=ns)
