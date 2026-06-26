# ddMap / SQM detector kernel — real csynth (separate from the old metric kernel)

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

This is the **DBZP ddMap + early/late SQM detector** kernel
(`hls/src/ddmap_sqm_hls.cpp`), the real detection core — NOT the older streaming
metric-engine kernel. Numbers below are verbatim from
`docs/synth/ddmap_kernel_csynth.rpt` (Vitis HLS 2025.2,
`vitis-run --mode hls --tcl hls/vitis_hls/run_ddmap_hls.tcl`).

## Configuration (synthesizable)

`hls::fft` (Xilinx FFT IP), FFT_SIZE = 2048 (max_nfft = 11), 16-bit scaled,
2 samples/chip (NS = 2046), N_BLK = 4 coherent blocks. One shared FFT instance is
reused for the code FFT, the per-block FFT, and the IFFT. Generates the real GPS
C/A code (G1/G2) on chip; axis input + s_axilite control. The carrier wipeoff and
the PRN/Doppler search loop are the host's job (one ddMap cell per call).

## Real csynth result (xczu7ev-ffvc1156-2-e)

| Metric | Value |
|---|---|
| Timing target / estimated | 5.00 ns / 3.650 ns (~274 MHz), met |
| BRAM_18K | 46 / 624 (7%) |
| DSP | 54 / 1728 (3%) |
| FF | 16095 / 460800 (3%) |
| LUT | 15525 / 230400 (6%) |
| URAM | 0 |
| Latency (one ddMap cell) | ~80208–80306 cycles (~0.40 ms @ 5 ns) |
| FFT instance | 6281 cycles each, reused 9× (1 code + 4×2 block/IFFT) |

**It fits the ZCU104 comfortably** (≤7% of any resource) and meets timing at the
5 ns target. As predicted by the benchmark cost analysis, it is far heavier than the
old streaming metric kernel — DSP 4 → 54, BRAM 0 → 46, LUT 4026 → 15525 — because of
the FFT-correlation. The FFT IP dominates the BRAM/DSP, as expected.

This is N_BLK = 4 at 2 samples/chip with a 2048-pt FFT. Full GPS-scale acquisition
(longer coherent integration, more samples/chip) would scale the FFT size and the
block count up; the FFT IP cost grows with FFT length, and the latency with N_BLK.

## C-simulation status (honest)

`csim_design` did **not** pass: the Xilinx FFT bit-accurate C-model aborts with a
floating-point exception under the scaled-FFT configuration
(`hls_fft.h get_status` / the model's internal scaling), independent of the kernel's
own logic. The TCL catches this and proceeds to csynth, which is the resource gate.
The detector algorithm is validated separately by the Python golden
(`scripts/dbzp_acq.py` / `scripts/ddmap_hls_vectors.py`): at the matched 2-samples/
chip config the golden gives the correct-PRN peak at the injected phase, the
wrong-PRN peak ~47× lower, and ds7-spoofed distortion (0.80) above clean (0.33). No
fixed-point csim agreement number is claimed here; only the real csynth numbers are.
The FFT C-model FPE is the next item to resolve for a fixed-point-vs-golden csim.
