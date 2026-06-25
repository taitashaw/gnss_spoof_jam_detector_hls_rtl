// ============================================================================
// axis_bfm.sv -- reusable AXI4-Stream throttle/backpressure engine + monitor
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// A small, seeded, reproducible flow-control generator used by the testbenches
// as both a source throttle (gate TVALID) and a sink backpressure source (drive
// TREADY). One instance == one channel side. The `enable` output is the
// per-cycle allow signal; the TB ANDs it into TVALID (source) or uses it as
// TREADY (sink). It also monitors accepted beats for reporting.
//
// MODE (string plusarg-friendly):
//   "none"   : enable always 1 (no throttling)
//   "random" : enable 1 with probability PCT% (seeded LCG)
//   "burst"  : alternating run-of-N enabled / run-of-N stalled
//
// SEED makes the random/burst pattern reproducible (default 0xC0FFEE).
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module axis_bfm #(
    parameter int PCT      = 60,
    parameter int BURST    = 8
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [1:0]  mode,     // 0=none, 1=random, 2=burst
    input  wire [31:0] seed,
    input  wire        beat,     // accepted handshake (valid && ready) to monitor
    output reg         enable,
    output reg [31:0]  beat_count
);
    reg [31:0] lfsr;
    reg [31:0] burst_cnt;
    reg        burst_phase;

    function automatic [31:0] nxt(input [31:0] s);
        nxt = (s * 32'd1664525 + 32'd1013904223);
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            lfsr        <= (seed == 0) ? 32'hC0FFEE : seed;
            burst_cnt   <= 0;
            burst_phase <= 1'b1;
            enable      <= 1'b1;
            beat_count  <= 32'd0;
        end else begin
            lfsr <= nxt(lfsr);
            case (mode)
                2'd0: enable <= 1'b1;
                2'd1: enable <= ((lfsr % 100) < PCT);
                2'd2: begin
                    if (burst_cnt + 1 >= BURST) begin
                        burst_cnt   <= 0;
                        burst_phase <= ~burst_phase;
                        enable      <= ~burst_phase;
                    end else begin
                        burst_cnt <= burst_cnt + 1;
                        enable    <= burst_phase;
                    end
                end
                default: enable <= 1'b1;
            endcase
            if (beat) beat_count <= beat_count + 1;
        end
    end
endmodule

`default_nettype wire
