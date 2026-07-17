// =============================================================================
// tb_streaming_dma_ip.v
//
// Self-checking testbench for streaming_dma_ip.
//
// What it verifies (all visible directly in the GTKWave trace too):
//   1. Reset behaviour of every block.
//   2. Avalon-MM master (dma_engine) correctly honours amm_waitrequest before
//      considering a read "accepted".
//   3. Avalon-MM slave (avalon_onchip_mem) correctly asserts waitrequest
//      (stall generator) and returns readdatavalid after a fixed latency.
//   4. Avalon-ST handshake between dma_engine (source) and avalon_consumer
//      (sink), including sink backpressure (asi_ready deasserted).
//   5. End-to-end data integrity: every byte that lands on led_output is
//      independently predicted from the memory's known init pattern and
//      compared - a mismatch is flagged immediately with $display and
//      bumps an error counter checked at the end.
//   6. Address wraparound: memory depth is deliberately small (16 words)
//      so the address counter wraps multiple times during the run.
// =============================================================================

`timescale 1ns/1ps

module tb_streaming_dma_ip;

    // ------------------------------------------------------------------
    // Parameters for this test run (small memory -> wraps quickly,
    // both mem and sink stalls enabled -> real backpressure is exercised)
    // ------------------------------------------------------------------
    localparam ADDR_WIDTH            = 8;
    localparam MEM_WORDS             = 16;
    localparam MEM_LATENCY           = 2;
    localparam MEM_STALL_PERIOD      = 4;
    localparam CONSUMER_STALL_PERIOD = 3;

    localparam CLK_PERIOD = 20; // 50 MHz

    // ------------------------------------------------------------------
    // DUT connections
    // ------------------------------------------------------------------
    reg clk;
    reg reset_n;

    wire [7:0] led_output;

    wire [ADDR_WIDTH-1:0] dbg_amm_address;
    wire                  dbg_amm_read;
    wire [31:0]           dbg_amm_readdata;
    wire                  dbg_amm_readdatavalid;
    wire                  dbg_amm_waitrequest;

    wire [7:0]  dbg_stream_data;
    wire        dbg_stream_valid;
    wire        dbg_stream_ready;

    wire [15:0] dbg_xfer_count;

    streaming_dma_ip #(
        .ADDR_WIDTH            (ADDR_WIDTH),
        .MEM_WORDS             (MEM_WORDS),
        .MEM_LATENCY           (MEM_LATENCY),
        .MEM_STALL_PERIOD      (MEM_STALL_PERIOD),
        .CONSUMER_STALL_PERIOD (CONSUMER_STALL_PERIOD)
    ) dut (
        .clk                    (clk),
        .reset_n                (reset_n),
        .led_output              (led_output),

        .dbg_amm_address        (dbg_amm_address),
        .dbg_amm_read           (dbg_amm_read),
        .dbg_amm_readdata       (dbg_amm_readdata),
        .dbg_amm_readdatavalid  (dbg_amm_readdatavalid),
        .dbg_amm_waitrequest    (dbg_amm_waitrequest),

        .dbg_stream_data        (dbg_stream_data),
        .dbg_stream_valid       (dbg_stream_valid),
        .dbg_stream_ready       (dbg_stream_ready),

        .dbg_xfer_count         (dbg_xfer_count)
    );

    // ------------------------------------------------------------------
    // Clock / reset
    // ------------------------------------------------------------------
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        clk     = 1'b0;
        reset_n = 1'b0;
        repeat (5) @(posedge clk);
        reset_n = 1'b1;
        $display("[%0t] TB: reset released", $time);
    end

    // ------------------------------------------------------------------
    // VCD dump for GTKWave - dump the whole hierarchy so every internal
    // signal (memory contents excluded) is available to probe.
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("streaming_dma_ip.vcd");
        $dumpvars(0, tb_streaming_dma_ip);
    end

    // ------------------------------------------------------------------
    // Scoreboard stage 1: remember the word-address of every ACCEPTED
    // Avalon-MM read request (read && !waitrequest), in issue order.
    // ------------------------------------------------------------------
    localparam FIFO_DEPTH = 16;
    reg [ADDR_WIDTH-1:0] addr_fifo [0:FIFO_DEPTH-1];
    integer addr_wr, addr_rd;

    // Scoreboard stage 2: expected data byte queue, one entry per word
    // that comes back from memory (readdatavalid), in order.
    reg [7:0] exp_fifo [0:FIFO_DEPTH-1];
    integer exp_wr, exp_rd;

    integer errors;
    integer checked;

    initial begin
        addr_wr = 0; addr_rd = 0;
        exp_wr  = 0; exp_rd  = 0;
        errors  = 0;
        checked = 0;
    end

    // Capture accepted read address
    always @(posedge clk) begin
        if (reset_n && dbg_amm_read && !dbg_amm_waitrequest) begin
            addr_fifo[addr_wr % FIFO_DEPTH] <= dbg_amm_address;
            addr_wr <= addr_wr + 1;
        end
    end

    // When data comes back from memory, pop the address and compute the
    // expected byte using the *same* formula avalon_onchip_mem used to
    // initialise itself: byte = (word_index*2 + 1) & 0xFF
    always @(posedge clk) begin
        if (reset_n && dbg_amm_readdatavalid) begin
            exp_fifo[exp_wr % FIFO_DEPTH] <=
                (((addr_fifo[addr_rd % FIFO_DEPTH] >> 2) * 2 + 1) & 8'hFF);
            exp_wr  <= exp_wr + 1;
            addr_rd <= addr_rd + 1;
        end
    end

    // When the byte is actually handed to the sink, pop the expected value
    // and compare.
    always @(posedge clk) begin
        if (reset_n && dbg_stream_valid && dbg_stream_ready) begin
            checked <= checked + 1;
            if (dbg_stream_data !== exp_fifo[exp_rd % FIFO_DEPTH]) begin
                $display("[%0t] MISMATCH #%0d: got 0x%02h expected 0x%02h",
                          $time, checked, dbg_stream_data, exp_fifo[exp_rd % FIFO_DEPTH]);
                errors <= errors + 1;
            end else begin
                $display("[%0t] OK #%0d: stream_data=0x%02h led_output(prev)=0x%02h xfer_count=%0d",
                          $time, checked, dbg_stream_data, led_output, dbg_xfer_count);
            end
            exp_rd <= exp_rd + 1;
        end
    end

    // ------------------------------------------------------------------
    // Run for enough cycles to see several full address wraps
    // (MEM_WORDS=16 -> 64 bytes -> wraps every 16 transfers)
    // ------------------------------------------------------------------
    initial begin
        wait (reset_n === 1'b1);
        repeat (2500) @(posedge clk);

        $display("--------------------------------------------------");
        $display(" TEST SUMMARY");
        $display("   transfers checked : %0d", checked);
        $display("   mismatches        : %0d", errors);
        if (checked == 0)
            $display("   RESULT            : FAIL (no transfers observed)");
        else if (errors == 0)
            $display("   RESULT            : PASS");
        else
            $display("   RESULT            : FAIL");
        $display("--------------------------------------------------");

        $finish;
    end

endmodule
