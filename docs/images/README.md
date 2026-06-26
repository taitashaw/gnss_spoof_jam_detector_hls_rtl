# Waveform and chart artifacts

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

Every image here is a real export from the **current** DBZP ddMap + own-FFT + SQM
detector — block design, AXIS waveform, and detection charts. No mock-ups, and no
legacy metric-engine images remain.

## Block design

- `gnss_block_design.png` / `.svg` — the Vivado IP-Integrator block design built
  around the **current own-FFT kernel** (`xilinx.com:hls:ddmap_sqm_hls:1.0`):
  Zynq UltraScale+ PS → AXI DMA (MM2S) → kernel `iq_in`, with the kernel's
  `s_axi_ctrl` (results: peak_power, code_phase, distortion, early/late power) and
  the DMA control on the PS `M_AXI_HPM0` via SmartConnects. Built and validated
  (zero critical warnings) by `vivado/run_bd_ownfft.tcl`, exported headless with
  `write_bd_layout` (SVG/PDF) under Xvfb, the PDF rasterized to PNG. See
  `docs/images/BLOCK_DESIGN.md`.

## AXIS waveform

- `waveform_ddmap_axis.png` — the current kernel's `iq_in` AXI4-Stream handshake from
  a **real XSim C/RTL co-simulation** (`cosim_design` on `ddmap_sqm_hls`, which now
  runs because the FFT is our own — no vendor C-model). Rendered by
  `scripts/render_ddmap_wave.py` from the cosim VCD. It shows the kernel holding
  `iq_in_TREADY` low while it computes the C/A generation and the code FFT, then
  asserting `TREADY` to read one 2048-beat block (TVALID high, real TDATA streaming,
  `TLAST` at the end) — genuine kernel-side backpressure. Every transition is a real
  VCD transition. Regenerate: run `cosim_design -trace_level all` on the kernel, dump
  the `iq_in_*` signals to a VCD over a ~90 us window, then run the render script.

## Detection charts

- `ddmap_peaks.png` — clean-vs-spoofed ddMap peak (strongest PRN) from a real-C/A
  DBZP acquisition on TEXBAT (`docs/single_pass_detection.md`).
- `benchmark_dbzp_vs_pcs.png` — measured DBZP-vs-PCS benchmark from
  `scripts/benchmark.py` (`docs/comparison_baseline_vs_ddmap.md`).
