// ============================================================================
// axis_packet_counter.sv -- AXI4-Stream traffic / health monitor
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Passive monitor (taps signals; drives nothing on the stream). Counts:
//   in_beats        accepted input beats   (s_valid && s_ready)
//   out_beats       accepted output beats  (m_valid && m_ready)
//   in_packets      input packets          (in_beat && s_last)
//   out_packets     output packets         (out_beat && m_last)
//   stall_cycles    we stalled the source  (s_valid && !s_ready)
//   backpr_cycles   downstream backpressure (m_valid && !m_ready)
//   malformed_pkts  output packets whose beat length != EXPECTED_LEN
//                   (tlast misalignment); EXPECTED_LEN=0 disables the check.
//
// Reset active-low. Counters saturate-free (wrap) 32-bit; enough for sim.
// ============================================================================
`default_nettype none

module axis_packet_counter #(
    parameter int EXPECTED_LEN = 1024
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        s_valid,
    input  wire        s_ready,
    input  wire        s_last,

    input  wire        m_valid,
    input  wire        m_ready,
    input  wire        m_last,

    output reg [31:0]  in_beats,
    output reg [31:0]  out_beats,
    output reg [31:0]  in_packets,
    output reg [31:0]  out_packets,
    output reg [31:0]  stall_cycles,
    output reg [31:0]  backpr_cycles,
    output reg [31:0]  malformed_pkts
);
    wire in_beat  = s_valid && s_ready;
    wire out_beat = m_valid && m_ready;

    reg [31:0] cur_out_len;

    always @(posedge clk) begin
        if (!rst_n) begin
            in_beats       <= 32'd0;
            out_beats      <= 32'd0;
            in_packets     <= 32'd0;
            out_packets    <= 32'd0;
            stall_cycles   <= 32'd0;
            backpr_cycles  <= 32'd0;
            malformed_pkts <= 32'd0;
            cur_out_len    <= 32'd0;
        end else begin
            if (in_beat)               in_beats  <= in_beats  + 1'b1;
            if (out_beat)              out_beats <= out_beats + 1'b1;
            if (in_beat && s_last)     in_packets  <= in_packets  + 1'b1;
            if (s_valid && !s_ready)   stall_cycles  <= stall_cycles  + 1'b1;
            if (m_valid && !m_ready)   backpr_cycles <= backpr_cycles + 1'b1;

            if (out_beat) begin
                if (m_last) begin
                    out_packets <= out_packets + 1'b1;
                    cur_out_len <= 32'd0;
                    if (EXPECTED_LEN != 0 && (cur_out_len + 1'b1) != EXPECTED_LEN[31:0])
                        malformed_pkts <= malformed_pkts + 1'b1;
                end else begin
                    cur_out_len <= cur_out_len + 1'b1;
                end
            end
        end
    end
endmodule

`default_nettype wire
