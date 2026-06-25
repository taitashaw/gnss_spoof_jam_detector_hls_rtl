// ============================================================================
// nco_mixer.sv -- streaming NCO + complex mixer (RTL front-end stage 1)
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Consumes raw signed I/Q (tdata[31:16]=I s16, tdata[15:0]=Q s16) and produces
// NCO-mixed I/Q in the same packing. Mixing follows the project spec formula:
//
//   mixed_I = sat16((I*cos - Q*sin) >> NCO_SCALE)
//   mixed_Q = sat16((I*sin + Q*cos) >> NCO_SCALE)
//   cos = LUT[(idx + QUARTER) % SIZE], sin = LUT[idx]
//   idx = (phase >> NCO_PHASE_SHIFT) % NCO_LUT_SIZE
//
// The phase accumulator advances ONLY on an accepted input handshake and is
// reset to 0 at each window boundary (the accepted beat with tlast), so the
// per-window phase matches the golden reference model exactly. The cos/sin come
// from the shared Q14 LUT in gnss_top_pkg (numerically identical to the C and
// Python front-ends). Products are saturated to s16.
//
// Output VALID is registered and never depends combinationally on m_axis_tready
// (s_ready = !m_valid || m_ready breaks only the backward path). Active-low rst.
// ============================================================================
`default_nettype none

module nco_mixer
    import gnss_top_pkg::*;
(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] phase_inc,   // from reg bank (default NCO_PHASE_INC_DEFAULT)

    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tlast,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,

    output reg  [31:0] m_axis_tdata,
    output reg         m_axis_tlast,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready
);
    localparam int unsigned PHASE_MASK = (1 << NCO_PHASE_ACC_BITS) - 1;

    reg [NCO_PHASE_ACC_BITS-1:0] phase;

    assign s_axis_tready = !m_axis_tvalid || m_axis_tready;
    wire in_fire = s_axis_tvalid && s_axis_tready;

    // current-phase LUT lookups (combinational)
    wire [5:0] idx_sin = phase[NCO_PHASE_SHIFT +: 6];
    wire [5:0] idx_cos = idx_sin + NCO_QUARTER[5:0];
    wire signed [15:0] s_lut = nco_sin(idx_sin);
    wire signed [15:0] c_lut = nco_sin(idx_cos);

    wire signed [15:0] in_i = s_axis_tdata[31:16];
    wire signed [15:0] in_q = s_axis_tdata[15:0];

    // products (s16*s16 -> s32) and combine (>> NCO_SCALE)
    wire signed [33:0] mix_i_raw = ($signed(in_i) * c_lut) - ($signed(in_q) * s_lut);
    wire signed [33:0] mix_q_raw = ($signed(in_i) * s_lut) + ($signed(in_q) * c_lut);
    wire signed [33:0] mix_i_sh  = mix_i_raw >>> NCO_SCALE;
    wire signed [33:0] mix_q_sh  = mix_q_raw >>> NCO_SCALE;

    function automatic signed [15:0] sat16(input signed [33:0] v);
        if (v > IQ_SAT_MAX)      sat16 = IQ_SAT_MAX;
        else if (v < IQ_SAT_MIN) sat16 = IQ_SAT_MIN;
        else                     sat16 = v[15:0];
    endfunction

    wire signed [15:0] mixed_i = sat16(mix_i_sh);
    wire signed [15:0] mixed_q = sat16(mix_q_sh);

    always @(posedge clk) begin
        if (!rst_n) begin
            phase         <= '0;
            m_axis_tvalid <= 1'b0;
            m_axis_tdata  <= '0;
            m_axis_tlast  <= 1'b0;
        end else if (s_axis_tready) begin
            m_axis_tvalid <= s_axis_tvalid;
            if (s_axis_tvalid) begin
                m_axis_tdata <= {mixed_i, mixed_q};
                m_axis_tlast <= s_axis_tlast;
                // advance phase, reset to 0 at the window boundary
                phase <= s_axis_tlast ? '0
                                      : (phase + phase_inc[NCO_PHASE_ACC_BITS-1:0]) & PHASE_MASK[NCO_PHASE_ACC_BITS-1:0];
            end
        end
    end
endmodule

`default_nettype wire
