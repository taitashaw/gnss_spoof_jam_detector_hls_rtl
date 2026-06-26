# ============================================================================
# run_ddmap_hls.tcl -- Vitis HLS csim + csynth for the ddMap/SQM detector kernel
# Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
#
# Run:  vitis-run --mode hls --tcl hls/vitis_hls/run_ddmap_hls.tcl
# Builds the synthesizable hls::fft ddMap/SQM kernel, C-simulates against the
# Python golden (vectors/ddmap_hls), and runs C synthesis. Reports go under
# ddmap_sqm_prj/sol1/syn/report/.  Separate project from the old metric kernel.
# ============================================================================
set PART xczu7ev-ffvc1156-2-e
set REPO [file normalize [file join [file dirname [info script]] ../..]]
set INC  "-I$REPO/hls/include"

open_project -reset ddmap_sqm_prj
set_top ddmap_sqm_hls
add_files    $REPO/hls/src/ddmap_sqm_hls.cpp   -cflags "$INC"
add_files -tb $REPO/hls/tb/tb_ddmap_sqm_hls.cpp -cflags "$INC"

open_solution -reset sol1
set_part $PART
create_clock -period 5 -name default

puts "==== C SIMULATION (kernel vs golden) ===="
if {[catch {csim_design -argv "$REPO"} csim_err]} {
    puts "CSIM_STATUS: FAILED ($csim_err) -- proceeding to csynth for resource numbers"
} else {
    puts "CSIM_STATUS: PASSED"
}

puts "==== C SYNTHESIS ===="
if {[catch {csynth_design} err]} {
    puts "ERROR: csynth_design failed: $err"
    exit 1
}
puts "DDMAP HLS DONE. Reports: ddmap_sqm_prj/sol1/syn/report/"
exit 0
