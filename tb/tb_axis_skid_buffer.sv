// ============================================================================
// tb_axis_skid_buffer.sv -- unit test: data stable + lossless under backpressure
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Drives a known incrementing sequence into axis_skid_buffer with random source
// throttling and random downstream backpressure (seeded, reproducible) and
// checks that EVERY beat comes out exactly once, in order, with no loss or
// duplication. Also checks tdata stays stable while tvalid && !tready.
//
// Run with -d SIM_ASSERT to additionally enable the protocol checker bind.
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_axis_skid_buffer;
    localparam int DW = 32;
    localparam int NBEATS = 2000;
    localparam int SEEDP = 32'hC0FFEE;

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    logic [DW-1:0] s_tdata; logic s_tlast, s_tvalid, s_tready;
    logic [DW-1:0] m_tdata; logic m_tlast, m_tvalid, m_tready;

    axis_skid_buffer #(.DATA_WIDTH(DW)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(s_tdata), .s_axis_tlast(s_tlast),
        .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .m_axis_tdata(m_tdata), .m_axis_tlast(m_tlast),
        .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready)
    );

    // golden expected value for stability + ordering checks
    int unsigned send_cnt = 0;
    int unsigned recv_cnt = 0;
    int          errors   = 0;
    int unsigned rs = SEEDP;
    int unsigned rm = SEEDP ^ 32'h12345;

    function int unsigned lcg(inout int unsigned s);
        s = (s * 32'd1664525 + 32'd1013904223);
        return s;
    endfunction

    // source: present incrementing data, throttle randomly.
    // cnt_next folds in this cycle's acceptance so the next presented value is
    // never a duplicate of the one just accepted.
    wire accept = s_tvalid && s_tready;
    wire [31:0] cnt_next = send_cnt + (accept ? 1 : 0);
    always @(posedge clk) begin
        if (!rst_n) begin
            s_tvalid <= 0; s_tdata <= 0; s_tlast <= 0; send_cnt <= 0;
        end else begin
            send_cnt <= cnt_next;
            if (!s_tvalid || accept) begin
                if (cnt_next < NBEATS && (lcg(rs) % 100 < 70)) begin
                    s_tvalid <= 1;
                    s_tdata  <= cnt_next + 1; // 1-based payload
                    s_tlast  <= (((cnt_next + 1) % 64) == 0);
                end else begin
                    s_tvalid <= 0;
                end
            end
        end
    end

    // sink: random backpressure
    always @(posedge clk) begin
        if (!rst_n) m_tready <= 0;
        else        m_tready <= (lcg(rm) % 100 < 60);
    end

    // checker: data must arrive 1,2,3,... in order
    always @(posedge clk) begin
        if (rst_n && m_tvalid && m_tready) begin
            recv_cnt <= recv_cnt + 1;
            if (m_tdata !== (recv_cnt + 1)) begin
                $error("ordering/loss: got %0d expected %0d", m_tdata, recv_cnt + 1);
                errors++;
            end
        end
    end

    // stability check: while valid held and not ready, data must not change
    logic [DW-1:0] prev_m; logic prev_stall;
    always @(posedge clk) begin
        if (rst_n) begin
            if (m_tvalid && !m_tready) begin
                if (prev_stall && (m_tdata !== prev_m)) begin
                    $error("TDATA changed during stall: %0d -> %0d", prev_m, m_tdata);
                    errors++;
                end
                prev_m <= m_tdata; prev_stall <= 1;
            end else prev_stall <= 0;
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;
        wait (recv_cnt == NBEATS);
        repeat (5) @(posedge clk);
        if (errors == 0)
            $display("PASS tb_axis_skid_buffer: %0d beats, lossless+ordered+stable", NBEATS);
        else
            $display("FAIL tb_axis_skid_buffer: %0d errors", errors);
        $finish;
    end

    // watchdog
    initial begin
        #2_000_000;
        $display("FAIL tb_axis_skid_buffer: watchdog timeout (recv=%0d)", recv_cnt);
        $finish;
    end
endmodule

`default_nettype wire
