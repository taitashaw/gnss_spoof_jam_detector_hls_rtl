# ============================================================================
# compile_order.tcl -- ordered source list for the XSim / Vivado flow
# Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
#
# gnss_top_pkg.sv MUST compile first (package), then rtl/common, then rtl/gnss,
# then the testbench support + tops. Sourced by vivado/run_xsim.tcl and mirrored
# by scripts/run_xsim.sh.
# ============================================================================

# Single place to change the target part (HLS uses the same default).
set PART xczu7ev-ffvc1156-2-e

# repo root relative to this file
set REPO [file normalize [file join [file dirname [info script]] ..]]

set PKG_SRCS [list \
    $REPO/rtl/gnss/gnss_top_pkg.sv \
]

set RTL_COMMON [list \
    $REPO/rtl/common/axis_skid_buffer.sv \
    $REPO/rtl/common/axis_register_slice.sv \
    $REPO/rtl/common/axis_packet_counter.sv \
    $REPO/rtl/common/axis_latency_counter.sv \
    $REPO/rtl/common/axis_protocol_checker.sv \
    $REPO/rtl/common/simple_reg_bank.sv \
]

set RTL_GNSS [list \
    $REPO/rtl/gnss/nco_mixer.sv \
    $REPO/rtl/gnss/prn_lfsr_gen.sv \
    $REPO/rtl/gnss/early_prompt_late_tap.sv \
    \
    $REPO/rtl/gnss/gnss_metric_hls_model.sv \
    \
    $REPO/rtl/gnss/gnss_alert_packer.sv \
    $REPO/rtl/gnss/gnss_top.sv \
]

# --------------------------------------------------------------------------
# ONE-LINE SWAP: to use the Vitis-HLS-exported metric IP instead of the
# behavioral stand-in, comment out the gnss_metric_hls_model.sv line above and
# add the exported RTL here (typically hls/.../impl/ip or the *_v1_0 sources),
# then wire its ap_rst to gnss_top's `hls_rst` (= ~rst_n). Example:
#   # remove: $REPO/rtl/gnss/gnss_metric_hls_model.sv
#   lappend RTL_GNSS $REPO/hls/vitis_hls/gnss_metric_hls_prj/sol1/impl/ip/hdl/verilog/gnss_metric_hls.v
# --------------------------------------------------------------------------

set TB_SRCS [list \
    $REPO/tb/axis_bfm.sv \
    $REPO/tb/gnss_scoreboard.sv \
    $REPO/tb/tb_gnss_top.sv \
    $REPO/tb/tb_axis_skid_buffer.sv \
    $REPO/tb/tb_nco_mixer.sv \
    $REPO/tb/tb_prn_lfsr_gen.sv \
]

set ALL_SRCS [concat $PKG_SRCS $RTL_COMMON $RTL_GNSS $TB_SRCS]
