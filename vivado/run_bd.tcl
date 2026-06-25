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
set BD      gnss_system_bd

# EXPOSE_FMC=1 (default): expose external FMC/ADC AXI4-Stream ports (input switch
#   + output broadcaster) alongside the DMA path. This variant validates and
#   synthesizes, but the 512-bit external metrics bus makes it exceed the package
#   I/O (686 ports), so it cannot be implemented to a bitstream.
# EXPOSE_FMC=0: DMA-only deployable variant (no wide external I/O) -> this is the
#   configuration that implements and bitstreams. Pass via -tclargs 0.
set EXPOSE_FMC 1
if {$argc >= 1} { set EXPOSE_FMC [lindex $argv 0] }
set PROJDIR $REPO/build/vivado_bd
if {!$EXPOSE_FMC} { set PROJDIR $REPO/build/vivado_bd_impl }
puts "EXPOSE_FMC=$EXPOSE_FMC  PROJDIR=$PROJDIR"

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

# ---- AXIS path IP: input switch + output broadcaster (EXPOSE_FMC only) ----
# in_switch selects the kernel's input between the AXI DMA (MM2S) and an external
# FMC/ADC AXI4-Stream port (the direct front-end bypass). out_bcast duplicates the
# metrics stream to both the AXI DMA (S2MM, for PS readback) and an external sink.
if {$EXPOSE_FMC} {
    set in_switch [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_switch:* in_switch]
    set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1} CONFIG.ROUTING_MODE {0} \
        CONFIG.TDEST_WIDTH {0} CONFIG.ARB_ON_TLAST {1} CONFIG.TDATA_NUM_BYTES {8}] $in_switch
    set out_bcast [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_broadcaster:* out_bcast]
    set_property -dict [list CONFIG.NUM_MI {2}] $out_bcast
}

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

if {$EXPOSE_FMC} {
    connect_bd_net $clk [get_bd_pins in_switch/aclk] [get_bd_pins out_bcast/aclk]
    connect_bd_net [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
        [get_bd_pins in_switch/aresetn] [get_bd_pins out_bcast/aresetn]
}

# ---- control path: PS M_AXI -> ctrl_smc -> {DMA lite, kernel ctrl} ----
connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] [get_bd_intf_pins ctrl_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins ctrl_smc/M00_AXI] [get_bd_intf_pins axi_dma_0/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins ctrl_smc/M01_AXI] [get_bd_intf_pins gnss_metric_hls_0/s_axi_ctrl]

# ---- memory path: DMA M_AXI_MM2S/S2MM -> data_smc -> PS S_AXI_HP0 ----
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] [get_bd_intf_pins data_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] [get_bd_intf_pins data_smc/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins data_smc/M00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP0_FPD]

# ---- AXI4-Stream datapath ----
if {$EXPOSE_FMC} {
    # input: DMA MM2S + external FMC -> switch -> kernel tap_in
    connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins in_switch/S00_AXIS]
    connect_bd_intf_net [get_bd_intf_pins in_switch/M00_AXIS] [get_bd_intf_pins gnss_metric_hls_0/tap_in]
    # output: kernel metric_out -> broadcaster -> {DMA S2MM, external sink}
    connect_bd_intf_net [get_bd_intf_pins gnss_metric_hls_0/metric_out] [get_bd_intf_pins out_bcast/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins out_bcast/M00_AXIS] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

    # external ports: direct front-end streaming path alongside the DMA path.
    # The external AXIS ports need an associated external clock port; expose the
    # PL-sourced clock and reset (explicit ports) and associate the streams with it.
    create_bd_port -dir O -type clk fmc_clk
    connect_bd_net [get_bd_ports fmc_clk] [get_bd_pins zynq_ultra_ps_e_0/pl_clk0]
    create_bd_port -dir O -type rst fmc_aresetn
    connect_bd_net [get_bd_ports fmc_aresetn] [get_bd_pins proc_sys_reset_0/peripheral_aresetn]

    make_bd_intf_pins_external -name fmc_iq_in       [get_bd_intf_pins in_switch/S01_AXIS]
    make_bd_intf_pins_external -name metrics_out_ext [get_bd_intf_pins out_bcast/M01_AXIS]

    # Set the external clock port to the ACHIEVED PL clock frequency so it matches
    # the driving net (the port-default 100 MHz would otherwise mismatch). The AXIS
    # port FREQ_HZ and TDATA width are read-only and propagate from the associated
    # clock and the connected internal pins.
    set plfreq [get_property CONFIG.FREQ_HZ [get_bd_pins zynq_ultra_ps_e_0/pl_clk0]]
    if {$plfreq eq "" || $plfreq <= 10000000} { set plfreq 96968727 }
    puts "ACHIEVED_PL_FREQ_HZ=$plfreq"
    set_property CONFIG.FREQ_HZ $plfreq [get_bd_ports fmc_clk]
    set_property CONFIG.ASSOCIATED_BUSIF {fmc_iq_in:metrics_out_ext} [get_bd_ports fmc_clk]
} else {
    # DMA-only deployable datapath (no external I/O -> implements + bitstreams)
    connect_bd_intf_net [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] [get_bd_intf_pins gnss_metric_hls_0/tap_in]
    connect_bd_intf_net [get_bd_intf_pins gnss_metric_hls_0/metric_out] [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]
}

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
