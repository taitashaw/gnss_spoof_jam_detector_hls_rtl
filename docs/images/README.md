# Waveform and chart artifacts

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

All images here are produced from real runs, not mock-ups.

## Charts

- `scores_by_scenario.png`, `metrics_by_scenario.png` — produced by `make plots`
  from the real `make selfcheck` / `make xsim` metrics (seed `0xC0FFEE`).

## Waveform

- `waveform_mixed_attack.png` — a timing diagram rendered by
  `scripts/render_wave.py` from `mixed_attack.vcd`, the value-change dump from a
  real XSim run of `tb_gnss_top` on the `mixed_attack` scenario under `burst`
  backpressure (seed `0xC0FFEE`). Every transition shown is a real transition in
  the VCD. It highlights a metrics-output backpressure interval where
  `m_axis_tvalid` is held while `m_axis_tready = 0` and `tdata` stays stable — the
  AXIS rule that a functional C simulation cannot exercise.

  XSim on this install has no headless GUI-to-PNG export, so the committed PNG is a
  faithful matplotlib rendering of the actual VCD signal data rather than a GUI
  screenshot (no fabricated screenshot is committed).

  A real XSim GUI capture was attempted under a virtual framebuffer (Xvfb): the
  Vivado simulator GUI does launch and load the design, but the wave window cannot
  be brought to the foreground, focused, or zoomed to the backpressure interval
  without interactive control — the simulator exposes no scriptable wave-focus or
  zoom-to-range Tcl command, and no GUI-automation tool (xdotool) is available
  headless. Every capture rendered the source/objects panel, not a legible wave
  window. Rather than commit a screenshot that does not actually show the
  waveform, the matplotlib render above (real VCD data) remains the waveform
  artifact. To capture the XSim wave window interactively, open the design in the
  Vivado GUI on a real display and apply `mixed_attack.wcfg`.

- `mixed_attack.vcd` — the real value-change dump (open directly in GTKWave, or
  import into the Vivado/XSim waveform viewer).
- `mixed_attack.wcfg` — a Vivado XSim waveform configuration naming the same
  signals, for the interactive GUI view.

### Reproduce

```
# regenerate the VCD, the native .wdb, and the rendered PNG in one step:
make waves

# or open interactively in the Vivado GUI:
#   1. regenerate the native waveform database:
#        cd <a scratch dir>
#        xvlog -sv -d SIM_ASSERT <repo>/rtl/gnss/gnss_top_pkg.sv <repo>/rtl/common/*.sv \
#              <repo>/rtl/gnss/*.sv <repo>/tb/axis_bfm.sv <repo>/tb/gnss_scoreboard.sv \
#              <repo>/tb/tb_gnss_top.sv
#        xelab tb_gnss_top -s wsim -d SIM_ASSERT --timescale 1ns/1ps -debug typical
#        echo 'log_wave -recursive *; run all; exit' > dump.tcl
#        xsim wsim -tclbatch dump.tcl -wdb mixed_attack.wdb \
#             --testplusarg INFILE=<repo>/vectors/mixed_attack/input_iq.txt \
#             --testplusarg OUTFILE=/tmp/o.txt --testplusarg SCENARIO=mixed_attack \
#             --testplusarg STALL_MODE=burst --testplusarg SEED=12648430
#   2. vivado -> Open Static Simulation -> load mixed_attack.wdb, apply mixed_attack.wcfg
```

The native `.wdb` is several megabytes and is regenerable from the command above,
so it is not committed; the equivalent `.vcd` (same signal data, much smaller) is.
