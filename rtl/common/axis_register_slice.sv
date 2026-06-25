// ============================================================================
// axis_register_slice.sv -- one-deep registered AXI4-Stream stage
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Registers the forward path (tdata/tlast/tvalid). m_axis_tvalid is a register
// and never depends combinationally on m_axis_tready. s_axis_tready is allowed
// to depend on m_axis_tready (backward path) -- only the VALID/TDATA forward
// path is registered here. For a buffer that also registers the backward path
// use axis_skid_buffer (depth-2).
//
// tdata/tlast are held stable while tvalid && !tready (the slot only reloads on
// an accepted upstream beat). Reset is active-low.
// ============================================================================
`default_nettype none

module axis_register_slice #(
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
    reg                  vld;
    reg [DATA_WIDTH-1:0] data;
    reg                  last;

    assign m_axis_tvalid = vld;
    assign m_axis_tdata  = data;
    assign m_axis_tlast  = last;

    // We can accept a new beat when the slot is empty or being drained.
    assign s_axis_tready = !vld || m_axis_tready;

    always @(posedge clk) begin
        if (!rst_n) begin
            vld  <= 1'b0;
            data <= '0;
            last <= 1'b0;
        end else if (s_axis_tready) begin
            vld  <= s_axis_tvalid;
            data <= s_axis_tdata;
            last <= s_axis_tlast;
        end
    end
endmodule

`default_nettype wire
