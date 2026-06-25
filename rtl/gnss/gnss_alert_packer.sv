// ============================================================================
// gnss_alert_packer.sv -- threshold compare + alert flags + final packet pack
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Consumes the metric-engine bundle, compares the metrics against the run-time
// thresholds from the reg bank, builds alert_flags (Section 4 bit map), folds in
// the measured latency_cycles from axis_latency_counter, sets packet_status, and
// packs everything into one wide AXIS metrics beat (METRIC_W bits, tlast=1).
//
//   bit0 high_power_jam : power_estimate > power_jam_threshold
//   bit1 cn0_drop       : cn0_proxy      < cn0_drop_threshold
//   bit2 corr_asymmetry : symmetry_error > symmetry_threshold
//   bit3 doppler_anomaly: doppler_energy > doppler_energy_threshold
//   bit4 spoof_high     : spoof_score    > spoof_score_threshold
//   bit5 jam_high       : jam_score      > jam_score_threshold
//   bit6 malformed      : sample_count  != window_size
//
// VALID/READY preserved: a one-deep output register; m_axis_tvalid never depends
// combinationally on m_axis_tready. Active-low reset.
// ============================================================================
`default_nettype none

module gnss_alert_packer
    import gnss_top_pkg::*;
(
    input  wire        clk,
    input  wire        rst_n,

    // metric bundle in
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [31:0] window_id,
    input  wire [47:0] power_estimate,
    input  wire [31:0] noise_estimate,
    input  wire [31:0] cn0_proxy,
    input  wire [31:0] corr_prompt,
    input  wire [31:0] corr_early,
    input  wire [31:0] corr_late,
    input  wire [31:0] symmetry_error,
    input  wire [47:0] doppler_energy,
    input  wire [47:0] power_jump_metric,
    input  wire [31:0] spoof_score,
    input  wire [31:0] jam_score,
    input  wire [31:0] sample_count,

    // thresholds + config (from reg bank)
    input  wire [31:0] window_size,
    input  wire [47:0] power_jam_threshold,
    input  wire [31:0] cn0_drop_threshold,
    input  wire [47:0] symmetry_threshold,
    input  wire [47:0] doppler_energy_threshold,
    input  wire [31:0] spoof_score_threshold,
    input  wire [31:0] jam_score_threshold,

    // measured latency (from axis_latency_counter)
    input  wire [31:0] latency_cycles,

    // packed metrics AXIS out
    output reg  [METRIC_W-1:0] m_axis_tdata,
    output reg                 m_axis_tlast,
    output reg                 m_axis_tvalid,
    input  wire                m_axis_tready
);
    assign s_ready = !m_axis_tvalid || m_axis_tready;
    wire fire = s_valid && s_ready;

    // ---- flags (combinational) ----
    wire malformed = (sample_count != window_size);
    wire [7:0] flags =
          (( power_estimate     > power_jam_threshold)      << FLAG_HIGH_POWER_JAM)
        | (( cn0_proxy          < cn0_drop_threshold)       << FLAG_CN0_DROP)
        | (({16'd0,symmetry_error} > symmetry_threshold)    << FLAG_CORR_ASYMMETRY)
        | (( doppler_energy     > doppler_energy_threshold) << FLAG_DOPPLER_ANOMALY)
        | (( spoof_score        > spoof_score_threshold)    << FLAG_SPOOF_SCORE_HIGH)
        | (( jam_score          > jam_score_threshold)      << FLAG_JAM_SCORE_HIGH)
        | (( malformed)                                     << FLAG_MALFORMED_PACKET);

    wire [7:0] status = malformed ? PKT_STATUS_MALFORMED[7:0] : PKT_STATUS_OK[7:0];

    // ---- pack ----
    function automatic logic [METRIC_W-1:0] pack_metrics();
        logic [METRIC_W-1:0] w;
        w = '0;
        w[M_WINDOW_ID_O +: 32] = window_id;
        w[M_POWER_O     +: 48] = power_estimate;
        w[M_NOISE_O     +: 32] = noise_estimate;
        w[M_CN0_O       +: 32] = cn0_proxy;
        w[M_CP_O        +: 32] = corr_prompt;
        w[M_CE_O        +: 32] = corr_early;
        w[M_CL_O        +: 32] = corr_late;
        w[M_SYM_O       +: 32] = symmetry_error;
        w[M_DOPP_O      +: 48] = doppler_energy;
        w[M_PJUMP_O     +: 48] = power_jump_metric;
        w[M_SPOOF_O     +: 32] = spoof_score;
        w[M_JAM_O       +: 32] = jam_score;
        w[M_FLAGS_O     +: 8]  = flags;
        w[M_LAT_O       +: 32] = latency_cycles;
        w[M_SCNT_O      +: 32] = sample_count;
        w[M_STATUS_O    +: 8]  = status;
        return w;
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
            m_axis_tdata  <= '0;
        end else begin
            if (m_axis_tvalid && m_axis_tready) m_axis_tvalid <= 1'b0;
            if (fire) begin
                m_axis_tdata  <= pack_metrics();
                m_axis_tlast  <= 1'b1;   // one beat = one packet
                m_axis_tvalid <= 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
