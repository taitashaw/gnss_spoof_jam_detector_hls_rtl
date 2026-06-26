# ddMap / SQM detector kernel — own-FFT build (real csim + csynth)

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

The **DBZP ddMap + early/late SQM detector** kernel (`hls/src/ddmap_sqm_hls.cpp`),
the real detection core. It now uses our **own from-scratch fixed-point FFT**
(`hls/src/fft_fixed.hpp`, numpy-verified — see `docs/fft_fixed_design.md`) instead of
the Xilinx `hls_fft.h` IP. That switch **unblocked simulation**: the vendor FFT
C-model aborted csim with an integer-divide `SIGFPE`, so the detector could never be
simulated; with our FFT, csim runs and passes against the Python golden.

## C-simulation — REAL, unblocked, passes (`tb_ddmap_sqm_hls.cpp`)

`csim_design` (and plain g++) now run to completion. Verbatim:

```
clean_p5  corr_prn=5  kernel: peak=600  dist=0.3316  | golden: peak=600  dist=0.3305
wrong_p6  corr_prn=6  kernel: peak=1544 dist=0.5272  | golden: peak=330  dist=0.0213
ds7_p23   corr_prn=23 kernel: peak=1393 dist=0.9082  | golden: peak=1393 dist=0.7993
OK: wrong-PRN peak << correct-PRN peak (44.7x lower)
OK: ds7 distortion 0.908 > clean 0.332 (spoof signature)
DDMAP/SQM KERNEL CSIM PASS
```

- correct-PRN code phase **exact** (600 and 1393 match the golden),
- wrong-PRN peak **44.7×** lower (golden ≈47×),
- ds7-spoofed SQM distortion **> clean** (the spoof signature), distortion within
  fixed-point tolerance of the golden (0.33 vs 0.33; 0.91 vs 0.80).

Building our own FFT also **exposed a real bug** the FPE-blocked vendor path had
hidden: the on-chip C/A G2 phase shift used `+shift` where the golden uses numpy
`roll(g2, shift)` = `-shift`, so the generated Gold code was wrong and nothing
correlated. The unblocked csim caught it; fixed in `gen_ca_upsampled`.

## C synthesis — real numbers (xczu7ev-ffvc1156-2-e), own FFT

Verbatim from `docs/synth/ddmap_ownfft_csynth.rpt`:

| Metric | Value |
|---|---|
| BRAM_18K | 58 / 624 (9%) |
| DSP | 14 / 1728 (1%) |
| FF | 7878 / 460800 (2%) |
| LUT | 9539 / 230400 (4%) |
| URAM | 0 |
| Timing target / estimated | 2.50 ns / **2.046 ns** (**488.76 MHz**), +0.45 ns slack |
| Latency | 271,504 cycles (~0.56 ms @ 2.046 ns); FFT butterfly II=2 |

**Timing — MET (target was 400 MHz / 2.5 ns).** Estimated 2.046 ns = **488.76 MHz**,
comfortably past 400 MHz with positive slack. Closed by retiming (no algorithm or
accuracy change), in order of impact:

1. **Conflict-free FFT memory (ping-pong):** each radix-2 stage reads one buffer and
   writes another (`fft_stage(s, src, dst)` with distinct array args), so the
   flattened butterfly has no in-place read/write recurrence -> it pipelines (146 ->
   354 MHz). The two same-array writes still force butterfly II=2 (the latency cost).
2. **DSP-registered butterfly:** the four real multiplies are bound to pipelined
   DSP48E2 (`BIND_OP latency=3` -> A/B, M, P registers).
3. **Multipliers -> shifts:** the input `/65536`, the spectral-product `*2^14` gain,
   and the power output `*2^20` scaling are powers of two, rewritten as left shifts.
   This removed the wide (80-97 bit) multipliers that capped the clock and **cut DSP
   86 -> 14** (354 -> 489 MHz). It also fixed an input-saturation quirk, so detector
   distortion now matches the golden almost exactly (0.3305 vs 0.3305).
4. **Partial-max reduction:** the SQM peak search keeps 4 parallel maxima (lane
   i%4) so the max-update recurrence has distance 4, not 1.

**Accuracy preserved (the hard rule):** the numpy FFT gate still PASSES unchanged
(tone 96.5 dB/15.7 ENOB, C/A 85.6 dB/13.9 ENOB, worst impulse7 8.8 ENOB), and the
detector csim still PASSES (peak phases 600/1393 exact, ds7 distortion 0.799 > clean
0.330, wrong-PRN 47.5x lower). No accuracy was traded for timing.

**Cost of the speed-up:** latency 80,208 -> 271,504 cycles (~3.4x), from the
ping-pong LOAD/OUT copies per FFT call and the II=2 butterfly; FF ~flat (7650 ->
7878); BRAM 52 -> 58 (ping-pong buffers); LUT and **DSP both dropped** (shifts
replaced multipliers). Throughput is lower per the latency, but the **clock target
(400 MHz) is met** and the design still fits the ZCU104 easily (≤9%).

## Superseded — the old `hls_fft.h` (vendor-FFT) approach

The earlier kernel used the Xilinx FFT IP. Those numbers
(`docs/synth/ddmap_kernel_csynth.rpt`: **BRAM 46, DSP 54, FF 16095, LUT 15525,
~274 MHz**) are **retired** — they describe the vendor-FFT design, which **could not
be simulated** (csim/cosim both blocked by the FFT C-model `SIGFPE`). They do NOT
describe the current detector. The current, simulatable design is the own-FFT build
above — which is now both **fully verifiable** (numpy-checked FFT + passing detector
csim) **and faster** (489 vs 274 MHz) at far fewer DSPs (14 vs 54).
