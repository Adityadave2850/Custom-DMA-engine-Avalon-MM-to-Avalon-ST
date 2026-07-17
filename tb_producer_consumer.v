// =============================================================================
// tb_producer_consumer.v
//
// Secondary testbench: exercises the simple standalone path
// avalon_producer -> avalon_consumer (no DMA / no memory), to demonstrate
// that avalon_producer.v is independently reusable as its own small IP
// block and that the basic Avalon-ST valid/ready handshake is correct.
//
// Self-checks that the byte stream landing on led_output is the free-running
// counter sequence 0,1,2,...,255,0,... with no skips or repeats, even with
// sink backpressure enabled.
// =============================================================================

`timescale 1ns/1ps

module tb_producer_consumer;

    localparam CLK_PERIOD = 20;

    reg clk;
    reg reset_n;

    wire [7:0] stream_data;
    wire       stream_valid;
    wire       stream_ready;
    wire [7:0] led_output;
    wire [15:0] xfer_count;

    avalon_producer u_producer (
        .clk       (clk),
        .reset_n   (reset_n),
        .aso_data  (stream_data),
        .aso_valid (stream_valid),
        .aso_ready (stream_ready)
    );

    avalon_consumer #(
        .STALL_PERIOD (5)   // exercise sink backpressure
    ) u_consumer (
        .clk        (clk),
        .reset_n    (reset_n),
        .asi_data   (stream_data),
        .asi_valid  (stream_valid),
        .asi_ready  (stream_ready),
        .led_output (led_output),
        .xfer_count (xfer_count)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        clk     = 1'b0;
        reset_n = 1'b0;
        repeat (5) @(posedge clk);
        reset_n = 1'b1;
    end

    initial begin
        $dumpfile("producer_consumer.vcd");
        $dumpvars(0, tb_producer_consumer);
    end

    // Expected value = previous accepted value + 1 (starts at 0)
    reg [7:0] expected;
    integer   checked;
    integer   errors;

    initial begin
        expected = 8'd0;
        checked  = 0;
        errors   = 0;
    end

    always @(posedge clk) begin
        if (reset_n && stream_valid && stream_ready) begin
            checked <= checked + 1;
            if (stream_data !== expected) begin
                $display("[%0t] MISMATCH #%0d: got 0x%02h expected 0x%02h",
                          $time, checked, stream_data, expected);
                errors <= errors + 1;
            end
            expected <= expected + 8'd1;
        end
    end

    initial begin
        wait (reset_n === 1'b1);
        repeat (600) @(posedge clk);

        $display("--------------------------------------------------");
        $display(" PRODUCER/CONSUMER TEST SUMMARY");
        $display("   transfers checked : %0d", checked);
        $display("   mismatches        : %0d", errors);
        $display("   RESULT            : %s", (checked > 0 && errors == 0) ? "PASS" : "FAIL");
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
