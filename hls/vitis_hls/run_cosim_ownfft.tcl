set REPO [file normalize [file join [file dirname [info script]] ../..]]
open_project ddmap_ownfft_ip_prj
set_top ddmap_sqm_hls
open_solution sol1
puts "==== COSIM (own FFT, trace) ===="
if {[catch {cosim_design -trace_level all -rtl verilog -argv "$REPO"} e]} { puts "COSIM_FAILED: $e" } else { puts "COSIM_PASSED" }
exit 0
