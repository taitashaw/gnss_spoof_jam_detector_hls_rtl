// ============================================================================
// simple_reg_bank.sv -- lightweight config/status register bank
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// A small memory-mapped register file holding the detector's run-time config
// and status. It is deliberately a plain {we, waddr, wdata}/{raddr, rdata}
// interface rather than full AXI4-Lite -- a thin AXI4-Lite shim (address
// decode + handshake) maps onto this directly when the design is integrated
// into a PS/PL system. See docs/hardware_bringup_notes.md.
//
// Config registers are initialized at reset to the parameter defaults (which
// gnss_top drives from gnss_top_pkg), so the datapath is fully operational with
// no host writes. Threshold/word widths are 64-bit because some thresholds
// (power, doppler) exceed 32 bits.
//
// power_prev / noise_prev are status-feedback latches: the metric engine
// returns the current window's power/noise, and on `latch_en` this bank stores
// them to feed the NEXT window (the pass-in design for power_jump -- no hidden
// engine state). Reset clears them to 0 (the documented "first window" seed).
// ============================================================================
`default_nettype none

module simple_reg_bank #(
    parameter int unsigned DEF_WINDOW_SIZE        = 1024,
    parameter longint unsigned DEF_POWER_JAM_THR  = 64'd150000000000,
    parameter int unsigned DEF_CN0_DROP_THR       = 180,
    parameter longint unsigned DEF_SYMMETRY_THR   = 64'd2000000,
    parameter longint unsigned DEF_DOPPLER_THR    = 64'd20000000000,
    parameter int unsigned DEF_SPOOF_THR          = 500,
    parameter int unsigned DEF_JAM_THR            = 500,
    parameter int unsigned DEF_NCO_PHASE_INC      = 262144,
    parameter int unsigned DEF_PRN_SEED           = 337
) (
    input  wire        clk,
    input  wire        rst_n,

    // simple memory-mapped write port (future AXI4-Lite write channel)
    input  wire        we,
    input  wire [3:0]  waddr,
    input  wire [63:0] wdata,

    // simple memory-mapped read port (future AXI4-Lite read channel)
    input  wire [3:0]  raddr,
    output reg  [63:0] rdata,

    // status feedback latches (engine -> bank -> next window)
    input  wire        latch_en,
    input  wire [47:0] latch_power,
    input  wire [31:0] latch_noise,

    // decoded config outputs to the datapath
    output wire [31:0] window_size,
    output wire [47:0] power_jam_threshold,
    output wire [31:0] cn0_drop_threshold,
    output wire [47:0] symmetry_threshold,
    output wire [47:0] doppler_energy_threshold,
    output wire [31:0] spoof_score_threshold,
    output wire [31:0] jam_score_threshold,
    output wire [31:0] nco_phase_inc,
    output wire [31:0] prn_seed,
    output wire [31:0] control,
    output wire [31:0] status,
    output wire [47:0] power_prev,
    output wire [31:0] noise_prev
);
    // Register address map (also the future AXI4-Lite offsets, x8 bytes):
    localparam [3:0] A_WINDOW   = 4'd0;
    localparam [3:0] A_PWRJAM   = 4'd1;
    localparam [3:0] A_CN0DROP  = 4'd2;
    localparam [3:0] A_SYM      = 4'd3;
    localparam [3:0] A_DOPP     = 4'd4;
    localparam [3:0] A_SPOOF    = 4'd5;
    localparam [3:0] A_JAM      = 4'd6;
    localparam [3:0] A_PHASEINC = 4'd7;
    localparam [3:0] A_PRNSEED  = 4'd8;
    localparam [3:0] A_CONTROL  = 4'd9;
    localparam [3:0] A_STATUS   = 4'd10;
    localparam [3:0] A_PWRPREV  = 4'd11;
    localparam [3:0] A_NOISEPREV= 4'd12;

    reg [63:0] regs [0:15];

    assign window_size              = regs[A_WINDOW][31:0];
    assign power_jam_threshold      = regs[A_PWRJAM][47:0];
    assign cn0_drop_threshold       = regs[A_CN0DROP][31:0];
    assign symmetry_threshold       = regs[A_SYM][47:0];
    assign doppler_energy_threshold = regs[A_DOPP][47:0];
    assign spoof_score_threshold    = regs[A_SPOOF][31:0];
    assign jam_score_threshold      = regs[A_JAM][31:0];
    assign nco_phase_inc            = regs[A_PHASEINC][31:0];
    assign prn_seed                 = regs[A_PRNSEED][31:0];
    assign control                  = regs[A_CONTROL][31:0];
    assign status                   = regs[A_STATUS][31:0];
    assign power_prev               = regs[A_PWRPREV][47:0];
    assign noise_prev               = regs[A_NOISEPREV][31:0];

    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 16; i = i + 1) regs[i] <= 64'd0;
            regs[A_WINDOW]   <= DEF_WINDOW_SIZE;
            regs[A_PWRJAM]   <= DEF_POWER_JAM_THR;
            regs[A_CN0DROP]  <= DEF_CN0_DROP_THR;
            regs[A_SYM]      <= DEF_SYMMETRY_THR;
            regs[A_DOPP]     <= DEF_DOPPLER_THR;
            regs[A_SPOOF]    <= DEF_SPOOF_THR;
            regs[A_JAM]      <= DEF_JAM_THR;
            regs[A_PHASEINC] <= DEF_NCO_PHASE_INC;
            regs[A_PRNSEED]  <= DEF_PRN_SEED;
            regs[A_CONTROL]  <= 64'd1; // bit0 = enable
            regs[A_STATUS]   <= 64'd0;
            regs[A_PWRPREV]  <= 64'd0;
            regs[A_NOISEPREV]<= 64'd0;
        end else begin
            // host write (config)
            if (we) regs[waddr] <= wdata;
            // status feedback latch from the engine (next-window power/noise)
            if (latch_en) begin
                regs[A_PWRPREV]   <= {16'd0, latch_power};
                regs[A_NOISEPREV] <= {32'd0, latch_noise};
            end
        end
    end

    always @(*) rdata = regs[raddr];
endmodule

`default_nettype wire
