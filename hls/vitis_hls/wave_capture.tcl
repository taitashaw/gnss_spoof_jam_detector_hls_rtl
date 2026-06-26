# XSim wave-viewer setup for the own-FFT ddMap/SQM kernel cosim AXIS waveform.
# Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
#
# After cosim_design, run this in the XSim GUI to reproduce docs/images/
# waveform_ddmap_axis.png (the real wave-viewer screenshot):
#   cd hls/vitis_hls/ddmap_ownfft_ip_prj/sol1/sim/verilog
#   DISPLAY=:N  xsim ddmap_sqm_hls -gui -tclbatch ../../../../wave_capture.tcl
# then screenshot the wave window (headless: Xvfb + `import -window root`).
# run 76500 ns stops just after iq_in_TREADY rises (~75 us, the backpressure
# release after the code FFT) so XSim's auto-zoom lands on that transition.
set dut /apatb_ddmap_sqm_hls_top/AESL_inst_ddmap_sqm_hls
add_wave ${dut}/ap_start
add_wave ${dut}/iq_in_TVALID
add_wave ${dut}/iq_in_TREADY
add_wave ${dut}/iq_in_TLAST
add_wave ${dut}/iq_in_TDATA
add_wave ${dut}/ap_done
run 76500 ns
