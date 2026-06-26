# Waveform and chart artifacts

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

All images here are produced from real runs, not mock-ups. They are split into
**current detector** (DBZP ddMap + own-FFT + SQM) and **legacy** (the superseded
streaming metric engine — see README section 11). No legacy image is referenced as
the current design.

## Current detector

- `ddmap_peaks.png` — clean-vs-spoofed ddMap peak (strongest PRN) from a real-C/A
  DBZP acquisition on TEXBAT (`docs/single_pass_detection.md`).
- `benchmark_dbzp_vs_pcs.png` — measured DBZP-vs-PCS benchmark (sensitivity, PRN
  accuracy, ds7 spoof) from `scripts/benchmark.py`
  (`docs/comparison_baseline_vs_ddmap.md`).

### Pending current-kernel hardware renders

The own-FFT ddMap kernel (`hls/src/ddmap_sqm_hls.cpp`) is verified by csim + csynth
(`hls/vitis_hls/run_ddmap_ownfft.tcl`, 488.76 MHz) but has **not** yet been packaged
into a Vivado IP-Integrator block design, so there is **no current-kernel
block-design image or AXIS waveform yet** — and none is faked. When the own-FFT kernel
is integrated into a BD, regenerate the block-design diagram and an AXIS-handshake
waveform from that kernel (headless under Xvfb, the same flow the legacy BD used).
The latency + CDC properties of the integrated PL fabric are already audited in
`docs/audit_latency_cdc.md` (single-clock, all paths safely timed).

## Legacy streaming front-end (superseded — documents the old metric engine only)

These render the legacy NCO/PRN/metric-engine subsystem and are referenced only by
the legacy docs (`docs/system_integration.md`, `docs/latency_report_template.md`):

- `gnss_block_design.png` / `.svg` — the legacy metric-kernel Vivado block design.
- `waveform_mixed_attack.png` + `mixed_attack.vcd` / `.wcfg` — a real XSim VCD render
  of the legacy `tb_gnss_top` under burst backpressure (rendered by
  `scripts/render_wave.py`; every transition is a real VCD transition).
- `scores_by_scenario.png`, `metrics_by_scenario.png` — the legacy 8-scenario metric/
  score charts (`make plots`).

They are retained as evidence of the legacy subsystem's streaming/backpressure
discipline; they do not describe the current ddMap/SQM detector.
