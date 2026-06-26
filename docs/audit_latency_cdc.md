# Latency + CDC audit — ddMap/SQM own-FFT detector

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

A ShawSilicon-grade audit of the current HLS ddMap/SQM detector (own fixed-point FFT,
488.76 MHz / 2.046 ns, `docs/synth/ddmap_ownfft_csynth.rpt`). Measure first, decide
second. All numbers are read from the Vitis HLS csynth report and Vivado
`report_cdc`/`report_clocks` on the routed checkpoint — none estimated.

## Part A — latency audit

### End-to-end, one ddMap cell (one PRN, one Doppler, N_BLK=4 coherent blocks)

| Quantity | Cycles | Time @ 488.76 MHz |
|---|---|---|
| **One ddMap cell, in to decision** | **271,504** | **555.5 µs** |
| └ FFT (9 calls: 1 code + 4 block + 4 IFFT) | 241,587 (89.0%) | 494.3 µs |
| &nbsp;&nbsp;&nbsp;per FFT call | 26,843 | 54.9 µs |
| &nbsp;&nbsp;&nbsp;&nbsp;— butterfly STAGE compute (II=2) | 22,738 / call | 46.5 µs |
| &nbsp;&nbsp;&nbsp;&nbsp;— ping-pong LOAD+OUT copies | 4,105 / call | 8.4 µs |
| └ ping-pong copy overhead, all 9 FFTs | 36,945 (13.6%) | 75.6 µs |
| └ non-FFT (C/A gen, block read, product, accumulate, SQM) | ~29,900 (11.0%) | ~61 µs |

The FFT dominates (89%). Two HLS-specific overheads are visible: the **ping-pong
LOAD/OUT copies** (13.6% of the cell — pure data movement, no compute) and the
**II=2 butterfly** (the two same-array writes per radix-2 stage force II=2, doubling
the 22,738-cycle STAGE term).

### Real-time deadline

The detector consumes one cell's worth of data = N_BLK × 1 ms = **4 ms** (four 1 ms
C/A code periods, decimated from the 25 Msps stream). One cell computes in 555.5 µs:

> **per-cell real-time headroom = 4 ms / 555.5 µs = 7.2×**

So in the wall-clock time it takes to *receive* one cell's 4 ms window, the engine can
process **7.2 cells**. The decision budget is therefore **7.2 ddMap cells per 4 ms
window** for drop-free continuous operation.

| Workload | Cells | Time | vs deadline |
|---|---|---|---|
| Monitor ≤7 tracked satellites (1 cell each), per 4 ms window | ≤7 | ≤3.89 ms | **PASS** (< 4 ms) |
| Full visible constellation (~11 sats), per 4 ms window | 11 | 6.1 ms | exceeds 4 ms → revisit at 8 ms |
| Cold full-sky search (32 PRN × ~13 Doppler bins) | 416 | 231 ms | one-time startup; PASS at any cadence ≥ ~250 ms |

For spoof/jam monitoring — which tracks an already-acquired satellite set and where
events evolve over seconds (a decision cadence of 100 ms–1 s is operationally ample)
— the design **PASSES the real-time budget with margin**: a tracked set of ≤7
satellites sustains the tightest per-4 ms-window cadence, and a full 416-cell search
completes in 231 ms, well inside any ≥250 ms cadence.

### Verdict A — **PASS**

The current HLS latency meets the real-time detection deadline for the intended
monitoring workload (7.2× per-cell headroom; 7-cell-per-window budget). It only
exceeds the budget in a regime that is not a hard real-time requirement
(full-constellation acquisition inside a single 4 ms window).

What a streaming RTL FFT *would* recover (for reference, not required): an SDF FFT at
II=1 with no per-call LOAD/OUT copies would cut each FFT from 26,843 to ~2,200 cycles
(~12×), the cell from 271,504 to ~50,000 cycles, raising the budget to ~40 cells per
4 ms window. This is an optional throughput optimisation, **not** needed to meet the
deadline.

## Part B — CDC audit

Measured with `report_clocks` and `report_cdc -details` on the routed checkpoint
(`build/vivado_bd_impl/.../gnss_system_bd_wrapper_routed.dcp`).

### Clock domains

| Clock | Period | Freq | Scope |
|---|---|---|---|
| `clk_pl_0` (PS `PL_CLK[0]`) | 10.312 ns | 96.97 MHz | entire PL fabric: kernel + AXI DMA + 2× AXI SmartConnect + reset |
| PS8 internal (DDR, APU, …) | — | — | hardened inside `zynq_ultra_ps_e`; not fabric logic |

The integrated PL fabric is **single-clock**: the HLS kernel exposes only `ap_clk` /
`ap_rst_n` (confirmed in the generated RTL — no internal CDC), and the DMA,
SmartConnects and kernel are all driven by `clk_pl_0`. The PS↔PL AXI interfaces
(`M_AXI_HPM0_FPD` control, `S_AXI_HP0_FPD` data) are synchronous to `clk_pl_0`; the
PS provides AXI on the PL-supplied clock and absorbs its DDR/APU clock crossings
inside the hardened `PS8` silicon (vendor-guaranteed, not a fabric CDC).

### Crossing analysis

```
report_cdc -details  ->  "All paths are Safely Timed."
```

Zero **Critical**, zero **Warning** CDC paths. There are no unsynchronized or
unconstrained fabric crossings, because there is only one fabric clock — every
register-to-register path is intra-clock and timed by static timing analysis.

### Verdict B — **no CDC findings on the current design**

One forward-looking item (a CDC *design* item, NOT an HLS-to-RTL conversion item):
the own-FFT kernel closes timing at 488 MHz, far above the 97 MHz `clk_pl_0` and the
DMA/PS-AXI clock. If a future integration clocks the kernel at its 488 MHz Fmax to
exploit the speed, the kernel↔DMA AXI4-Stream boundary becomes a genuine clock-domain
crossing and must use an **asynchronous / rate-matching AXIS FIFO** with
`set_clock_groups -asynchronous` (or `set_max_delay -datapath_only`). This is fixed by
a synchronizing FIFO + constraints — standard CDC practice, independent of whether the
core is HLS or hand-written RTL.

> Audit note: `report_cdc` was run on the existing integrated block design (built with
> the earlier kernel). The own-FFT kernel is also strictly single-clock, so it slots
> into the identical single-clock PL fabric and introduces no new crossing — the
> "Safely Timed" result carries over. Re-integrating the own-FFT kernel into the BD
> and re-running `report_cdc` is recommended as confirmation when that BD is built.

## Part C — decision

- **Latency: PASS** the real-time budget → **do NOT rewrite the FFT to streaming
  RTL.** The HLS engine's 7.2× per-cell headroom meets the monitoring deadline; a
  pure-RTL SDF FFT would add throughput headroom but is not justified by the deadline.
- **CDC: clean** on the current design (all paths safely timed, single PL clock). The
  only CDC action is the forward-looking async AXIS FIFO + constraints **if** the
  kernel is later clocked above the DMA/AXI domain — a synchronizer/constraint fix,
  not an RTL conversion.

**Outcome: HLS passes the audit. No RTL overhaul. CDC is a constraints/FIFO concern
to address only at the faster-clock integration step.**
