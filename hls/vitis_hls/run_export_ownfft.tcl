# Export the CURRENT own-FFT ddMap/SQM kernel as an IP-XACT component
# Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
set REPO [file normalize [file join [file dirname [info script]] ../..]]
set INC "-I$REPO/hls/include -I$REPO/hls/src"
open_project -reset ddmap_ownfft_ip_prj
set_top ddmap_sqm_hls
add_files    $REPO/hls/src/ddmap_sqm_hls.cpp   -cflags "$INC"
add_files -tb $REPO/hls/tb/tb_ddmap_sqm_hls.cpp -cflags "$INC"
open_solution -reset sol1
set_part xczu7ev-ffvc1156-2-e
create_clock -period 2.5 -name default
puts "==== C SYNTHESIS ===="
if {[catch {csynth_design} se]} { puts "CSYNTH_FAILED: $se"; exit 1 }
puts "==== EXPORT IP ===="
if {[catch {export_design -rtl verilog -format ip_catalog -display_name "ddmap_sqm_ownfft" -description "DBZP ddMap + own fixed-point FFT + SQM detector"} ee]} { puts "EXPORT_FAILED: $ee"; exit 1 }
puts "EXPORT DONE"
exit 0
