// ============================================================================
// gnss_scoreboard.sv -- structural sanity checks on captured metric packets
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Watches the packed metrics output beat and checks the invariants that must
// hold for EVERY packet regardless of scenario:
//   * sample_count == WINDOW_SIZE
//   * packet_status == OK and the malformed flag is clear
//   * latency_cycles > 0
//   * reserved flag bit (7) is 0
//   * spoof_score / jam_score <= SCORE_MAX
//
// The scenario-specific golden comparison (exact alert flags + loose metric
// ranges) is done by scripts/check_gnss_results.py against the actual_metrics.txt
// the testbench writes -- this scoreboard is the in-sim structural guard. It
// raises $error (counted) on any violation and tallies packets seen.
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module gnss_scoreboard
    import gnss_top_pkg::*;
(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 valid,
    input  wire                 ready,
    input  wire [METRIC_W-1:0]  tdata,
    output reg  [31:0]          packets,
    output reg  [31:0]          errors
);
    wire        beat   = valid && ready;
    wire [31:0] scnt   = tdata[M_SCNT_O   +: 32];
    wire [7:0]  flags  = tdata[M_FLAGS_O  +: 8];
    wire [7:0]  status = tdata[M_STATUS_O +: 8];
    wire [31:0] lat    = tdata[M_LAT_O    +: 32];
    wire [31:0] spoof  = tdata[M_SPOOF_O  +: 32];
    wire [31:0] jam    = tdata[M_JAM_O    +: 32];

    always @(posedge clk) begin
        if (!rst_n) begin
            packets <= 32'd0;
            errors  <= 32'd0;
        end else if (beat) begin
            packets <= packets + 1;
            if (scnt != WINDOW_SIZE) begin
                $error("scoreboard: sample_count %0d != %0d", scnt, WINDOW_SIZE); errors <= errors + 1;
            end
            if (status != PKT_STATUS_OK) begin
                $error("scoreboard: packet_status %0d != OK", status); errors <= errors + 1;
            end
            if (flags[FLAG_MALFORMED_PACKET]) begin
                $error("scoreboard: malformed flag set"); errors <= errors + 1;
            end
            if (flags[FLAG_RESERVED]) begin
                $error("scoreboard: reserved flag bit set"); errors <= errors + 1;
            end
            if (lat == 0) begin
                $error("scoreboard: latency_cycles is zero"); errors <= errors + 1;
            end
            if (spoof > SCORE_MAX || jam > SCORE_MAX) begin
                $error("scoreboard: score exceeds SCORE_MAX"); errors <= errors + 1;
            end
        end
    end
endmodule

`default_nettype wire
