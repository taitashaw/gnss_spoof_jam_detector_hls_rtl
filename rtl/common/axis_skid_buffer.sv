// ============================================================================
// axis_skid_buffer.sv -- full-throughput AXI4-Stream skid buffer (depth-2 FIFO)
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// A depth-2 register FIFO. This is the cleanest provably-correct skid buffer:
//   * s_axis_tready = !full  -- depends only on the registered occupancy count,
//                               NOT combinationally on m_axis_tready.
//   * m_axis_tvalid = !empty -- registered occupancy; does NOT depend
//                               combinationally on m_axis_tready (the key AXIS
//                               rule). Sticky VALID: once asserted it stays
//                               asserted until the beat is accepted.
//   * m_axis_tdata / tlast come from the read entry and are STABLE while
//     tvalid && !tready, because the read pointer only advances on an accepted
//     handshake.
//   * Full throughput: when occupancy == 1 it can accept and emit in the same
//     cycle, so back-to-back transfers run at one beat/clock.
//
// Reset is active-low (rst_n). On reset the FIFO is emptied (valid deasserted).
// ============================================================================
`default_nettype none

module axis_skid_buffer #(
    parameter int DATA_WIDTH = 32
) (
    input  wire                  clk,
    input  wire                  rst_n,

    input  wire [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tlast,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,

    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire                  m_axis_tlast,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready
);
    localparam int W = DATA_WIDTH + 1; // {tlast, tdata}

    reg [W-1:0] mem [0:1];
    reg         wptr;
    reg         rptr;
    reg [1:0]   count;

    wire full  = (count == 2'd2);
    wire empty = (count == 2'd0);

    assign s_axis_tready = !full;
    assign m_axis_tvalid = !empty;
    assign {m_axis_tlast, m_axis_tdata} = mem[rptr];

    wire do_wr = s_axis_tvalid && s_axis_tready;
    wire do_rd = m_axis_tvalid && m_axis_tready;

    always @(posedge clk) begin
        if (!rst_n) begin
            wptr  <= 1'b0;
            rptr  <= 1'b0;
            count <= 2'd0;
        end else begin
            if (do_wr) begin
                mem[wptr] <= {s_axis_tlast, s_axis_tdata};
                wptr      <= wptr + 1'b1;
            end
            if (do_rd) begin
                rptr <= rptr + 1'b1;
            end
            case ({do_wr, do_rd})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule

`default_nettype wire
