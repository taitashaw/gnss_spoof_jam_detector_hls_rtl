# Hardware Bring-Up Notes

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

> **Legacy.** The NCO/PRN/metric-engine bring-up steps below are for the superseded
> streaming front-end (README §11). The current ddMap/SQM detector takes pre-wiped,
> decimated I/Q over AXI4-Stream and a `prn` over s_axilite; its hardware path is the
> standard Zynq UltraScale+ DMA + s_axilite pattern (see `docs/architecture.md` and
> `docs/audit_latency_cdc.md`).

This design is simulation-complete and structured for a real bench. Nothing below
claims board validation; the items marked TODO genuinely require board
documentation that is not assumed to exist.

## ZCU104-class path (Zynq UltraScale+)

Target part `xczu7ev-ffvc1156-2-e`. The intended system topology:

- The PS (processor system) feeds sample buffers to the PL over an AXI DMA, or a
  live ADC stream enters the PL directly through an AXI4-Stream from the front-end.
- The PL processes the deterministic stream through this accelerator with a bounded
  per-window latency that `axis_latency_counter` measures directly.
- Results return to the PS as either an AXI4-Stream of metrics packets into a DMA
  descriptor ring, or as register reads. The `simple_reg_bank` in this design maps
  one-to-one onto an AXI4-Lite slave: each register address becomes an AXI4-Lite
  offset, with the config registers as writes and the status/`power_prev`/
  `noise_prev` registers as reads.

The reset polarity is reconciled in exactly one place. The RTL is active-low
`rst_n`; the Vitis-HLS-exported metric IP uses active-high `ap_rst`. `gnss_top.sv`
derives `hls_rst = ~rst_n` and that is the only adapter; wire the exported IP's
`ap_rst` to `hls_rst` when swapping it in.

## NT1065 / FMC front-end path (TODO: needs board documentation)

A real GNSS RF front-end such as an NT1065 over an FMC carrier would replace the
synthetic vectors. This is gated on documentation that this repository does not
assume:

- TODO: the FMC pinout for the specific carrier and front-end.
- TODO: the exact ADC sample format and how I and Q are presented (bit width,
  packing, two's-complement vs offset-binary, sample rate).
- TODO: the clocking and reset constraints (reference clock, sample clock domain,
  reset sequencing) and the constraints file entries they imply.

Until those exist, the simulation uses a generic s16 I/Q contract. When they are
known, the only change is the source of the AXI4-Stream: set `nco_phase_inc` to the
real intermediate frequency and `prn_seed` to the target code, and the mixer, PRN,
metric engine, and alert packer are unchanged.

## GPS L1/L2 antenna

A passive or active GPS antenna is useful only once the RF front-end capture works,
because the accelerator operates on digitized I/Q, not on RF. It is listed here so
the full bench is documented, not because any antenna-dependent claim is made.

## Smaller boards

- Zybo Z7: suitable for smaller stream-control demonstrations of the AXIS plumbing
  and the NCO/PRN front-end at reduced window sizes.
- Basys 3: an educational and control-path subset only; it has no usable RF path
  and limited resources, so it can host the handshake and counter logic for
  teaching but not the full metric engine at the default window.

## The one concrete next step

Replace the synthetic I/Q source with a single captured NT1065 ADC frame at the
same s16 I/Q AXI4-Stream contract and re-run `make xsim` unchanged. That exercises
the entire pipeline on real signal characteristics without any RTL change and is
the smallest honest step from simulation toward the bench.
