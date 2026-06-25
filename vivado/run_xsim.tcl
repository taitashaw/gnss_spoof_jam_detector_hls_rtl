# ============================================================================
# run_xsim.tcl -- compile + elaborate + run the GNSS scenario matrix in XSim
# Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
#
# Run with:   vivado -mode batch -source vivado/run_xsim.tcl
# (or use the thinner scripts/run_xsim.sh wrapper, which the Makefile calls.)
#
# Compiles in the order from compile_order.tcl, elaborates tb_gnss_top with the
# SIM_ASSERT protocol assertions enabled (-d SIM_ASSERT), and runs every scenario
# in the Section-12 test matrix, writing results/<scenario>/actual_metrics.txt for
# scripts/check_gnss_results.py to validate. Backpressure uses a fixed seed so the
# stalls are reproducible.
# ============================================================================
source [file join [file dirname [info script]] compile_order.tcl]

set SEED 12648430  ;# 0xC0FFEE

# scenario -> stall mode (Section 12 matrix)
set MATRIX {
    {clean         none}
    {clean         random}
    {wideband_jam  none}
    {tone_jam      random}
    {delayed_spoof random}
    {doppler_shift burst}
    {cn0_drop      none}
    {mixed_attack  random}
    {backpressure  random}
}

puts "== xvlog (compile) =="
exec xvlog -sv -d SIM_ASSERT {*}$ALL_SRCS >@ stdout

puts "== xelab (elaborate tb_gnss_top) =="
exec xelab tb_gnss_top -s gnss_sim -d SIM_ASSERT --timescale 1ns/1ps >@ stdout

foreach pair $MATRIX {
    lassign $pair scen mode
    set infile  $REPO/vectors/$scen/input_iq.txt
    set outdir  $REPO/results/$scen
    file mkdir $outdir
    set outfile $outdir/actual_metrics.txt
    if {![file exists $infile]} {
        puts "SKIP $scen ($infile missing -- run 'make vectors')"
        continue
    }
    puts "== run $scen (stall=$mode) =="
    exec xsim gnss_sim -R \
        --testplusarg INFILE=$infile \
        --testplusarg OUTFILE=$outfile \
        --testplusarg SCENARIO=$scen \
        --testplusarg STALL_MODE=$mode \
        --testplusarg SEED=$SEED >@ stdout
}

puts "== unit testbenches =="
foreach ut {tb_axis_skid_buffer tb_nco_mixer tb_prn_lfsr_gen} {
    exec xelab $ut -s ${ut}_s --timescale 1ns/1ps >@ stdout
    exec xsim ${ut}_s -R >@ stdout
}
puts "XSim run complete. Validate with: make check"
