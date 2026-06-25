# Block design diagram

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

`gnss_block_design.png` and `gnss_block_design.svg` are real exports of the
validated Vivado IP Integrator block design `gnss_system_bd`, produced by
`vivado/run_bd.tcl`. The diagram is Vivado's own rendering of the actual canvas
(`write_bd_layout`), not a hand-drawn or fabricated image.

## How it was produced

`write_bd_layout` requires the Vivado GUI subsystem, which is unavailable in a
pure headless batch shell. It was run under a virtual framebuffer so Vivado
rendered its own diagram with no interactive session:

```
# build + validate the block design
vivado -mode batch -source vivado/run_bd.tcl

# export the validated layout (Vivado renders SVG/PDF; PNG is not a valid
# write_bd_layout format in this build, so SVG/PDF then rasterized)
xvfb-run -a vivado -mode batch -source - <<'TCL'
open_project build/vivado_bd/gnss_system.xpr
open_bd_design build/vivado_bd/gnss_system.srcs/sources_1/bd/gnss_system_bd/gnss_system_bd.bd
start_gui
write_bd_layout -format svg -orientation landscape -force docs/images/gnss_block_design.svg
write_bd_layout -format pdf -orientation landscape -force build/vivado_bd/gnss_block_design.pdf
stop_gui
TCL

# rasterize the vector export to PNG
convert -density 150 build/vivado_bd/gnss_block_design.pdf -rotate 90 -background white -flatten \
        docs/images/gnss_block_design.png
convert docs/images/gnss_block_design.png -trim +repage -bordercolor white -border 25 \
        docs/images/gnss_block_design.png
```

## Reproduce / inspect interactively

```
vivado -mode batch -source vivado/run_bd.tcl   # build + validate
vivado build/vivado_bd/gnss_system.xpr          # open in the GUI to inspect/screenshot
```

The committed `.svg` is the vector source; the `.png` is the rasterized version
embedded in the README.
