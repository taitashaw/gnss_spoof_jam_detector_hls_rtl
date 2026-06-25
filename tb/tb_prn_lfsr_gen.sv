// ============================================================================
// tb_prn_lfsr_gen.sv -- unit test: chip advances only on handshake; determinism
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Pulses `advance` with random gaps and checks the early-tap chip sequence equals
// a golden software LFSR (same polynomial/seed) -- proving the code advances
// exactly once per asserted `advance` and never on idle cycles. Then asserts
// `restart` and confirms the sequence repeats from the seed (per-window
// determinism). Reset determinism is checked implicitly by the repeat.
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_prn_lfsr_gen
    import gnss_top_pkg::*;
;
    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    logic        advance, restart;
    logic signed [1:0] chip_e, chip_p, chip_l;

    prn_lfsr_gen dut (
        .clk(clk), .rst_n(rst_n), .seed(PRN_SEED_DEFAULT),
        .advance(advance), .restart(restart),
        .chip_e(chip_e), .chip_p(chip_p), .chip_l(chip_l));

    // golden software LFSR
    int unsigned gstate;
    function automatic int gchip(); return (gstate & 1) ? 1 : -1; endfunction
    task automatic gstep();
        automatic int unsigned fb = ((gstate >> PRN_TAP_A) ^ (gstate >> PRN_TAP_B)) & 1;
        gstate = ((gstate << 1) | fb) & PRN_LFSR_MASK;
    endtask

    int errors = 0;
    int unsigned lf = 32'hC0FFEE;
    int seq0 [0:255];

    function automatic bit rnd();
        lf = lf*32'd1664525 + 32'd1013904223; return (lf % 100) < 55;
    endfunction

    initial begin
        advance = 0; restart = 0;
        repeat (3) @(posedge clk); rst_n = 1; @(posedge clk);

        // PASS 1: random-gap advance, compare early chip to golden
        gstate = PRN_SEED_DEFAULT;
        for (int n=0; n<256; n++) begin
            // wait random idle cycles with advance=0 (chip must NOT move)
            while (!rnd()) begin advance <= 0; @(posedge clk); end
            // sample chip the cycle we assert advance (early = current state chip)
            advance <= 1; #1;
            seq0[n] = chip_e;
            if (chip_e !== gchip()) begin
                if (errors<4) $display("  chip[%0d] dut=%0d golden=%0d", n, chip_e, gchip());
                errors++;
            end
            @(posedge clk);     // advance takes effect
            gstep();
            advance <= 0;
        end

        // PASS 2: restart -> sequence must repeat from the seed
        advance <= 0; restart <= 1; @(posedge clk); restart <= 0; @(posedge clk);
        gstate = PRN_SEED_DEFAULT;
        for (int n=0; n<256; n++) begin
            advance <= 1; #1;
            if (chip_e !== seq0[n]) begin
                if (errors<4) $display("  restart chip[%0d] dut=%0d expected=%0d", n, chip_e, seq0[n]);
                errors++;
            end
            @(posedge clk); advance <= 0;
        end

        if (errors == 0)
            $display("PASS tb_prn_lfsr_gen: chip advances only on handshake; restart is deterministic");
        else
            $display("FAIL tb_prn_lfsr_gen: %0d mismatches", errors);
        $finish;
    end
    initial begin #5_000_000; $display("FAIL tb_prn_lfsr_gen: watchdog"); $finish; end
endmodule

`default_nettype wire
