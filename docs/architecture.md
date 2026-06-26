# Architecture

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

The detector computes one **delay-Doppler-map (ddMap) cell** per call — one PRN, one
Doppler hypothesis, `N_BLK = 4` coherent 1 ms blocks — and reads the spoof/jam
signatures off it. The synthesizable core is `hls/src/ddmap_sqm_hls.cpp`; the FFT is
the own fixed-point `hls/src/fft_fixed.hpp`.

## Signal path

```
Pre-wiped, decimated I/Q  (host: carrier-Doppler wipeoff + decimate to 2.046 Msps)
        |
        v
AXI4-Stream in  (32-bit: I s16 [31:16], Q s16 [15:0]) -- N_BLK x 2048 samples / cell
        |
        v
+-----------------------------------------------------------------+
|  generate on-chip C/A code (G1/G2 Gold code, IS-GPS-200)        |
|        |                                                        |
|        v                                                        |
|   fft_fixed (forward) ----> code spectrum (conjugated)          |
|                                          |                      |
|   per 1 ms block:                        |                      |
|     fft_fixed (forward) --> block spec --x--> spectral product  |
|                                              |                  |
|                                   fft_fixed (inverse / IFFT)    |
|                                              |                  |
|                              coherent accumulate over N_BLK     |
|                                              |                  |
|                              |corr|^2 profile (the ddMap cell)  |
+-----------------------------------------------------------------+
        |
        v
  peak power | code phase | early/late SQM distortion  (s_axilite outputs)
        |
        v
  spoof = distortion > threshold ; jam = ddMap floor / energy elevation
```

The input is a 32-bit AXI4-Stream of signed complex samples — `I = tdata[31:16]`
(s16), `Q = tdata[15:0]` (s16). One cell consumes `N_BLK * FFT_N = 4 * 2048` samples
(four 1 ms C/A periods, zero-padded to 2048). The outputs are read over `s_axilite`:
`peak_power`, `code_phase`, `distortion_q16` (early/late distortion in Q16),
`early_power`, `late_power`.

## Stage ownership

1. **On-chip C/A code** (`gen_ca_upsampled`): a G1/G2 Gold-code generator (taps per
   IS-GPS-200) produces the length-1023 code for the requested PRN, upsampled to
   2 samples/chip (NS = 2046) and zero-padded to 2048. The G2 phase shift matches the
   numpy golden (`g2[(i - shift) mod 1023]`).
2. **Code spectrum**: one forward `fft_fixed` of the code, conjugated, reused for
   every block in the cell.
3. **Per-block correlation**: each pre-wiped 1 ms block is forward-FFT'd, multiplied
   by the conjugate code spectrum (with a 2^14 rescale to keep the triple-transform
   correlation in fixed-point precision), and inverse-FFT'd to a 1 ms correlation.
4. **Coherent accumulation**: the complex correlations are summed across `N_BLK`
   blocks (the DBZP coherent-gain step) into the ddMap cell.
5. **SQM read-out**: the `|corr|^2` profile gives the peak power and code phase
   (partial-max reduction), and the early/late samples at ±0.5 chip give the
   distortion `|E - L| / (E + L)` — the spoof statistic.

## The FFT (shared instance)

One `fft_fixed` instance is reused for the code FFT, the per-block FFT, and the IFFT
(9 calls per cell). It is a radix-2 decimation-in-time fixed-point FFT with a
compile-time twiddle ROM and ping-pong stage buffers; see `docs/fft_fixed_design.md`.
Forward vs inverse is a direction flag (conjugate twiddles); the /N normalisation
comes from the per-stage halving, and is harmless because the peak location and the
early/late distortion ratio are scale-invariant.

## HLS / RTL split

The whole detector cell — code generation, the three FFT passes, the spectral
product, coherent accumulation, and the SQM read-out — is the HLS kernel
(`ddmap_sqm_hls.cpp` + `fft_fixed.hpp`), synthesized at 488.76 MHz (single `ap_clk`).
The carrier-Doppler wipeoff and the outer PRN/Doppler search loop are the host's job
(one cell per kernel call). System integration (AXI DMA feeding the AXIS input,
s_axilite control from the PS) follows the standard Zynq UltraScale+ pattern; the PL
fabric is single-clock (see `docs/audit_latency_cdc.md`).

## Data contract summary

| Stream | Width | Contents |
|---|---|---|
| I/Q in (AXIS) | 32 | `I s16` [31:16], `Q s16` [15:0]; N_BLK x 2048 samples per cell |
| control / results (s_axilite) | — | in: `prn`; out: `peak_power`, `code_phase`, `distortion_q16`, `early_power`, `late_power` |

## Legacy streaming front-end (superseded)

The earlier streaming anomaly metric engine (RTL NCO mixer → PRN LFSR /
early-prompt-late tap → HLS metric engine → alert packer) is **not** part of this
detector. Its RTL is retained under `rtl/gnss/` and labeled legacy; see README §11.
The signal path above replaces it entirely.
