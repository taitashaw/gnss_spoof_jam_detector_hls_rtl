set REPO [file normalize [file join [file dirname [info script]] ../..]]
open_project ddmap_sqm_prj
set_top ddmap_sqm_hls
add_files $REPO/hls/src/ddmap_sqm_hls.cpp -cflags "-I$REPO/hls/include"
add_files -tb $REPO/hls/tb/tb_ddmap_sqm_hls.cpp -cflags "-I$REPO/hls/include"
open_solution sol1
set_part xczu7ev-ffvc1156-2-e
create_clock -period 5 -name default
puts "==== C SYNTHESIS (BFP config) ===="
if {[catch {csynth_design} se]} { puts "CSYNTH_FAILED: $se"; exit 1 }
puts "==== COSIM (RTL vs C) ===="
if {[catch {cosim_design -argv "$REPO" -trace_level none} ce]} {
    puts "COSIM_RESULT: FAILED ($ce)"
} else { puts "COSIM_RESULT: PASSED" }
exit 0
