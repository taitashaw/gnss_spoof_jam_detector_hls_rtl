# ============================================================================
# run_bd_gnss_spoof_jam_detector_system.tcl
#   Zynq UltraScale+ block design for the own-FFT ddMap/SQM GNSS spoof/jam
#   detector kernel (xilinx.com:hls:ddmap_sqm_hls:1.0).
# Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
#
# Batch, no GUI. Reproduces the COMPLETE current diagram end to end, including
# the external RESULTS_READY_IRQ port and the two I/O annotation comments, so a
# fresh rebuild regenerates exactly what exists today.
#
#   PS M_AXI_HPM0 -> ctrl_smc -> { AXI DMA S_AXI_LITE, kernel s_axi_ctrl }
#   AXI DMA MM2S (32b) -> kernel iq_in
#   AXI DMA M_AXI_MM2S -> data_smc -> PS S_AXI_HP0 (DDR)
#   kernel interrupt -> external port RESULTS_READY_IRQ
# The kernel has NO AXIS output (results are read over s_axi_ctrl registers:
# peak_power, code_phase, distortion_q16, early/late_power), so there is no S2MM.
#
# Run:  vivado -mode batch -source vivado/run_bd_gnss_spoof_jam_detector_system.tcl
# ============================================================================
set REPO    [file normalize [file join [file dirname [info script]] ..]]
set PART    xczu7ev-ffvc1156-2-e
set IP_REPO $REPO/hls/vitis_hls/ddmap_ownfft_ip_prj/sol1/impl/ip
set BD      gnss_spoof_jam_detector_system_bd
set PROJDIR $REPO/build/vivado_bd_gnss_spoof_jam_detector_system

if {![file exists $IP_REPO/component.xml]} { puts "ERROR: own-FFT IP not found at $IP_REPO"; exit 1 }
file mkdir $PROJDIR
create_project -force gnss_spoof_jam_detector_system $PROJDIR -part $PART
set_property ip_repo_paths [list $IP_REPO] [current_project]
update_ip_catalog
create_bd_design $BD
current_bd_design $BD

# ---- Processing System (minimal: one HP slave + M_AXI_HPM, one PL clock) ----
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* zynq_ultra_ps_e_0]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset 0} [get_bd_cells zynq_ultra_ps_e_0]
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__USE__S_AXI_GP2 {1} \
    CONFIG.PSU__SAXIGP2__DATA_WIDTH {128} \
    CONFIG.PSU__MAXIGP0__DATA_WIDTH {32} \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
] $ps

# ---- own-FFT ddMap/SQM kernel ----
set kern [create_bd_cell -type ip -vlnv xilinx.com:hls:ddmap_sqm_hls:1.0 ddmap_sqm_hls_0]
# discover the kernel's interface pins by type (robust to naming)
set kern_axis [get_bd_intf_pins -of $kern -filter {VLNV =~ *axis* && MODE == Slave}]
set kern_ctrl [get_bd_intf_pins -of $kern -filter {VLNV =~ *aximm* && MODE == Slave}]
puts "KERNEL_AXIS=$kern_axis  KERNEL_CTRL=$kern_ctrl"

# ---- AXI DMA: MM2S only (32-bit stream into the kernel) ----
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:* axi_dma_0]
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {0} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_m_axi_mm2s_data_width {32} \
    CONFIG.c_mm2s_burst_size {16} \
] $dma

# ---- SmartConnects: control fan-out (1->2), memory fan-in (1->1) ----
set ctrl_smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* ctrl_smc]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] $ctrl_smc
set data_smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* data_smc]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] $data_smc

# ---- reset ----
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* proc_sys_reset_0

# ---- clock + reset nets ----
set clk  [get_bd_pins zynq_ultra_ps_e_0/pl_clk0]
set prst [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0]
connect_bd_net $clk \
    [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk] \
    [get_bd_pins zynq_ultra_ps_e_0/saxihp0_fpd_aclk] \
    [get_bd_pins axi_dma_0/s_axi_lite_aclk] \
    [get_bd_pins axi_dma_0/m_axi_mm2s_aclk] \
    [get_bd_pins ddmap_sqm_hls_0/ap_clk] \
    [get_bd_pins ctrl_smc/aclk] \
    [get_bd_pins data_smc/aclk] \
    [get_bd_pins proc_sys_reset_0/slowest_sync_clk]
connect_bd_net $prst [get_bd_pins proc_sys_reset_0/ext_reset_in]
connect_bd_net [get_bd_pins proc_sys_reset_0/interconnect_aresetn] \
    [get_bd_pins ctrl_smc/aresetn] [get_bd_pins data_smc/aresetn]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
    [get_bd_pins axi_dma_0/axi_resetn] [get_bd_pins ddmap_sqm_hls_0/ap_rst_n]

# ---- control path: PS M_AXI_HPM0 -> ctrl_smc -> {DMA lite, kernel ctrl} ----
connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] [get_bd_intf_pins ctrl_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_smc/M00_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins ctrl_smc/M01_AXI] $kern_ctrl

# ---- memory path: DMA M_AXI_MM2S -> data_smc -> PS S_AXI_HP0 ----
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins data_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins data_smc/M00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP0_FPD]

# ---- AXI4-Stream datapath: DMA MM2S -> kernel iq_in ----
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] $kern_axis

# ---- manual addition #1: kernel interrupt made external as RESULTS_READY_IRQ ----
set irq_port [create_bd_port -dir O -type intr RESULTS_READY_IRQ]
connect_bd_net [get_bd_pins ddmap_sqm_hls_0/interrupt] $irq_port

# ---- manual addition #2: the two I/O annotation comments ----
set_property USER_COMMENTS.comment_0 {I/Q INPUT (AXIS) - DMA-fed; FMC/ADC injection point} [current_bd_design]
set_property USER_COMMENTS.comment_1 {RESULTS OUT - read via s_axi_ctrl registers} [current_bd_design]

# ---- addresses + validate ----
assign_bd_address
regenerate_bd_layout
save_bd_design
set vrc [catch {validate_bd_design} verr]
puts "==== validate_bd_design ===="
puts $verr
set crit [get_msg_config -severity {CRITICAL WARNING} -count]
puts "CRITICAL_WARNING_COUNT=$crit"
if {$vrc} { puts "VALIDATE_FAILED"; exit 2 }
save_bd_design

# ---- render the CURRENT block-design diagram (headless) ----
if {[catch {write_bd_layout -force -format png $REPO/docs/images/gnss_block_design.png} pe]} {
    puts "WRITE_BD_PNG_FAILED: $pe"
} else { puts "WROTE_BD_PNG" }
if {[catch {write_bd_layout -force -format svg $REPO/docs/images/gnss_block_design.svg} se]} {
    puts "WRITE_BD_SVG_FAILED: $se"
} else { puts "WROTE_BD_SVG" }

# ---- BD wrapper ----
make_wrapper -files [get_files $PROJDIR/gnss_spoof_jam_detector_system.srcs/sources_1/bd/$BD/$BD.bd] -top
puts "BD_DONE"
exit 0
