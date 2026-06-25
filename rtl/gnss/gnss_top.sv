// ============================================================================
// gnss_top.sv -- GNSS spoof/jam detector top-level integration
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
//   AXIS I/Q in -> axis_skid_buffer -> nco_mixer -> prn_lfsr_gen / e-p-l tap
//               -> gnss_metric_hls_model (or exported HLS IP) -> gnss_alert_packer
//               -> axis_latency_counter -> AXIS metrics out
//
// Reset polarity: everything here is active-low rst_n. The future Vitis-HLS
// exported metric IP uses ap_rst (active-high); the single documented adapter is
// `wire hls_rst = ~rst_n;` below -- the only place polarity is reconciled. When
// the exported IP replaces gnss_metric_hls_model (one-line switch in
// vivado/compile_order.tcl) wire its ap_rst to hls_rst.
//
// The reg bank supplies run-time thresholds / phase_inc / prn_seed and holds the
// power_prev/noise_prev latches; the metric engine returns the current window's
// power/noise which are latched on the engine's output handshake to feed the
// next window (pass-in design, no hidden engine state).
// ============================================================================
`default_nettype none

module gnss_top
    import gnss_top_pkg::*;
(
    input  wire        clk,
    input  wire        rst_n,

    // raw I/Q in: tdata[31:16]=I s16, tdata[15:0]=Q s16
    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tlast,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,

    // packed metrics out (METRIC_W bits, one beat/packet, tlast=1)
    output wire [METRIC_W-1:0] m_axis_tdata,
    output wire                m_axis_tlast,
    output wire                m_axis_tvalid,
    input  wire                m_axis_tready,

    // optional host config write port (future AXI4-Lite); leave tied off to use
    // the reset-default configuration
    input  wire        cfg_we,
    input  wire [3:0]  cfg_waddr,
    input  wire [63:0] cfg_wdata,

    // observability
    output wire [31:0] dbg_out_packets,
    output wire [31:0] dbg_backpr_cycles,
    output wire [31:0] dbg_latency_first
);
    // single documented reset-polarity adapter for the future HLS IP
    wire hls_rst = ~rst_n; /* verilator lint_off UNUSED */ wire _unused_hls_rst = hls_rst;

    // ---- reg bank: config + status latches ----
    wire [31:0] window_size, cn0_drop_threshold, spoof_score_threshold, jam_score_threshold;
    wire [47:0] power_jam_threshold, symmetry_threshold, doppler_energy_threshold;
    wire [31:0] nco_phase_inc, prn_seed, control, status;
    wire [47:0] power_prev; wire [31:0] noise_prev;
    wire        latch_en; wire [47:0] latch_power; wire [31:0] latch_noise;

    simple_reg_bank u_regs (
        .clk(clk), .rst_n(rst_n),
        .we(cfg_we), .waddr(cfg_waddr), .wdata(cfg_wdata),
        .raddr(4'd0), .rdata(/*unused*/),
        .latch_en(latch_en), .latch_power(latch_power), .latch_noise(latch_noise),
        .window_size(window_size),
        .power_jam_threshold(power_jam_threshold),
        .cn0_drop_threshold(cn0_drop_threshold),
        .symmetry_threshold(symmetry_threshold),
        .doppler_energy_threshold(doppler_energy_threshold),
        .spoof_score_threshold(spoof_score_threshold),
        .jam_score_threshold(jam_score_threshold),
        .nco_phase_inc(nco_phase_inc),
        .prn_seed(prn_seed),
        .control(control), .status(status),
        .power_prev(power_prev), .noise_prev(noise_prev)
    );

    // ---- input skid buffer ----
    wire [31:0] iq_tdata; wire iq_tlast, iq_tvalid, iq_tready;
    axis_skid_buffer #(.DATA_WIDTH(32)) u_in_skid (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(s_axis_tdata), .s_axis_tlast(s_axis_tlast),
        .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready),
        .m_axis_tdata(iq_tdata), .m_axis_tlast(iq_tlast),
        .m_axis_tvalid(iq_tvalid), .m_axis_tready(iq_tready)
    );

    // ---- NCO mixer ----
    wire [31:0] mix_tdata; wire mix_tlast, mix_tvalid, mix_tready;
    nco_mixer u_mixer (
        .clk(clk), .rst_n(rst_n), .phase_inc(nco_phase_inc),
        .s_axis_tdata(iq_tdata), .s_axis_tlast(iq_tlast),
        .s_axis_tvalid(iq_tvalid), .s_axis_tready(iq_tready),
        .m_axis_tdata(mix_tdata), .m_axis_tlast(mix_tlast),
        .m_axis_tvalid(mix_tvalid), .m_axis_tready(mix_tready)
    );

    // ---- PRN + early/prompt/late tap ----
    wire prn_advance, prn_restart;
    wire signed [1:0] chip_e, chip_p, chip_l;
    prn_lfsr_gen u_prn (
        .clk(clk), .rst_n(rst_n), .seed(prn_seed),
        .advance(prn_advance), .restart(prn_restart),
        .chip_e(chip_e), .chip_p(chip_p), .chip_l(chip_l)
    );

    wire [TAP_W-1:0] tap_tdata; wire tap_tlast, tap_tvalid, tap_tready;
    early_prompt_late_tap u_tap (
        .clk(clk), .rst_n(rst_n),
        .s_mixed_tdata(mix_tdata), .s_mixed_tlast(mix_tlast),
        .s_mixed_tvalid(mix_tvalid), .s_mixed_tready(mix_tready),
        .prn_advance(prn_advance), .prn_restart(prn_restart),
        .chip_e(chip_e), .chip_p(chip_p), .chip_l(chip_l),
        .m_tap_tdata(tap_tdata), .m_tap_tlast(tap_tlast),
        .m_tap_tvalid(tap_tvalid), .m_tap_tready(tap_tready)
    );

    // ---- metric engine (behavioral stand-in for the exported HLS IP) ----
    wire        me_valid, me_ready;
    wire [31:0] me_window_id, me_noise, me_cn0, me_cp, me_ce, me_cl, me_sym, me_spoof, me_jam, me_scnt;
    wire [47:0] me_power, me_dopp, me_pjump;
    gnss_metric_hls_model u_engine (
        .clk(clk), .rst_n(rst_n),
        .s_tap_tdata(tap_tdata), .s_tap_tlast(tap_tlast),
        .s_tap_tvalid(tap_tvalid), .s_tap_tready(tap_tready),
        .power_prev(power_prev), .noise_prev(noise_prev),
        .m_valid(me_valid), .m_ready(me_ready),
        .window_id(me_window_id), .power_estimate(me_power), .noise_estimate(me_noise),
        .cn0_proxy(me_cn0), .corr_prompt(me_cp), .corr_early(me_ce), .corr_late(me_cl),
        .symmetry_error(me_sym), .doppler_energy(me_dopp), .power_jump_metric(me_pjump),
        .spoof_score(me_spoof), .jam_score(me_jam), .sample_count(me_scnt)
    );

    // latch current power/noise on the engine's output handshake (-> next window)
    assign latch_en    = me_valid && me_ready;
    assign latch_power = me_power;
    assign latch_noise = me_noise;

    // ---- latency counter (input I/Q first beat -> metrics out tlast) ----
    wire [31:0] lat_first, lat_total, lat_window, lat_live;
    axis_latency_counter u_lat (
        .clk(clk), .rst_n(rst_n),
        .in_valid(s_axis_tvalid), .in_ready(s_axis_tready),
        .out_valid(m_axis_tvalid), .out_ready(m_axis_tready), .out_last(m_axis_tlast),
        .latency_first(lat_first), .latency_total(lat_total),
        .window_cycles(lat_window), .live_cycles(lat_live)
    );
    assign dbg_latency_first = lat_first;

    // ---- alert packer ----
    wire [METRIC_W-1:0] pk_tdata; wire pk_tlast, pk_tvalid, pk_tready;
    gnss_alert_packer u_packer (
        .clk(clk), .rst_n(rst_n),
        .s_valid(me_valid), .s_ready(me_ready),
        .window_id(me_window_id), .power_estimate(me_power), .noise_estimate(me_noise),
        .cn0_proxy(me_cn0), .corr_prompt(me_cp), .corr_early(me_ce), .corr_late(me_cl),
        .symmetry_error(me_sym), .doppler_energy(me_dopp), .power_jump_metric(me_pjump),
        .spoof_score(me_spoof), .jam_score(me_jam), .sample_count(me_scnt),
        .window_size(window_size),
        .power_jam_threshold(power_jam_threshold), .cn0_drop_threshold(cn0_drop_threshold),
        .symmetry_threshold(symmetry_threshold), .doppler_energy_threshold(doppler_energy_threshold),
        .spoof_score_threshold(spoof_score_threshold), .jam_score_threshold(jam_score_threshold),
        .latency_cycles(lat_live),
        .m_axis_tdata(pk_tdata), .m_axis_tlast(pk_tlast),
        .m_axis_tvalid(pk_tvalid), .m_axis_tready(pk_tready)
    );

    // ---- output skid buffer ----
    axis_skid_buffer #(.DATA_WIDTH(METRIC_W)) u_out_skid (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(pk_tdata), .s_axis_tlast(pk_tlast),
        .s_axis_tvalid(pk_tvalid), .s_axis_tready(pk_tready),
        .m_axis_tdata(m_axis_tdata), .m_axis_tlast(m_axis_tlast),
        .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready)
    );

    // ---- observability counters ----
    wire [31:0] in_beats, out_beats, in_packets, out_packets, stall_cycles, backpr_cycles, malformed_pkts;
    axis_packet_counter #(.EXPECTED_LEN(1)) u_pktcnt (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_axis_tvalid), .s_ready(s_axis_tready), .s_last(s_axis_tlast),
        .m_valid(m_axis_tvalid), .m_ready(m_axis_tready), .m_last(m_axis_tlast),
        .in_beats(in_beats), .out_beats(out_beats),
        .in_packets(in_packets), .out_packets(out_packets),
        .stall_cycles(stall_cycles), .backpr_cycles(backpr_cycles),
        .malformed_pkts(malformed_pkts)
    );
    assign dbg_out_packets   = out_packets;
    assign dbg_backpr_cycles = backpr_cycles;

    // ---- simulation-only protocol checkers (empty without +define+SIM_ASSERT) ----
    axis_protocol_checker #(.DATA_WIDTH(32), .NAME("iq_in")) chk_in (
        .clk(clk), .rst_n(rst_n), .tdata(s_axis_tdata), .tlast(s_axis_tlast),
        .tvalid(s_axis_tvalid), .tready(s_axis_tready));
    axis_protocol_checker #(.DATA_WIDTH(METRIC_W), .NAME("metrics_out")) chk_out (
        .clk(clk), .rst_n(rst_n), .tdata(m_axis_tdata), .tlast(m_axis_tlast),
        .tvalid(m_axis_tvalid), .tready(m_axis_tready));
endmodule

`default_nettype wire
