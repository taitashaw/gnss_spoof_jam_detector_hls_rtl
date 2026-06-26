# Block design diagram

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

`gnss_block_design.png` / `.svg` are real exports of the **current** own-FFT
ddMap/SQM block design — Vivado's own rendering of the actual canvas
(`write_bd_layout`), not a hand-drawn or fabricated image.

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

# 3) render the diagram under a virtual framebuffer (start_gui enables the canvas)
export DISPLAY=:99 ; Xvfb :99 -screen 0 2400x1600x24 &
vivado -mode batch -source - <<'TCL'
open_project build/vivado_bd_ownfft/gnss_ownfft_system.xpr
open_bd_design [get_files gnss_ownfft_system_bd.bd]
start_gui
write_bd_layout -format svg -orientation landscape -force docs/images/gnss_block_design.svg
write_bd_layout -format pdf -orientation landscape -force build/vivado_bd_ownfft/gnss_ownfft_bd.pdf
TCL

# 4) rasterize the vector PDF to PNG
convert -density 300 build/vivado_bd_ownfft/gnss_ownfft_bd.pdf -background white -flatten \
        -trim +repage -bordercolor white -border 40 docs/images/gnss_block_design.png
```

To inspect interactively: `vivado build/vivado_bd_ownfft/gnss_ownfft_system.xpr`.
