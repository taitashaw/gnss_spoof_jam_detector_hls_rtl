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
| BRAM_18K | 52 / 624 (8%) |
| DSP | 86 / 1728 (5%) |
| FF | 7650 / 460800 (2%) |
| LUT | 10416 / 230400 (5%) |
| URAM | 0 |
| Timing target / estimated | 5.00 ns / **6.825 ns** (146.51 MHz) |

**Fit:** comfortably fits the ZCU104 (≤8% of any resource). One shared `fft_fixed`
instance is reused for the code FFT, per-block FFT, and IFFT (not inlined 9×).

**Timing (honest negative):** the design does **NOT** meet the 5 ns (200 MHz) target
— the csynth-estimated critical path is 6.825 ns (≈146 MHz), set by the fixed-point
radix-2 butterfly's complex multiply-add. It is implementable at ≈146 MHz; closing
5 ns would need a deeper-pipelined butterfly (ping-pong stage buffers / registered
DSP cascade), which is future work. Reported as measured, not met.

## Superseded — the old `hls_fft.h` (vendor-FFT) approach

The earlier kernel used the Xilinx FFT IP. Those numbers
(`docs/synth/ddmap_kernel_csynth.rpt`: **BRAM 46, DSP 54, FF 16095, LUT 15525,
~274 MHz**) are **retired** — they describe the vendor-FFT design, which **could not
be simulated** (csim/cosim both blocked by the FFT C-model `SIGFPE`). They do NOT
describe the current detector. The current, simulatable design is the own-FFT build
above. Trade between the two: the vendor IP closes timing faster (~274 vs ~146 MHz)
and uses fewer DSPs, but cannot be C-simulated on this install; our FFT is slower and
uses more DSPs but is fully verifiable (numpy-checked FFT + passing detector csim).
