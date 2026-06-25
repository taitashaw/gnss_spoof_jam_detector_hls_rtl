# ============================================================================
# run_hls.tcl -- Vitis HLS build for the GNSS metric kernel
# Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
#
# Run:  vitis_hls -f hls/vitis_hls/run_hls.tcl
#
# Runs C simulation (kernel vs golden reference), C synthesis, and -- if synth
# succeeds -- exports the RTL IP. To retarget, change PART in ONE place below
# (the Vivado/XSim flow's PART lives in vivado/compile_order.tcl; keep them in
# sync). Toolchain assumption: Vitis HLS 2022.2+ (uses ap_int / ap_axiu /
# hls::stream). On 2025.2 the same classic TCL is driven via the vitis_hls
# wrapper script; see README for the exact invocation.
# ============================================================================

# ---- single place to set the target part ----
set PART xczu7ev-ffvc1156-2-e

set REPO [file normalize [file join [file dirname [info script]] ../..]]
set INC  "-I$REPO/hls/include"

open_project -reset gnss_metric_hls_prj
set_top gnss_metric_hls

add_files    $REPO/hls/src/gnss_metric_hls.cpp  -cflags "$INC"
add_files -tb $REPO/hls/tb/tb_gnss_metric_hls.cpp -cflags "$INC"

open_solution -reset sol1
set_part $PART
create_clock -period 5 -name default

source $REPO/hls/vitis_hls/solution_directives.tcl

puts "==== C SIMULATION (kernel vs golden) ===="
csim_design -argv "$REPO"

puts "==== C SYNTHESIS ===="
if {[catch {csynth_design} synth_err]} {
    puts "ERROR: csynth_design failed: $synth_err"
    exit 1
}

puts "==== EXPORT RTL IP ===="
if {[catch {export_design -rtl verilog -format ip_catalog} exp_err]} {
    puts "WARNING: export_design failed (synthesis still valid): $exp_err"
}

puts "HLS flow complete. Reports under gnss_metric_hls_prj/sol1/syn/report/."
exit 0
