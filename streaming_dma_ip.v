// =============================================================================
// streaming_dma_ip.v
//
// TOP-LEVEL, BOARD-AGNOSTIC IP CORE
//
// This is the "productized" version of the original project: a single,
// self-contained module with only clk/reset/led ports crossing its boundary,
// no dependency on a Quartus Platform-Designer/Qsys system ("mem_system")
// or any vendor-specific glue. Drop this module (plus its four RTL
// dependencies) into any FPGA project / any board and it will elaborate and
// run unchanged - only the board-level pin wrapper (see avalon_test.v)
// differs from board to board.
//
// Internal datapath (unchanged in spirit from the original project):
//
//   avalon_onchip_mem  --Avalon-MM-->  dma_engine  --Avalon-ST-->  avalon_consumer --> led_output
//     (read-only slave)                (read master +                (sink, drives
//                                        stream source)                LEDs)
//
// A full set of internal handshake signals are brought out as "dbg_*" ports
// purely so that every protocol signal (address, read, waitrequest,
// readdatavalid, stream valid/ready/data, transfer count) is easy to find
// and probe in a waveform viewer such as GTKWave.
// =============================================================================

module streaming_dma_ip #(
    parameter ADDR_WIDTH            = 8,     // Avalon-MM byte address width
    parameter MEM_WORDS             = 64,    // internal memory depth (32-bit words)
    parameter MEM_LATENCY           = 2,     // memory read latency, in cycles
    parameter MEM_STALL_PERIOD      = 5,     // memory waitrequest stall period (0=off)
    parameter CONSUMER_STALL_PERIOD = 0      // sink backpressure period (0=off)
)(
    input  wire                     clk,
    input  wire                     reset_n,

    output wire [7:0]                led_output,

    // ---------------- debug / verification monitor ports ----------------
    output wire [ADDR_WIDTH-1:0]     dbg_amm_address,
    output wire                      dbg_amm_read,
    output wire [31:0]               dbg_amm_readdata,
    output wire                      dbg_amm_readdatavalid,
    output wire                      dbg_amm_waitrequest,

    output wire [7:0]                dbg_stream_data,
    output wire                      dbg_stream_valid,
    output wire                      dbg_stream_ready,

    output wire [15:0]               dbg_xfer_count
);

    // ------------------------------------------------------------------
    // Internal Avalon-MM bus: dma_engine (master) <-> avalon_onchip_mem (slave)
    // ------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0] amm_address;
    wire                  amm_read;
    wire [31:0]           amm_readdata;
    wire                  amm_readdatavalid;
    wire                  amm_waitrequest;

    // ------------------------------------------------------------------
    // Internal Avalon-ST bus: dma_engine (source) <-> avalon_consumer (sink)
    // ------------------------------------------------------------------
    wire [7:0] stream_data;
    wire       stream_valid;
    wire       stream_ready;

    dma_engine #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .ADDR_MAX   (MEM_WORDS*4 - 1)
    ) u_dma (
        .clk                (clk),
        .reset_n            (reset_n),

        .amm_address        (amm_address),
        .amm_read           (amm_read),
        .amm_readdata       (amm_readdata),
        .amm_readdatavalid  (amm_readdatavalid),
        .amm_waitrequest    (amm_waitrequest),

        .aso_data           (stream_data),
        .aso_valid          (stream_valid),
        .aso_ready          (stream_ready)
    );

    avalon_onchip_mem #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (32),
        .MEM_WORDS    (MEM_WORDS),
        .LATENCY      (MEM_LATENCY),
        .STALL_PERIOD (MEM_STALL_PERIOD)
    ) u_mem (
        .clk            (clk),
        .reset_n        (reset_n),

        .address        (amm_address),
        .read           (amm_read),
        .readdata       (amm_readdata),
        .readdatavalid  (amm_readdatavalid),
        .waitrequest    (amm_waitrequest)
    );

    avalon_consumer #(
        .STALL_PERIOD (CONSUMER_STALL_PERIOD)
    ) u_consumer (
        .clk         (clk),
        .reset_n     (reset_n),

        .asi_data    (stream_data),
        .asi_valid   (stream_valid),
        .asi_ready   (stream_ready),

        .led_output  (led_output),
        .xfer_count  (dbg_xfer_count)
    );

    // ------------------------------------------------------------------
    // Debug/monitor taps - purely combinational wires onto the internal
    // busses, so every handshake signal is directly observable at the top
    // level (and therefore trivially added to a GTKWave view).
    // ------------------------------------------------------------------
    assign dbg_amm_address       = amm_address;
    assign dbg_amm_read          = amm_read;
    assign dbg_amm_readdata      = amm_readdata;
    assign dbg_amm_readdatavalid = amm_readdatavalid;
    assign dbg_amm_waitrequest   = amm_waitrequest;

    assign dbg_stream_data       = stream_data;
    assign dbg_stream_valid      = stream_valid;
    assign dbg_stream_ready      = stream_ready;

endmodule
