# Waveform and chart artifacts

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

Every image here is a real export from the **current** DBZP ddMap + own-FFT + SQM
detector — block design, AXIS waveform, and detection charts. No mock-ups, and no
legacy metric-engine images remain.

## Block design

- `gnss_block_design.png` — a **screenshot of the actual Vivado IP Integrator
  canvas** (the real tool window) showing the block design built around the
  **current own-FFT kernel** (`xilinx.com:hls:ddmap_sqm_hls:1.0`): Zynq UltraScale+ PS
  → AXI DMA (MM2S) → kernel `iq_in`, with the kernel's `s_axi_ctrl` (results:
  peak_power, code_phase, distortion, early/late power) and the DMA control on the PS
  `M_AXI_HPM0` via the two SmartConnects, plus the processor reset. Built and validated
  (zero critical warnings) by `vivado/run_bd_ownfft.tcl`; captured headless under Xvfb
  (`vivado -mode gui` + `regenerate_bd_layout`, `import -window root`).
- `gnss_block_design.svg` — the same block design exported as vector by Vivado's
  `write_bd_layout`. See `docs/images/BLOCK_DESIGN.md`.

## AXIS waveform

- `waveform_ddmap_axis.png` — a **screenshot of the actual Vivado XSim waveform
  viewer** (signal pane + value column + timeline), from a real C/RTL co-simulation
  (`cosim_design` on `ddmap_sqm_hls`, which now runs because the FFT is our own — no
  vendor C-model). It shows the kernel's `iq_in` AXI4-Stream handshake at the
  backpressure interval: `iq_in_TREADY` held **low** (~74.8–75.0 us) while the kernel
  computes the C/A generation and the code FFT, then **rising to high** at ~75 us to
  read the block, with `iq_in_TDATA` (`1fc401b9`…) beginning to stream at that exact
  edge, `iq_in_TVALID`/`ap_start` high and `iq_in_TLAST`/`ap_done` low. This is the
  XSim tool window, not a re-plot.

  Regenerate: `cosim_design` the kernel, then `xsim ddmap_sqm_hls -gui` on the cosim
  snapshot, `add_wave` the `iq_in_*` / `ap_*` signals, `run 76500 ns` (so XSim's
  auto-zoom lands on the TREADY transition), and screenshot the wave window (headless:
  Xvfb + `import -window root`).

## Detection charts

- `ddmap_peaks.png` — clean-vs-spoofed ddMap peak (strongest PRN) from a real-C/A
  DBZP acquisition on TEXBAT (`docs/single_pass_detection.md`).
- `benchmark_dbzp_vs_pcs.png` — measured DBZP-vs-PCS benchmark from
  `scripts/benchmark.py` (`docs/comparison_baseline_vs_ddmap.md`).
