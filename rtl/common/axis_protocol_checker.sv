// ============================================================================
// axis_protocol_checker.sv -- simulation-only AXI4-Stream assertions
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Binds concurrent SVA to an AXIS channel to catch protocol violations during
// XSim. ALL assertions are guarded by `ifdef SIM_ASSERT so that default
// elaboration (without +define+SIM_ASSERT) compiles to an empty module and
// nothing is checked in synthesis. Enable in XSim with: xelab -d SIM_ASSERT
//
// Checked properties (while not in reset):
//   1. TDATA/TLAST stable while TVALID && !TREADY  (no mid-stall data change)
//   2. TVALID not dropped before a handshake        (no VALID withdrawal)
//   3. reset clears TVALID
//   4. no X on TVALID/TREADY
// ============================================================================
`default_nettype none

module axis_protocol_checker #(
    parameter int DATA_WIDTH = 32,
    parameter     NAME       = "axis"
) (
    input wire                  clk,
    input wire                  rst_n,
    input wire [DATA_WIDTH-1:0] tdata,
    input wire                  tlast,
    input wire                  tvalid,
    input wire                  tready
);
`ifdef SIM_ASSERT
    // 1. data/last stable during a stall (valid held, ready low)
    property p_data_stable;
        @(posedge clk) disable iff (!rst_n)
            (tvalid && !tready) |=> ($stable(tdata) && $stable(tlast));
    endproperty
    a_data_stable : assert property (p_data_stable)
        else $error("%s: TDATA/TLAST changed while TVALID && !TREADY", NAME);

    // 2. valid must not be withdrawn before the handshake completes
    property p_valid_held;
        @(posedge clk) disable iff (!rst_n)
            (tvalid && !tready) |=> tvalid;
    endproperty
    a_valid_held : assert property (p_valid_held)
        else $error("%s: TVALID deasserted before handshake", NAME);

    // 3. reset clears valid (checked on the cycle reset is low)
    a_reset_clears : assert property (
        @(posedge clk) (!rst_n) |-> (tvalid == 1'b0) || $isunknown(tvalid))
        else $error("%s: TVALID asserted during reset", NAME);

    // 4. no unknown on control signals out of reset
    property p_no_x;
        @(posedge clk) disable iff (!rst_n)
            (!$isunknown(tvalid) && !$isunknown(tready));
    endproperty
    a_no_x : assert property (p_no_x)
        else $error("%s: X/Z on TVALID/TREADY", NAME);
`endif
endmodule

`default_nettype wire
