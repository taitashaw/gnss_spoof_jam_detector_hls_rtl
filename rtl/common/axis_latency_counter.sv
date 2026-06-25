// ============================================================================
// axis_latency_counter.sv -- streaming latency measurement
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Measures, per window, real cycle latency through the pipeline INCLUDING any
// backpressure stalls (this is exactly what a cycle simulation proves that a
// C model cannot):
//
//   latency_first  : cycles from the first accepted input beat of a window to
//                    the first accepted output beat of that window's packet.
//   latency_total  : cycles from the first accepted input beat to the output
//                    tlast of the packet.
//   window_cycles  : cycles the timer ran for the most recent window.
//
// The counter arms for a new window after each output tlast, so it tracks one
// window in flight at a time -- matching the one-packet-per-window engine.
// Active-low reset. Outputs are registered and stable between updates, so the
// alert packer can sample latency_first when it builds the packet.
// ============================================================================
`default_nettype none

module axis_latency_counter (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        in_valid,
    input  wire        in_ready,
    input  wire        out_valid,
    input  wire        out_ready,
    input  wire        out_last,

    output reg [31:0]  latency_first,
    output reg [31:0]  latency_total,
    output reg [31:0]  window_cycles,
    // combinational running count since this window's first input beat; the
    // alert packer samples this when it stamps the packet so the reported
    // latency belongs to the current window (no off-by-one).
    output wire [31:0] live_cycles
);
    wire in_beat  = in_valid  && in_ready;
    wire out_beat = out_valid && out_ready;

    reg        armed;     // waiting for the first input beat of a window
    reg        running;   // timer active
    reg        got_first; // captured first output beat of this window
    reg [31:0] timer;

    // combinational running count for the current window (see port comment)
    assign live_cycles = timer;

    always @(posedge clk) begin
        if (!rst_n) begin
            armed         <= 1'b1;
            running       <= 1'b0;
            got_first     <= 1'b0;
            timer         <= 32'd0;
            latency_first <= 32'd0;
            latency_total <= 32'd0;
            window_cycles <= 32'd0;
        end else begin
            // Start timing at the first accepted input beat of a window.
            if (in_beat && armed) begin
                armed     <= 1'b0;
                running   <= 1'b1;
                got_first <= 1'b0;
                timer     <= 32'd0;
            end else if (running) begin
                timer <= timer + 1'b1;
            end

            // Capture latency to the first output beat.
            if (out_beat && running && !got_first) begin
                latency_first <= timer;
                got_first     <= 1'b1;
            end

            // On the packet's last output beat, latch totals and re-arm.
            if (out_beat && out_last && running) begin
                latency_total <= timer;
                window_cycles <= timer;
                running       <= 1'b0;
                armed         <= 1'b1;
            end
        end
    end
endmodule

`default_nettype wire
