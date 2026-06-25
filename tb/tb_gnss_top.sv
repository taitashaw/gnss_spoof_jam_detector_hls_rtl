// ============================================================================
// tb_gnss_top.sv -- full-pipeline XSim testbench for gnss_top
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Loads a scenario's input_iq.txt, drives the AXIS I/Q input with seeded source
// throttling, applies seeded output backpressure, captures every metrics packet,
// and writes results/<scenario>/actual_metrics.txt as key=value blocks (one per
// window, blank-line separated) for scripts/check_gnss_results.py to validate.
//
// The in-sim gnss_scoreboard enforces structural invariants; the protocol
// checkers (enabled with -d SIM_ASSERT) enforce AXIS valid/ready stability under
// the backpressure. A watchdog fails (rather than hangs) if packets stop coming.
//
// Plusargs:
//   +INFILE=<path>    input_iq.txt                (required)
//   +OUTFILE=<path>   actual_metrics.txt to write (required)
//   +SCENARIO=<name>  label for messages          (default "scenario")
//   +STALL_MODE=none|random|burst                 (default none)
//   +WINDOW_SIZE=<n>                              (default 1024)
//   +SEED=<int>       backpressure seed           (default 0xC0FFEE)
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module tb_gnss_top
    import gnss_top_pkg::*;
;
    localparam int MAXSAMP = 1 << 18; // holds up to 256 windows of 1024 samples

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    // ---- plusargs ----
    string infile, outfile, scen, stalls;
    int    win_size;
    int unsigned seedv;
    int unsigned mode_code;

    // ---- input memory ----
    int unsigned in_i [0:MAXSAMP-1];
    int unsigned in_q [0:MAXSAMP-1];
    int unsigned in_l [0:MAXSAMP-1];
    int          n_samp;
    int          n_windows;

    // ---- DUT signals ----
    logic [31:0] s_tdata; logic s_tlast, s_tvalid, s_tready;
    logic [METRIC_W-1:0] m_tdata; logic m_tlast, m_tvalid, m_tready;

    // ---- BFMs (seeded throttle + backpressure) ----
    logic        src_en, snk_en;
    logic [31:0] src_beats, snk_beats;
    wire         in_beat  = s_tvalid && s_tready;
    wire         out_beat = m_tvalid && m_tready;

    axis_bfm #(.PCT(70), .BURST(7)) u_src (
        .clk(clk), .rst_n(rst_n), .mode(mode_code[1:0]), .seed(seedv),
        .beat(in_beat), .enable(src_en), .beat_count(src_beats));
    axis_bfm #(.PCT(55), .BURST(9)) u_snk (
        .clk(clk), .rst_n(rst_n), .mode(mode_code[1:0]), .seed(seedv ^ 32'hABCDEF),
        .beat(out_beat), .enable(snk_en), .beat_count(snk_beats));

    // ---- DUT ----
    gnss_top dut (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(s_tdata), .s_axis_tlast(s_tlast),
        .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .m_axis_tdata(m_tdata), .m_axis_tlast(m_tlast),
        .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
        .cfg_we(1'b0), .cfg_waddr(4'd0), .cfg_wdata(64'd0),
        .dbg_out_packets(), .dbg_backpr_cycles(), .dbg_latency_first()
    );

    // ---- scoreboard ----
    wire [31:0] sb_packets, sb_errors;
    gnss_scoreboard u_sb (
        .clk(clk), .rst_n(rst_n), .valid(m_tvalid), .ready(m_tready),
        .tdata(m_tdata), .packets(sb_packets), .errors(sb_errors));

    // ---- input driver ----
    int send_idx;
    wire src_can_present = (!s_tvalid || (s_tvalid && s_tready));
    always @(posedge clk) begin
        if (!rst_n) begin
            s_tvalid <= 0; s_tdata <= 0; s_tlast <= 0; send_idx <= 0;
        end else begin
            if (s_tvalid && s_tready) send_idx <= send_idx + 1;
            if (src_can_present) begin
                if ((send_idx + (s_tvalid && s_tready ? 1 : 0)) < n_samp && src_en) begin
                    automatic int k = send_idx + (s_tvalid && s_tready ? 1 : 0);
                    s_tvalid <= 1;
                    s_tdata  <= {in_i[k][15:0], in_q[k][15:0]};
                    s_tlast  <= in_l[k][0];
                end else begin
                    s_tvalid <= 0;
                end
            end
        end
    end

    // ---- output backpressure ----
    always @(*) m_tready = snk_en;

    // ---- output capture + file write ----
    int fout;
    int pkt_count;

    task automatic write_packet();
        $fwrite(fout, "window_id=%0d\n",        m_tdata[M_WINDOW_ID_O +: 32]);
        $fwrite(fout, "power_estimate=%0d\n",   m_tdata[M_POWER_O     +: 48]);
        $fwrite(fout, "noise_estimate=%0d\n",   m_tdata[M_NOISE_O     +: 32]);
        $fwrite(fout, "cn0_proxy=%0d\n",        m_tdata[M_CN0_O       +: 32]);
        $fwrite(fout, "corr_prompt=%0d\n",      m_tdata[M_CP_O        +: 32]);
        $fwrite(fout, "corr_early=%0d\n",       m_tdata[M_CE_O        +: 32]);
        $fwrite(fout, "corr_late=%0d\n",        m_tdata[M_CL_O        +: 32]);
        $fwrite(fout, "symmetry_error=%0d\n",   m_tdata[M_SYM_O       +: 32]);
        $fwrite(fout, "doppler_energy=%0d\n",   m_tdata[M_DOPP_O      +: 48]);
        $fwrite(fout, "power_jump_metric=%0d\n",m_tdata[M_PJUMP_O     +: 48]);
        $fwrite(fout, "spoof_score=%0d\n",      m_tdata[M_SPOOF_O     +: 32]);
        $fwrite(fout, "jam_score=%0d\n",        m_tdata[M_JAM_O       +: 32]);
        $fwrite(fout, "alert_flags=%0d\n",      m_tdata[M_FLAGS_O     +: 8]);
        $fwrite(fout, "latency_cycles=%0d\n",   m_tdata[M_LAT_O       +: 32]);
        $fwrite(fout, "sample_count=%0d\n",     m_tdata[M_SCNT_O      +: 32]);
        $fwrite(fout, "packet_status=%0d\n",    m_tdata[M_STATUS_O    +: 8]);
        $fwrite(fout, "\n");
    endtask

    always @(posedge clk) begin
        if (rst_n && m_tvalid && m_tready) begin
            write_packet();
            pkt_count <= pkt_count + 1;
        end
    end

    // ---- load + run ----
    int fin, code, idx, vi, vq, vl, ns;
    initial begin
        if (!$value$plusargs("INFILE=%s", infile))  infile  = "input_iq.txt";
        if (!$value$plusargs("OUTFILE=%s", outfile)) outfile = "actual_metrics.txt";
        if (!$value$plusargs("SCENARIO=%s", scen))   scen    = "scenario";
        if (!$value$plusargs("STALL_MODE=%s", stalls)) stalls = "none";
        if (!$value$plusargs("WINDOW_SIZE=%d", win_size)) win_size = 1024;
        if (!$value$plusargs("SEED=%d", seedv)) seedv = 32'hC0FFEE;

        mode_code = (stalls == "random") ? 1 : (stalls == "burst") ? 2 : 0;

        // load input_iq.txt
        fin = $fopen(infile, "r");
        if (fin == 0) begin $display("FAIL: cannot open %s", infile); $finish; end
        ns = 0;
        code = $fscanf(fin, "%d %d %d %d", idx, vi, vq, vl);
        while (code == 4) begin
            in_i[ns] = vi; in_q[ns] = vq; in_l[ns] = vl; ns = ns + 1;
            code = $fscanf(fin, "%d %d %d %d", idx, vi, vq, vl);
        end
        $fclose(fin);
        n_samp    = ns;
        n_windows = ns / win_size;

        fout = $fopen(outfile, "w");
        if (fout == 0) begin $display("FAIL: cannot open %s for write", outfile); $finish; end

        // Optional VCD dump of the AXIS handshake + tapped/metrics signals so a
        // real waveform can be rendered or opened in the Vivado GUI. Enable with
        // +DUMPVCD (+VCDFILE=<path>). Dumps only the handshake-relevant nets.
        if ($test$plusargs("DUMPVCD")) begin
            string vp;
            if (!$value$plusargs("VCDFILE=%s", vp)) vp = "wave.vcd";
            $dumpfile(vp);
            $dumpvars(0, s_tvalid, s_tready, s_tlast, s_tdata);
            $dumpvars(0, m_tvalid, m_tready, m_tlast);
            $dumpvars(0, dut.tap_tvalid, dut.tap_tready, dut.tap_tlast);
            $dumpvars(0, m_tdata[15:0]);
        end

        pkt_count = 0;
        repeat (6) @(posedge clk);
        rst_n = 1;
        $display("tb_gnss_top: scenario=%s samples=%0d windows=%0d stall=%s seed=%08x",
                 scen, n_samp, n_windows, stalls, seedv);

        wait (pkt_count == n_windows);
        repeat (10) @(posedge clk);
        $fclose(fout);

        if (sb_errors == 0)
            $display("PASS tb_gnss_top[%s]: %0d packets captured, scoreboard clean", scen, pkt_count);
        else
            $display("FAIL tb_gnss_top[%s]: %0d scoreboard errors", scen, sb_errors);
        $finish;
    end

    // ---- watchdog (proportional to work) ----
    initial begin
        #20_000_000;
        $display("FAIL tb_gnss_top[%s]: watchdog timeout (pkts=%0d/%0d)", scen, pkt_count, n_windows);
        $fclose(fout);
        $finish;
    end
endmodule

`default_nettype wire
