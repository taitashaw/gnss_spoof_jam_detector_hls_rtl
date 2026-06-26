# Vitis HLS csim + csynth for the ddMap/SQM detector with our own fixed-point FFT
# Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
set REPO [file normalize [file join [file dirname [info script]] ../..]]
set INC "-I$REPO/hls/include -I$REPO/hls/src"
open_project -reset ddmap_ownfft_prj
set_top ddmap_sqm_hls
add_files    $REPO/hls/src/ddmap_sqm_hls.cpp   -cflags "$INC"
add_files -tb $REPO/hls/tb/tb_ddmap_sqm_hls.cpp -cflags "$INC"
open_solution -reset sol1
set_part xczu7ev-ffvc1156-2-e
create_clock -period 5 -name default
puts "==== C SIMULATION (own FFT, vs Python golden) ===="
if {[catch {csim_design -argv "$REPO"} e]} { puts "CSIM_STATUS: FAILED $e" } else { puts "CSIM_STATUS: PASSED" }
puts "==== C SYNTHESIS ===="
if {[catch {csynth_design} se]} { puts "CSYNTH_STATUS: FAILED $se"; exit 1 }
puts "OWNFFT DONE"
exit 0
