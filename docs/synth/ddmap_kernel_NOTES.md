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

`csim_design` did **not** pass. The Xilinx FFT bit-accurate C-model
(`hls_fft.h`) aborts with an integer-divide `SIGFPE` ("child killed: floating-point
exception") within ~2 s, **before any testbench output prints** — i.e. inside the
FFT model's first invocation, not in the kernel's own logic (the kernel has no
runtime-zero integer division). Workarounds attempted, in order:

1. **Scaled mode** (the config that synthesizes): FPE.
2. **Block-floating-point mode** (`scaling_opt = block_floating_point`,
   `config_width = 8`): the FFT model still FPEs, AND it forces the classic
   streaming-config API, which **fails synthesis** here — that API requires the FFT
   in/out arrays to be consumed as sequential streams, incompatible with this
   kernel's random-access correlation arrays (`Failed to implement stream interface
   on ... code_fd/blk_fd/corr`). So BFP cannot be used without restructuring the
   detector algorithm (which the task forbids).
3. **Disable FP-exception trapping** in the TB (`fedisableexcept(FE_ALL_EXCEPT)`):
   no effect — confirming an integer-divide SIGFPE (a hardware trap), not a
   trappable FP op.

This is a **documented `hls_fft.h` bit-accurate C-model limitation** under this
configuration on this install. It does NOT affect synthesis: csynth generates the
real FFT RTL and the resource/timing numbers above.

## Co-simulation status (honest)

`cosim_design` also **could not run**, blocked by the same C-model FPE.
cosim_design first runs the C testbench to generate the input/golden test vectors,
and that step calls the kernel's C model (FFT C-model) -> SIGFPE ->
`ERROR: [COSIM 212-320] C TB testing failed, stop generating test vectors` ->
`C/RTL co-simulation finished: FAIL`. So the C testbench passing is a hard
prerequisite for cosim that could not be fixed without either the vendor model
working or restructuring the kernel; cosim verification of the synthesized RTL is
therefore not available here. Stated plainly: **cosim did not run.**

## Verification that IS available

The detector algorithm is validated by the Python golden
(`scripts/dbzp_acq.py` / `scripts/ddmap_hls_vectors.py`), which the kernel mirrors
at the matched 2-samples/chip config: correct-PRN peak at the injected phase,
wrong-PRN peak ~47x lower, ds7-spoofed distortion 0.80 > clean 0.33. The kernel's
synthesizability and resource/timing cost are proven by the real csynth above. No
fixed-point csim/cosim agreement number is claimed, because none was produced.
