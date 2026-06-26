# Implementation (place-and-route + bitstream)

> **Kernel scope.** The numbers in this document are for the original streaming
> metric-engine kernel (LFSR/NCO-PRN anomaly accelerator), NOT the DBZP ddMap + SQM
> single-pass detector (the real detection core on real GPS data, validated as the
> C/Python golden + benchmark in `docs/comparison_baseline_vs_ddmap.md`). The ddMap
> FFT-correlation kernel is heavier (see the benchmark cost table) and has not yet
> been synthesized; no ddMap-kernel synthesis/impl number is claimed.

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

**Status: synthesized, placed, routed, timing-closed, and a bitstream was
generated. NOT flashed to a board.** There is no on-board run, no JTAG, no
hardware verification here.

Every number below is copied verbatim from the Vivado tool reports
(`docs/synth/impl_timing_summary.rpt`, `docs/synth/impl_util.rpt`); none are
estimated by hand.

## What was implemented

The deployable, bitstreamable configuration is the **DMA-only** variant of the
block design (`vivado/run_bd.tcl -tclargs 0`): PS + AXI DMA + the exported HLS
metric IP + SmartConnects + reset, with the kernel fed and drained by the DMA.

The external-FMC-port variant (`vivado/run_bd.tcl` default, `EXPOSE_FMC=1`)
validates and synthesizes, but it exposes a 64-bit I/Q input and a 512-bit metrics
output as top-level AXI4-Stream ports. That is **686 device I/O ports**, which
overutilizes the package — implementation fails at I/O placement
(`ERROR: [Place 30-415] IO Placement failed due to overutilization`). So the
bitstream is generated from the DMA-only variant; the external-port variant remains
a validated/synthesized design for the direct front-end streaming path (in a real
board that wide path would be an on-chip sink or a serialized link, not hundreds of
bonded pins). See `docs/system_integration.md`.

## Provenance

- Tool: Vivado 2025.2.
- Part: `xczu7ev-ffvc1156-2-e` (ZCU104 class).
- Clock: PL `pl_clk0`, achieved 96.968727 MHz (period 10.3125 ns).
- Flow run: `synth_design` -> `opt_design` -> `place_design` -> `route_design` ->
  `write_bitstream`, all completed (run status `write_bitstream Complete!`,
  progress 100%). Bitstream `gnss_system_bd_wrapper.bit` produced (~19 MB;
  regenerable, so gitignored — only the reports are committed).

## Timing (verbatim from `impl_timing_summary.rpt`)

| Metric | Value |
|---|---|
| WNS (setup worst negative slack) | 4.484 ns |
| TNS (total negative slack) | 0.000 ns |
| Setup failing endpoints | 0 of 63386 |
| WHS (hold worst slack) | 0.010 ns |
| THS (total hold slack) | 0.000 ns |
| Hold failing endpoints | 0 of 63386 |

**Timing closes.** WNS and WHS are both positive and there are zero failing setup
or hold endpoints, so all constraints are met at the ~96.97 MHz PL clock with
4.484 ns of setup margin.

## Post-implementation utilization (verbatim from `impl_util.rpt`)

| Resource | Used | Available | Utilization |
|---|---|---|---|
| CLB LUTs | 10044 | 230400 | 4.36% |
| — LUT as logic | 8378 | 230400 | 3.64% |
| — LUT as memory | 1666 | 101760 | 1.64% |
| CLB Registers (FF) | 16882 | 460800 | 3.66% |
| CLB | 2158 | 28800 | 7.49% |
| CARRY8 | 137 | 28800 | 0.48% |
| Block RAM Tile | 10 | 312 | 3.21% |
| DSP | 4 | 1728 | 0.23% |

These are post-route numbers (lower than the post-synthesis estimates, as
expected after optimization). The four DSPs are the metric kernel's multipliers;
the rest of the fabric is the AXI DMA, SmartConnects, and reset. The integrated,
routed system uses about 4-5% of the xczu7ev's logic.

## Reproduce

```
make hls                                            # export the metric IP
vivado -mode batch -source vivado/run_bd.tcl -tclargs 0   # DMA-only BD
# then implement to bitstream (see the impl TCL flow):
#   reset_run synth_1; launch_runs impl_1 -to_step write_bitstream; wait_on_run impl_1
#   report_timing_summary; report_utilization; (bitstream under impl_1/)
```

The bitstream is a build artifact; this design has not been programmed onto
hardware. On-board bring-up, ILA verification, and NT1065 RF capture remain
pending hardware (see the README roadmap).
