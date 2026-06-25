# System Integration (Zynq UltraScale+)

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

**Status: block design validated and synthesized; not yet flashed to a board.**

This phase integrates the Vitis-HLS-exported metric IP into a ZCU104-class Zynq
UltraScale+ system as a reproducible Vivado IP Integrator block design
(`vivado/run_bd.tcl`, batch — no GUI required to build or validate). The block
design validates with **zero critical warnings** and synthesizes with real
post-synthesis utilization (below). No bitstream is generated and nothing is run
on hardware.

![GNSS system block design](images/gnss_block_design.png)

## PS / PL architecture

- **PS — Zynq UltraScale+ MPSoC** (`zynq_ultra_ps_e`). The processing system runs
  the control software, owns DDR, and is the hardened silicon half of the device.
  One master port (`M_AXI_HPM0_FPD`) drives the control plane; one high-performance
  slave port (`S_AXI_HP0_FPD`, 128-bit) is the DMA's path to DDR. The PL fabric is
  clocked from `pl_clk0` (100 MHz) with `pl_resetn0` through a
  `proc_sys_reset` block.
- **PL — accelerator datapath.** An AXI DMA moves data between DDR and the
  accelerator's AXI4-Stream ports; the exported metric kernel
  (`xilinx.com:hls:gnss_metric_hls:1.0`) does the work; two AXI SmartConnects
  fan the control path out and the memory path in.

## DMA datapath (MM2S in, S2MM out)

```
DDR <-> PS S_AXI_HP0 <-> data_smc <-> AXI DMA  --MM2S(64b)-->  kernel tap_in
                                       AXI DMA  <--S2MM(512b)-- kernel metric_out
```

- **MM2S (memory-mapped to stream):** the DMA reads a buffer from DDR and streams
  it into the kernel's `tap_in` (64-bit AXI4-Stream, `tlast` delimiting each
  window). On the full ADC bench this stream is the tapped samples produced by the
  RTL front-end; for the integrated accelerator it is fed from DDR by the PS.
- **S2MM (stream to memory-mapped):** the kernel emits one 512-bit metrics packet
  per window on `metric_out` (`tlast = 1`), and the DMA writes it back to a DDR
  buffer for the PS to read.
- The DMA runs in direct-register mode (no scatter-gather); MM2S and S2MM stream
  widths are set independently (64-bit in, 512-bit out) to match the kernel ports.

### How the s16 I/Q AXI4-Stream contract maps in

The system-level I/Q contract is unchanged: `I = tdata[31:16]`, `Q = tdata[15:0]`,
`tlast` per window. In the full bench, the verified RTL front-end
(`nco_mixer` -> `prn_lfsr_gen` -> `early_prompt_late_tap`) consumes that raw s16
I/Q stream from the RF front-end (or a DMA MM2S channel) and produces the tapped
stream that feeds the kernel; the kernel's `metric_out` then goes to
`gnss_alert_packer` and out to S2MM. Only the metric kernel is exported as IP, so
this block design wires the kernel and DMA; the NCO/PRN/tap front-end and the
alert packer are the surrounding verified RTL (see `docs/architecture.md`) that a
later IP-packaging step folds into the same block design boundary.

## Control path (s_axilite)

```
PS M_AXI_HPM0 -> ctrl_smc -> { AXI DMA S_AXI_LITE, kernel s_axi_ctrl }
```

The PS configures and starts transfers over AXI4-Lite: the DMA's `S_AXI_LITE`
registers (source/destination addresses, lengths, start) and the kernel's
`s_axi_ctrl` block, which carries the ap_ctrl handshake plus the scalar config and
status the kernel uses per window — `window_id`, `power_prev`, `noise_prev` in, and
the current power/noise out — the pass-in design that keeps the power-jump and
noise-IIR state in software-visible registers rather than hidden in the kernel.

## Post-synthesis utilization (real, verbatim from the tool)

`synth_design` ran to completion on the block-design wrapper. The numbers below
are copied from `docs/synth/system_synth_util.rpt`; none are estimated by hand.
The PS is hardened silicon, so this is the PL fabric cost of the integrated
datapath (AXI DMA + two SmartConnects + the metric kernel + reset).

| Resource | Used | Available | Utilization |
|---|---|---|---|
| CLB LUTs | 11035 | 230400 | 4.79% |
| — LUT as logic | 9295 | 230400 | 4.03% |
| — LUT as memory | 1740 | 101760 | 1.71% |
| CLB Registers (FF) | 17757 | 460800 | 3.85% |
| Block RAM Tile | 10 (9x RAMB36, 2x RAMB18) | 312 | 3.21% |
| DSP48E2 | 4 | 1728 | 0.23% |
| URAM | 0 | 96 | 0% |

The four DSPs are exactly the metric kernel's correlation and cross-product
multipliers; the DMA and SmartConnects add no DSP. Block RAM comes from the DMA and
SmartConnect data FIFOs. The full integrated datapath uses under 5% of the
xczu7ev's LUTs, leaving ample room for multiple correlator channels.

This is a post-synthesis estimate; post-implementation (place-and-route) numbers
and final timing closure are the next deferred phase, along with bitstream
generation and on-board bring-up.

## Reproduce

```
make hls                                   # export the metric IP (prerequisite)
vivado -mode batch -source vivado/run_bd.tcl   # build + validate the block design
```

See `docs/images/BLOCK_DESIGN.md` for how the diagram was exported and how to open
the design in the Vivado GUI.
