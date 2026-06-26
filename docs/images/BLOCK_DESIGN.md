# Block design diagram

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

`gnss_block_design.png` is a **screenshot of the actual Vivado IP Integrator canvas**
for the **current** own-FFT ddMap/SQM block design — the real tool window, not a
hand-drawn or fabricated image. `gnss_block_design.svg` is the same design exported
as vector by Vivado's `write_bd_layout`.

The block design integrates the current kernel IP
(`xilinx.com:hls:ddmap_sqm_hls:1.0`, exported by
`hls/vitis_hls/run_export_ownfft.tcl`): Zynq UltraScale+ PS, an AXI DMA whose MM2S
stream drives the kernel `iq_in` AXI4-Stream, the kernel's `s_axi_ctrl` for the
`prn` input and the result registers, and two AXI SmartConnects + a processor reset.
It validates with **zero critical warnings**.

`write_bd_layout` needs the Vivado GUI subsystem (canvas), which a plain `-mode
batch` run lacks, so the export is done under a virtual framebuffer with `start_gui`.
`write_bd_layout` does not accept `png` in this build, so SVG/PDF are exported and the
PDF is rasterized.

## Reproduce

```
# 1) export the current kernel as IP
vitis-run --mode hls --tcl hls/vitis_hls/run_export_ownfft.tcl

# 2) build + validate the block design (zero critical warnings) and write SVG
vivado -mode batch -source vivado/run_bd_ownfft.tcl        # writes docs/images/gnss_block_design.svg

# 3) PNG = screenshot of the real IP Integrator canvas, headless under Xvfb
#    (wide framebuffer so the whole BD fits; regenerate_bd_layout tidies placement)
export DISPLAY=:98 ; Xvfb :98 -screen 0 3840x1400x24 &
vivado -mode gui -source - <<'TCL' &
open_project build/vivado_bd_ownfft/gnss_ownfft_system.xpr
open_bd_design [get_files gnss_ownfft_system_bd.bd]
regenerate_bd_layout
TCL
sleep 105 ; import -window root /tmp/bd_full.png       # capture the canvas
# then crop the diagram region to docs/images/gnss_block_design.png

# 4) SVG = Vivado vector export of the same canvas (start_gui enables the renderer)
vivado -mode batch -source - <<'TCL'
open_project build/vivado_bd_ownfft/gnss_ownfft_system.xpr
open_bd_design [get_files gnss_ownfft_system_bd.bd]
start_gui
write_bd_layout -format svg -orientation landscape -force docs/images/gnss_block_design.svg
TCL
```

To inspect interactively: `vivado build/vivado_bd_ownfft/gnss_ownfft_system.xpr`.
