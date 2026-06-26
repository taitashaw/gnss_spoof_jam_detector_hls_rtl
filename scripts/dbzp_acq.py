#!/usr/bin/env python3
"""dbzp_acq.py -- DBZP coherent acquisition + single-pass spoof/jam detection.

Builds the acquisition delay-Doppler correlation map (ddMap) for real GPS C/A PRNs
using coherent integration over `coherent_ms`, and computes the spoof/jam detection
statistics DIRECTLY from that same ddMap -- one pass, no separate tracking stage.

Faithful re-implementation (clean-room, MIT) of the coherent-integration approach
in the source receiver's weak_acq_optimized_DBZP.m / norm_acq_parcode.m
(John Bagshaw, Prof. Sunil Bisnath, York University -- "Fast GNSS Receiver
MATLAB"). The coherent gain comes from a cross-block FFT that combines `coherent_ms`
one-millisecond correlations coherently (the DBZP sensitivity mechanism).

Reads raw I/Q directly from the multi-GB TEXBAT .bin by byte offset (never loads
the whole file; the .bin is never committed).

Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
"""
import numpy as np

from gps_ca import upsample_ca

FS = 25.0e6                # confirmed TEXBAT complex sample rate
BYTES_PER_COMPLEX = 4
DOPP_MAX = 6000.0          # +/- Doppler search (Hz)
DOPP_COARSE = 1000.0       # coarse carrier-wipeoff step (Hz); fine via cross-block FFT


def read_iq(path, start_s, n_ms, decim=2):
    """Read n_ms ms of complex I/Q from .bin at start_s; block-average by `decim`."""
    ns_full = int(round(FS * 1e-3)) * n_ms          # samples at full rate
    start = int(round(start_s * FS))
    with open(path, "rb") as f:
        f.seek(start * BYTES_PER_COMPLEX)
        buf = f.read(ns_full * BYTES_PER_COMPLEX)
    a = np.frombuffer(buf, dtype="<i2").astype(np.float64)
    a = a[: (len(a) // 2) * 2]
    x = a[0::2] + 1j * a[1::2]
    if decim > 1:
        m = (len(x) // decim) * decim
        x = x[:m].reshape(-1, decim).mean(axis=1)
    return x


_CODE_FFT = {}


def code_fft(prn, ns):
    key = (prn, ns)
    if key not in _CODE_FFT:
        _CODE_FFT[key] = np.fft.fft(upsample_ca(prn, ns))
    return _CODE_FFT[key]


def acquire(x, prn, fs, coherent_ms):
    """DBZP-style coherent acquisition for one PRN over coherent_ms blocks.

    Returns a dict with the peak, its delay-Doppler location, the noise floor, and
    the code-phase power profile at the best Doppler (the ddMap row used for the
    single-pass detection metrics).
    """
    ns = int(round(fs * 1e-3))             # samples per 1 ms code period
    nblk = coherent_ms
    need = ns * nblk
    if len(x) < need:
        nblk = len(x) // ns
        need = ns * nblk
    blocks = x[:need].reshape(nblk, ns)    # [block, sample]
    t = np.arange(ns) / fs
    cf = np.conj(code_fft(prn, ns))

    coarse_grid = np.arange(-DOPP_MAX, DOPP_MAX + 1, DOPP_COARSE)
    best = dict(power=-1.0)
    # full per-Doppler peak track for noise-floor estimation
    floor_samples = []

    for fc in coarse_grid:
        wipe = np.exp(-2j * np.pi * fc * t)
        bw = blocks * wipe[None, :]                       # carrier wipeoff
        Bf = np.fft.fft(bw, axis=1)                       # per-block FFT
        corr = np.fft.ifft(Bf * cf[None, :], axis=1)      # circular corr per block
        # cross-block FFT -> coherent integration over nblk ms, fine Doppler
        Fd = np.fft.fftshift(np.fft.fft(corr, axis=0), axes=0)   # [fine_dopp, code]
        P = np.abs(Fd) ** 2
        floor_samples.append(np.median(P))
        bi = np.unravel_index(np.argmax(P), P.shape)
        if P[bi] > best["power"]:
            fine = np.fft.fftshift(np.fft.fftfreq(nblk, d=1e-3))
            best = dict(power=float(P[bi]),
                        doppler=float(fc + fine[bi[0]]),
                        code_phase=int(bi[1]),
                        profile=P[bi[0]].copy(),   # code-phase power at best Doppler
                        nblk=nblk, ns=ns)
    noise = float(np.median(floor_samples))
    best["noise"] = noise
    best["snr"] = best["power"] / noise if noise > 0 else 0.0
    return best


def detection_metrics(acq, fs, guard_chips=2.0):
    """Single-pass spoof/jam metrics computed FROM the ddMap (one PRN)."""
    prof = acq["profile"]
    ns = acq["ns"]
    noise = acq["noise"]
    samp_per_chip = fs / 1.023e6
    guard = int(round(guard_chips * samp_per_chip))
    main_i = int(np.argmax(prof))
    main_p = float(prof[main_i])

    # adaptive threshold for secondary peaks
    thr = noise * 25.0  # ~14 dB over the median floor

    # (a) PEAK COUNT: peaks above thr separated from the main peak by > guard
    #     (circular code phase). >1 distinct peak => spoof candidate.
    idx = np.arange(ns)
    dist = np.minimum((idx - main_i) % ns, (main_i - idx) % ns)
    secondary_mask = (prof > thr) & (dist > guard)
    # count local maxima within the secondary region
    peak_count = 1
    second_p = 0.0
    if secondary_mask.any():
        sp = prof.copy(); sp[~secondary_mask] = 0.0
        # collapse contiguous runs to single peaks
        above = secondary_mask.astype(int)
        edges = np.diff(np.concatenate(([0], above, [0])))
        starts = np.where(edges == 1)[0]; ends = np.where(edges == -1)[0]
        peak_count = 1 + len(starts)
        second_p = float(max((prof[s:e].max() for s, e in zip(starts, ends)), default=0.0))

    # (c) PEAK RATIO: strongest secondary / main
    peak_ratio = second_p / main_p if main_p > 0 else 0.0

    # (b) PEAK DISTORTION: early/late symmetry of the main peak at +/- 0.5 chip.
    #     Ideal C/A peak is a symmetric triangle -> ratio ~1. A superimposed spoof
    #     replica at a nearby code phase skews it.
    half = int(round(0.5 * samp_per_chip))
    early = float(prof[(main_i - half) % ns])
    late = float(prof[(main_i + half) % ns])
    distortion = abs(early - late) / (early + late + 1e-9)

    # (d) NOISE-FLOOR ELEVATION (jamming): floor power relative to a nominal.
    floor = noise

    return dict(main_power=main_p, peak_count=peak_count, peak_ratio=peak_ratio,
                distortion=distortion, floor=floor, snr=acq["snr"],
                doppler=acq["doppler"], code_phase=acq["code_phase"])
