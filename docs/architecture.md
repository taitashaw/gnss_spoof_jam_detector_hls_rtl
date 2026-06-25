# Architecture

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

## Signal path

```
Synthetic or ADC I/Q Stream
        |
        v
AXI4-Stream Skid Buffer
        |
        v
RTL NCO Mixer
        |
        v
RTL PRN / Early-Prompt-Late Generator
        |
        v
HLS GNSS Metric Engine
        |
        v
RTL Alert Packer + Latency Counter
        |
        v
AXI4-Stream Metrics Output
```

The input is a 32-bit AXI4-Stream of signed complex samples — `I = tdata[31:16]`
(s16), `Q = tdata[15:0]` (s16), with `tlast` marking the final sample of each
window (default window = 1024 complex samples). The output is one packed metrics
beat per window.

## Stage ownership (no duplicated logic)

The HLS/RTL boundary is resolved by a strict data contract so no stage redoes
another stage's work.

1. `nco_mixer.sv` consumes raw I/Q and produces NCO-mixed I/Q (s16). The phase
   accumulator advances only on an accepted handshake and resets at each window
   boundary, so the per-window phase is reproducible.
2. `prn_lfsr_gen.sv` produces early/prompt/late chip signs from a 10-bit Fibonacci
   LFSR, advancing only on accepted handshakes and reloading its seed at each
   window boundary.
3. `early_prompt_late_tap.sv` aligns the mixed stream with the chip taps and emits
   the tapped stream: mixed I/Q, the three chip signs, the sample index, and
   `tlast`.
4. The metric engine consumes the tapped stream and emits one metrics packet per
   window. It does not re-mix or re-generate the PRN.

## Windowing

All accumulators are per-window. The metric engine sums power, sub-block power,
the three correlation taps, and the Doppler cross-product energy across exactly
`WINDOW_SIZE` tapped beats, then computes the noise estimate, the C/N0 proxy, the
symmetry error, the derived anomaly signals, and the two saturated scores at the
`tlast` beat, resetting for the next window. `power_prev` and `noise_prev` are
passed in (from the register bank) and the current power/noise are returned to be
latched for the next window — there is no hidden persistent state for the
power-jump metric.

## Metric computation

Per window, on the tapped stream (full definitions in `gnss_metric_ref.cpp`):

- power_estimate — sum of `I^2 + Q^2`.
- noise_estimate — smoothed minimum of eight sub-block mean powers (a robust
  low-percentile noise-floor proxy), with a one-pole IIR carry.
- cn0_proxy — a division-free log-domain ratio of the despread prompt-correlation
  magnitude to the noise estimate (higher is healthier).
- corr_prompt / corr_early / corr_late — `|I_corr| + |Q_corr|` per E/P/L tap.
- symmetry_error — `|corr_early - corr_late|`.
- doppler_energy — FFT-free instantaneous-frequency energy, the summed magnitude
  of `imag(x[n] * conj(x[n-1]))`.
- power_jump_metric — `|power_estimate - power_estimate_prev|`.
- spoof_score — saturated weighted sum of symmetry, Doppler, C/N0 abnormality, and
  a delayed-replica shoulder signal.
- jam_score — saturated weighted sum of absolute power, low C/N0, correlation
  collapse, and the elevated noise floor.

## Alert scoring

`gnss_alert_packer.sv` compares the metrics against the run-time thresholds in the
register bank and packs `alert_flags` (bit 0 high power jam, bit 1 C/N0 drop, bit 2
correlation asymmetry, bit 3 Doppler energy anomaly, bit 4 spoof score high, bit 5
jam score high, bit 6 malformed packet, bit 7 reserved), folds in the measured
`latency_cycles`, sets `packet_status`, and emits the final packet.

## HLS / RTL split

The metric engine is the HLS block — it is accumulation and fixed-point scoring,
which is where HLS productivity pays off. Everything that must be cycle-exact and
deterministic — flow control, the NCO phase accumulator, the LFSR, stream
alignment, threshold packing, and latency measurement — is RTL. In simulation the
metric engine is a behavioral SystemVerilog stand-in with the identical port list
of the exported HLS IP, so `make xsim` runs without having first run Vitis HLS.

## Future ADC / FMC integration

The synthetic I/Q source is the only thing that changes for a real bench. A real
GNSS RF front-end (for example NT1065 over FMC) delivers s16 I/Q at the same AXI4-
Stream contract; it replaces the synthetic vectors with no change to the mixer,
PRN, metric engine, or alert packer. The register bank's `nco_phase_inc` and
`prn_seed` are then set to the real intermediate frequency and the target code.
See `hardware_bringup_notes.md`.

## Data contract summary

| Stream | Width | Contents |
|---|---|---|
| I/Q in | 32 | `I s16` [31:16], `Q s16` [15:0], `tlast` per window |
| tapped | 46 | mixed I/Q s16, E/P/L chip signs, sample index, `tlast` |
| metrics out | 512 | full packet, fields per `gnss_top_pkg.sv` offsets, `tlast`=1 |
