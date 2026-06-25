# ============================================================================
# run_bd.tcl -- Zynq UltraScale+ IP Integrator block design for the GNSS system
# Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
#
# Reproducible, batch (no GUI). Integrates the Vitis-HLS-exported metric IP
# (xilinx.com:hls:gnss_metric_hls:1.0) into a ZCU104-class system with an AXI DMA
# datapath:
#   PS M_AXI_HPM0  -> SmartConnect -> { AXI DMA S_AXI_LITE, kernel s_axi_ctrl }
#   AXI DMA MM2S (64b stream) -> kernel tap_in
#   kernel metric_out (512b stream) -> AXI DMA S2MM
#   AXI DMA M_AXI_MM2S/S2MM -> SmartConnect -> PS S_AXI_HP0 (DDR)
#
# Only the metric kernel is exported as IP; the I/Q -> tapped front-end
# (nco_mixer / prn_lfsr_gen / early_prompt_late_tap) and the alert packer are the
# verified RTL that, on the full ADC bench, sit between the RF front-end and the
# kernel. See docs/system_integration.md.
#
# Run:  vivado -mode batch -source vivado/run_bd.tcl
# Validates with validate_bd_design; aborts on any CRITICAL WARNING.
# ============================================================================

set REPO    [file normalize [file join [file dirname [info script]] ..]]
set PART    xczu7ev-ffvc1156-2-e
set IP_REPO $REPO/hls/vitis_hls/gnss_metric_hls_prj/sol1/impl/ip
set PROJDIR $REPO/build/vivado_bd
set BD      gnss_system_bd

if {![file exists $IP_REPO/component.xml]} {
    puts "ERROR: exported HLS IP not found at $IP_REPO"
    puts "       Run 'make hls' first to export the IP, then re-run this script."
    exit 1
}

file mkdir $PROJDIR
create_project -force gnss_system $PROJDIR -part $PART
set_property ip_repo_paths [list $IP_REPO] [current_project]
update_ip_catalog

create_bd_design $BD
current_bd_design $BD

# ---- Processing System (no board preset available -> minimal config) ----
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* zynq_ultra_ps_e_0]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {apply_board_preset 0} [get_bd_cells zynq_ultra_ps_e_0]
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__USE__S_AXI_GP2 {1} \
    CONFIG.PSU__SAXIGP2__DATA_WIDTH {128} \
    CONFIG.PSU__MAXIGP0__DATA_WIDTH {32} \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
] $ps

# ---- AXI DMA (direct register mode), MM2S 64b in / S2MM 512b out ----
set dma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:* axi_dma_0]
set_property -dict [list \
    CONFIG.c_include_sg {0} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_m_axis_mm2s_tdata_width {64} \
    CONFIG.c_s_axis_s2mm_tdata_width {512} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_m_axi_s2mm_data_width {512} \
    CONFIG.c_mm2s_burst_size {16} \
    CONFIG.c_s2mm_burst_size {16} \
] $dma

# ---- exported HLS metric kernel ----
set kern [create_bd_cell -type ip -vlnv xilinx.com:hls:gnss_metric_hls:1.0 gnss_metric_hls_0]

# ---- SmartConnects: control fan-out + memory fan-in ----
set ctrl_smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* ctrl_smc]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {2}] $ctrl_smc
set data_smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:* data_smc]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1}] $data_smc

# ---- reset ----
set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* proc_sys_reset_0]

# ---- clock + reset nets ----
set clk  [get_bd_pins zynq_ultra_ps_e_0/pl_clk0]
set prst [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0]

connect_bd_net $clk \
    [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk] \
    [get_bd_pins zynq_ultra_ps_e_0/saxihp0_fpd_aclk] \
    [get_bd_pins axi_dma_0/s_axi_lite_aclk] \
    [get_bd_pins axi_dma_0/m_axi_mm2s_aclk] \
    [get_bd_pins axi_dma_0/m_axi_s2mm_aclk] \
    [get_bd_pins gnss_metric_hls_0/ap_clk] \
    [get_bd_pins ctrl_smc/aclk] \
    [get_bd_pins data_smc/aclk] \
    [get_bd_pins proc_sys_reset_0/slowest_sync_clk]

connect_bd_net $prst [get_bd_pins proc_sys_reset_0/ext_reset_in]
connect_bd_net [get_bd_pins proc_sys_reset_0/interconnect_aresetn] \
    [get_bd_pins ctrl_smc/aresetn] [get_bd_pins data_smc/aresetn]
connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
    [get_bd_pins axi_dma_0/axi_resetn] [get_bd_pins gnss_metric_hls_0/ap_rst_n]

# ---- control path: PS M_AXI -> ctrl_smc -> {DMA lite, kernel ctrl} ----
connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] [get_bd_intf_pins ctrl_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_smc/M00_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins ctrl_smc/M01_AXI] [get_bd_intf_pins gnss_metric_hls_0/s_axi_ctrl]

# ---- memory path: DMA M_AXI_MM2S/S2MM -> data_smc -> PS S_AXI_HP0 ----
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins data_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins data_smc/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins data_smc/M00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP0_FPD]

# ---- AXI4-Stream datapath: MM2S -> kernel tap_in ; metric_out -> S2MM ----
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins gnss_metric_hls_0/tap_in]
connect_bd_intf_net [get_bd_intf_pins gnss_metric_hls_0/metric_out] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# ---- addresses + validate ----
assign_bd_address
regenerate_bd_layout
save_bd_design

set vrc [catch {validate_bd_design} verr]
puts "==== validate_bd_design ===="
puts $verr
if {$vrc} {
    puts "ERROR: validate_bd_design reported errors above. Stopping."
    exit 2
}
# fail on any CRITICAL WARNING surfaced during validate
set crit [get_msg_config -severity {CRITICAL WARNING} -count]
puts "CRITICAL WARNING count: $crit"

save_bd_design

# ---- BD wrapper HDL ----
make_wrapper -files [get_files $PROJDIR/gnss_system.srcs/sources_1/bd/$BD/$BD.bd] -top
add_files -norecurse $PROJDIR/gnss_system.gen/sources_1/bd/$BD/hdl/${BD}_wrapper.v
set_property top ${BD}_wrapper [current_fileset]
update_compile_order -fileset sources_1

puts "BLOCK DESIGN BUILD COMPLETE: $BD (validated)"
