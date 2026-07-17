// =============================================================================
// avalon_test.v
//
// BOARD-LEVEL TOP WRAPPER (example: Terasic-style DE-series board pin names:
// CLOCK_50 / KEY / LEDG). This is the *only* file you should need to touch
// when moving the IP to a different board - it merely maps board pins onto
// the portable streaming_dma_ip core.
//
// The original version of this file instantiated a Quartus Platform-Designer
// generated "mem_system" component, which does not exist as portable RTL and
// cannot be simulated or reused outside that exact Quartus project. It has
// been replaced with the self-contained streaming_dma_ip core (see
// streaming_dma_ip.v), which contains an equivalent Avalon-MM memory
// (avalon_onchip_mem.v) built from plain, synthesizable Verilog.
// =============================================================================

module avalon_test (
    input  wire        CLOCK_50,
    input  wire [0:0]  KEY,        // KEY[0] = active-low reset
    output wire [7:0]  LEDG
);

    streaming_dma_ip #(
        .ADDR_WIDTH            (8),
        .MEM_WORDS             (64),
        .MEM_LATENCY           (2),
        .MEM_STALL_PERIOD      (5),
        .CONSUMER_STALL_PERIOD (0)
    ) u_ip (
        .clk         (CLOCK_50),
        .reset_n     (KEY[0]),

        .led_output  (LEDG),

        // Debug ports left unconnected at board level (only used in sim)
        .dbg_amm_address       (),
        .dbg_amm_read          (),
        .dbg_amm_readdata      (),
        .dbg_amm_readdatavalid (),
        .dbg_amm_waitrequest   (),
        .dbg_stream_data       (),
        .dbg_stream_valid      (),
        .dbg_stream_ready      (),
        .dbg_xfer_count        ()
    );

endmodule
