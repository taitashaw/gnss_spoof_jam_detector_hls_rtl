# Known Limitations

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

This is deliberately honest scope. The design is simulation-complete; the items
here are real boundaries, not defects.

- Not a certified GPS receiver. It is a streaming anomaly-detection accelerator
  that computes GNSS-relevant metrics. It does not acquire, track, or produce a
  position, velocity, or time solution.

- The PRN generator is PRN-like, not a full GPS C/A code. It is a 10-bit Fibonacci
  LFSR producing a deterministic, reproducible chip sequence suitable for the
  anomaly demonstration. A certified design would implement the full Gold-code pair
  with the correct G1/G2 polynomials and per-satellite phase taps.

- C/N0 is a proxy, not a calibrated carrier-to-noise-density ratio in dB-Hz. It is
  a division-free log-domain ratio of the despread prompt correlation to the
  noise-floor estimate, with the correct monotonicity but no absolute calibration.

- Doppler is a simplified anomaly proxy, not a frequency estimate. It is an
  FFT-free instantaneous-frequency energy measure (the summed magnitude of the
  cross-product between consecutive mixed samples). It rises with residual carrier
  rate and with broadband interference; it does not report a Doppler value in Hz.

- The early/prompt/late spacing is one sample for the demonstration, and the
  streaming RTL uses edge-fill at the two window-boundary chip taps where the golden
  model uses a window-local wrap. This is documented and bounded; it cannot change
  an alert flag.

- No live RF validation yet. All results come from deterministic synthetic I/Q.
  The path to real capture is described in `hardware_bringup_notes.md` and is gated
  on board documentation.

- No fabricated resource or timing numbers. Vitis HLS C synthesis was run (Vitis
  HLS 2025.2 via `vitis-run --mode hls`); the resulting utilization (DSP 4, FF
  1735, LUT 4026, BRAM 0), the 5.00 ns clock target met at an estimated 3.625 ns,
  and the II = 1 accumulation loop are reported verbatim from the tool in
  `docs/synthesis_report.md` with the raw reports under `docs/synth/`. These are
  post-C-synthesis estimates; final post-implementation utilization and timing
  closure require Vivado place-and-route, which is a deferred phase. The
  cycle-accurate per-window latency is measured directly by `axis_latency_counter`
  in XSim, and `latency_report_template.md` is a structured template for those
  measured runs.

- Not yet implemented on hardware. There is no Vivado IP Integrator block design,
  no bitstream, and no on-board bring-up yet. These are deferred phases listed in
  the README roadmap, gated on the NT1065 FMC board documentation.

- The thresholds and score weights are tuned on the eight reference scenarios to
  separate them cleanly. They are a defensible default starting point, not
  field-calibrated detection thresholds; on real signals they would be retuned
  against labeled captures.
