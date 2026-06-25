// ============================================================================
// prn_lfsr_gen.sv -- deterministic PRN-like LFSR with E/P/L tap outputs
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// 10-bit Fibonacci LFSR, primitive polynomial x^10 + x^7 + 1, producing a
// deterministic +/-1 chip sequence. This is PRN-LIKE for the anomaly demo; it
// is NOT a certified GPS C/A code generator unless the full Gold-code pair is
// implemented (see docs/known_limitations.md).
//
// The module exposes three aligned chip taps so the early_prompt_late_tap can
// pair them with a one-sample-delayed mixed stream (prompt aligned, early one
// sample ahead, late one sample behind):
//
//   chip_e = g[n]   (early  = newest, combinational from the current state)
//   chip_p = g[n-1] (prompt = registered)
//   chip_l = g[n-2] (late   = registered)
//
// Chips are signed: +1 (sign bit 1) or -1 (sign bit 0). The LFSR advances ONLY
// on `advance` (an accepted handshake) and reloads `seed` on `restart` (window
// boundary), so each window reproduces the golden reference's per-window code.
// Reset is active-low and deterministic (state -> seed, taps -> +1 edge fill).
// ============================================================================
`default_nettype none

module prn_lfsr_gen
    import gnss_top_pkg::*;
(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] seed,
    input  wire        advance,   // step the code (accepted handshake)
    input  wire        restart,   // reload seed for a new window

    output wire signed [1:0] chip_e,  // +1 / -1
    output wire signed [1:0] chip_p,
    output wire signed [1:0] chip_l
);
    reg [PRN_LFSR_WIDTH-1:0] state;
    reg signed [1:0]         prompt_r;
    reg signed [1:0]         late_r;

    wire [PRN_LFSR_WIDTH-1:0] seed_masked =
        (seed[PRN_LFSR_WIDTH-1:0] == '0) ? PRN_SEED_DEFAULT[PRN_LFSR_WIDTH-1:0]
                                         : seed[PRN_LFSR_WIDTH-1:0];

    // current chip (combinational) from the LSB of the current state
    wire signed [1:0] early_c = state[0] ? 2'sd1 : -2'sd1;

    // Fibonacci feedback: bit PRN_TAP_A xor bit PRN_TAP_B
    wire fb = state[PRN_TAP_A] ^ state[PRN_TAP_B];
    wire [PRN_LFSR_WIDTH-1:0] next_state = {state[PRN_LFSR_WIDTH-2:0], fb};

    assign chip_e = early_c;
    assign chip_p = prompt_r;
    assign chip_l = late_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= PRN_SEED_DEFAULT[PRN_LFSR_WIDTH-1:0];
            prompt_r <= 2'sd1;
            late_r   <= 2'sd1;
        end else if (restart) begin
            // window boundary: reload seed, edge-fill the delayed taps
            state    <= seed_masked;
            prompt_r <= 2'sd1;
            late_r   <= 2'sd1;
        end else if (advance) begin
            late_r   <= prompt_r;
            prompt_r <= early_c;
            state    <= next_state;
        end
    end
endmodule

`default_nettype wire
