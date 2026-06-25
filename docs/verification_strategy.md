# Verification Strategy

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

## Why HLS C-simulation is not enough

C-simulation proves the math, not the hardware. It runs the metric function on a
buffer and checks the numbers, but it cannot exercise valid/ready handshaking,
backpressure, packet framing, or latency, because none of those exist at the C
level. A design that is correct in C-sim routinely drops or duplicates data the
first time a downstream block deasserts `tready`. The most common real bug class
here is an AXI4-Stream master whose `tvalid` depends combinationally on `tready`,
or whose `tdata` is not held stable while `tvalid && !tready`. C-sim is blind to
all of it.

## Why XSim cycle simulation is required

XSim runs the actual RTL cycle by cycle, so it is where the streaming claims are
proven. This project drives the full pipeline under three flow-control regimes —
no stalls, seeded random stalls, and seeded burst backpressure — and asserts that
the captured metrics are identical across all three. They are: backpressure
changes timing, never results. That equivalence is the property a functional demo
can never show, and it is the headline evidence this repository exists to produce.

## AXI backpressure risks and the VALID/READY rules

Enforced everywhere in the RTL and checked by `axis_protocol_checker.sv` (SVA
guarded by `SIM_ASSERT`):

- `m_axis_tvalid` must not depend combinationally on `m_axis_tready`.
- `tdata` and `tlast` stay stable while `tvalid && !tready`.
- `tvalid`, once asserted, is held until the handshake completes.
- reset clears `tvalid`.

The skid buffer is a depth-2 register FIFO whose `tready` and `tvalid` come only
from the registered occupancy count, so it satisfies these rules by construction
and sustains full throughput. Its unit test (`tb_axis_skid_buffer.sv`) pushes 2000
beats through random source throttling and random sink backpressure and confirms
every beat emerges exactly once, in order, with stable data.

## Single source of truth (avoid three-way metric drift)

There is exactly one golden definition of every metric: `hls/src/gnss_metric_ref.cpp`.

- The Python generator (`gen_gnss_vectors.py`) produces inputs, metadata, and
  loose expected ranges plus exact intended alert flags. It does not define exact
  metric values.
- The HLS kernel output is checked TIGHT against the C reference (a small
  fixed-point tolerance; in practice the integer math matches exactly).
- The XSim output is checked LOOSE against expected ranges plus exact alert flags.
- If the three ever disagree, the C reference wins and the others are corrected.

## The tapped_stream.txt consistency mechanism

The standalone HLS C testbench needs the tapped stream, but the XSim flow
regenerates it in RTL from raw I/Q. To keep both paths consistent, the Python
generator also writes `vectors/<scenario>/tapped_stream.txt` using a bit-exact
port of the golden mix and PRN front-end. The golden simulator (`gnss_ref_sim`)
re-derives the tapped stream from `input_iq.txt` and cross-checks it against that
file, failing non-zero on any mismatch — so the Python front-end and the C golden
front-end are proven identical before any metric is compared. The HLS C-sim reads
`tapped_stream.txt`; the XSim flow reads `input_iq.txt` and rebuilds the tapped
stream in hardware.

A documented, deliberate difference exists at exactly two of the 1024 beats per
window: the golden model uses a window-local wrap for the early/late chip taps
(`early[N-1]=c[0]`, `late[0]=c[N-1]`), while the streaming RTL uses edge-fill at
those boundaries because a causal stream cannot see across the window edge. XSim
is checked loose for exactly this reason, and the thresholds carry wide margins, so
the boundary difference cannot flip an alert flag. In practice the measured XSim
metrics matched the golden bit-for-bit across all eight scenarios.

## Fixed-point tolerance

The HLS kernel and the C reference use identical integer arithmetic with the
Section 5 widths, so the tight check passes at zero difference; the testbench still
allows a small slack to absorb any width or rounding edge.

## Scenario coverage

Eight deterministic scenarios (seed `0xC0FFEE`): clean, wideband_jam, tone_jam,
delayed_spoof, doppler_shift, cn0_drop, mixed_attack, and a dedicated backpressure
scenario. Each asserts an exact alert-flag set; clean and backpressure assert no
attack flags. The XSim test matrix runs each scenario under an assigned stall mode
(none, random, or burst) and the unit testbenches cover the skid buffer, the NCO
mixer phase determinism, and the PRN handshake and restart determinism.

## Failure modes this catches

- A metric engine that wraps an accumulator (sized with margin, would show as a
  scenario whose score collapses).
- An AXIS master that drops or duplicates data under backpressure (would show as a
  metric mismatch between the stalled and unstalled runs, or a scoreboard error).
- Front-end drift between Python and the golden model (fails the tapped-stream
  cross-check before any metric is even compared).
- A malformed window (wrong sample count) — flagged in `alert_flags` bit 6 and
  `packet_status`, and asserted by the in-sim scoreboard.

## Verified results on this machine

Reported honestly from real runs (Vivado 2025.2 XSim and Vitis HLS 2025.2):

- `make selfcheck`: 8/8 scenarios pass; front-end cross-check bit-exact.
- XSim: 8/8 pass; metrics bit-exact versus golden; identical under random and
  burst backpressure; zero protocol-assertion failures; measured latency ranged
  from 1021 cycles (no stalls) to 2038 cycles (burst backpressure).
- Vitis HLS C synthesis (`vitis-run --mode hls`): C simulation passed with 0
  errors over all eight scenarios; the accumulation loop achieves II = 1; the
  5.00 ns clock target is met at an estimated 3.625 ns; utilization is DSP 4, FF
  1735, LUT 4026, BRAM 0. Verbatim tool output is in `docs/synthesis_report.md`.
- Unit testbenches: skid buffer, NCO mixer, and PRN generator all pass.

Post-implementation timing closure and on-board bring-up are deferred phases
(README roadmap); no post-place-and-route numbers are claimed.
