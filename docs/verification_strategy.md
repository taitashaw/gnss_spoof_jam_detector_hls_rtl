# Verification Strategy

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

The detector is verified bottom-up, each layer gating the next. Every layer produced
a real, committed result; none is assumed.

## 1. numpy FFT accuracy gate (must pass before the FFT is used)

The own fixed-point FFT (`hls/src/fft_fixed.hpp`) is verified as a standalone unit
against `numpy.fft` before it is wired into the detector (`hls/tb/tb_fft_fixed.cpp`,
`scripts/gen_fft_vectors.py`). The bound is **SNR ≥ 50 dB** on every test vector;
measured: impulse exact, tone 96.5 dB / 15.7 ENOB, random 83.9 dB / 13.6 ENOB, C/A
block 85.6 dB / 13.9 ENOB, worst impulse7 54.7 dB / 8.8 ENOB, ifft(fft(x)) round-trip
68 dB. This runs in plain csim / g++ with no vendor model, so it actually executes.
An accuracy regression at any later step is a failure, not an accepted cost.

## 2. Detector C-simulation vs the Python golden

`hls/tb/tb_ddmap_sqm_hls.cpp` runs the synthesizable kernel against the Python golden
(`scripts/ddmap_hls_vectors.py`) at the matched 2-samples/chip config: correct-PRN
code phase exact (600, 1393), wrong-PRN peak 47.5× lower, ds7-spoofed SQM distortion
0.799 > clean 0.330, and distortion within fixed-point tolerance of the golden
(0.3305 vs 0.3305). Because the FFT is our own (no vendor C-model), this csim is
unblocked — and it is what caught the on-chip C/A G2 shift-sign bug that an
FPE-blocked vendor path had hidden.

## 3. The single golden source (no drift)

There is one golden definition of the detection math: the Python acquisition
(`scripts/dbzp_acq.py`) and Gold-code generator (`scripts/gps_ca.py`). The kernel
mirrors it; the test-bench compares against the reference it produces. The FFT golden
is `numpy.fft`. No metric is defined in more than one place.

## 4. Cycle-level RTL simulation (XSim) for the streaming path

XSim runs the RTL cycle by cycle to prove the streaming/flow-control claims that
C-simulation cannot: valid/ready handshaking, backpressure, and framing. The repo's
XSim flow drives the pipeline under no-stall, random-stall, and burst-backpressure
regimes and asserts the captured results are identical across all three —
backpressure changes timing, never results. (This discipline was built on the legacy
streaming front-end; the detector kernel itself is single-clock and exposes only
`ap_clk`.)

## 5. Real-data validation (TEXBAT)

The detector is validated on real recorded spoofing (`docs/texbat_validation.md`,
`docs/single_pass_detection.md`): ds7 (matched-power SCER, the hardest class) is
detected at 100% with 0% clean-slice false-alarm by the early/late SQM distortion
(threshold ≥ 0.50); ds2 (overpowered time-push) is honestly not separated by the
distortion metric and is caught by absolute power / ddMap energy. The ~43 GB `.bin`
files are never committed — path + SHA256 + citation only. Negative results are
reported.

## 6. Latency + CDC audit

`docs/audit_latency_cdc.md`: end-to-end latency (271,504 cycles = 555.5 µs per cell @
488.76 MHz, 7.2× real-time headroom) and Vivado `report_cdc` on the routed design
("All paths are Safely Timed", single PL clock). The audit verdict is that the HLS
design meets the real-time monitoring deadline with no CDC findings.

## Why each layer is necessary

C-simulation proves the math, not the hardware; XSim proves the streaming behavior;
TEXBAT proves the detection on real attacks (including a null); the audit proves the
timing/real-time/CDC properties. A result is reported as measured at each layer —
including honest negatives — never assumed from the layer below.
