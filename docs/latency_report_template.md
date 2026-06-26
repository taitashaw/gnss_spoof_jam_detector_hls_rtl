# Latency Report Template

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

> **Legacy.** This template targets the superseded streaming metric engine's
> `axis_latency_counter` (README §11). The current ddMap/SQM detector's end-to-end
> latency is measured and audited in `docs/audit_latency_cdc.md` (271,504 cycles =
> 555.5 µs per cell @ 488.76 MHz, 7.2× real-time headroom).

This is a TEMPLATE. It is filled from real `axis_latency_counter` output captured
during an XSim run; it contains no invented numbers. The latency counter measures,
per window, the cycles from the first accepted input I/Q beat to the metrics output
beat, including any backpressure stalls. Populate the table from
`results/<scenario>/actual_metrics.txt` (the `latency_cycles` field) for the run
you are reporting, and record the clock period used so cycles can be converted to
time.

## Run metadata

| Field | Value |
|---|---|
| Tool / version | _fill in (e.g. Vivado 20xx.x XSim)_ |
| Target part | _fill in (default xczu7ev-ffvc1156-2-e)_ |
| Clock period | _fill in (the metric engine clock; HLS default 5 ns)_ |
| Window size | _fill in (default 1024)_ |
| Seed | _fill in (default 0xC0FFEE)_ |

## Per-scenario measured latency

| Scenario | Stall mode | latency_cycles | latency (= cycles x clock period) |
|---|---|---|---|
| clean | _ | _ | _ |
| wideband_jam | _ | _ | _ |
| tone_jam | _ | _ | _ |
| delayed_spoof | _ | _ | _ |
| doppler_shift | _ | _ | _ |
| cn0_drop | _ | _ | _ |
| mixed_attack | _ | _ | _ |
| backpressure | _ | _ | _ |

## Notes

- `latency_cycles` is a real measured count, not a model estimate. The software
  golden simulation reports a model estimate instead, clearly labeled; only XSim
  values belong in this table.
- Expect the no-stall scenarios to be close to the window length plus the fixed
  pipeline depth, and the random/burst scenarios to be larger by the number of
  stall cycles the backpressure injected. Record the stall mode alongside each
  figure so the numbers are comparable.
- Do not enter synthesis-derived timing (Fmax, slack) here unless it comes from a
  real Vitis HLS or Vivado run; this template is for measured simulation latency.
