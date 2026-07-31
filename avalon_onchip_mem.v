// =============================================================================
// avalon_onchip_mem.v
//
// Generic Avalon-MM SLAVE (read-only in this build) backed by inferred block
// RAM. Replaces the Quartus/Platform-Designer-generated "mem_system" Qsys
// component that the original test wrapper depended on. Because this module
// is plain, portable Verilog with no tool-generated glue, the IP no longer
// needs Platform Designer / Qsys / a specific vendor's memory core - it will
// drop into any board/toolchain that can synthesize plain RTL.
//
// A configurable stall generator periodically asserts waitrequest, and a
// configurable pipeline depth (LATENCY) delays readdatavalid, so that a
// master's protocol handling can actually be exercised/verified in
// simulation instead of assuming an ideal, always-ready slave.
// =============================================================================

module avalon_onchip_mem #(
    parameter ADDR_WIDTH    = 8,     // byte address width
    parameter DATA_WIDTH    = 32,
    parameter MEM_WORDS     = 64,    // depth in 32-bit words
    parameter LATENCY       = 2,     // cycles from accepted request -> readdatavalid
    parameter STALL_PERIOD  = 5      // assert waitrequest for 1 cycle every N read
                                      // attempts while a request is pending (0 = never stall)
)(
    input  wire                     clk,
    input  wire                     reset_n,

    input  wire [ADDR_WIDTH-1:0]    address,
    input  wire                     read,
    output reg  [DATA_WIDTH-1:0]    readdata,
    output reg                      readdatavalid,
    output wire                     waitrequest
);

    localparam WORD_BITS = $clog2(MEM_WORDS);

    // ---------------------------------------------------------------
    // Storage, pre-loaded with a simple, predictable pattern so that a
    // testbench can compute expected data purely from the address:
    //   readdata[7:0] == (word_index*2 + 1) & 0xFF
    // ---------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:MEM_WORDS-1];

    integer i;
    reg [7:0] init_byte;
    initial begin
        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            init_byte = (i * 2 + 1) & 8'hFF;
            mem[i] = {8'hA5, 8'h5A, 8'hA5, init_byte};
        end
    end
    /* ==============================================================================
     * MEMORY INITIALIZATION PATTERN (Diagnostic & Bus Testing)
     * ==============================================================================
     * This block pre-loads the memory with a highly deliberate diagnostic pattern
     * rather than leaving it uninitialized ('X') or zeroed out.
     *
     * 1. The Sentinel Bytes: {8'hA5, 8'h5A, 8'hA5}
     * - Binary A5 = 10100101
     * - Binary 5A = 01011010
     * These hex values are exact bitwise inverses. Stringing them together on a 
     * 32-bit data bus forces nearly every bit line to flip simultaneously. 
     * This acts as a classic hardware stress-test (checking for short-circuits 
     * or voltage droop) and easily exposes bit-shift errors that a standard 
     * 0xAA/0x55 checkerboard might hide. It also creates a highly recognizable 
     * visual signature in waveform viewers like GTKWave.
     *
     * 2. The Address-Dependent Byte: init_byte = (i * 2 + 1) & 8'hFF
     * - The lowest 8 bits are mathematically tied to the memory index (i).
     * - This guarantees every word is unique, allowing the testbench to verify 
     * addressing logic (e.g., ensuring address 4 doesn't accidentally read 
     * the data from address 0).
     * - Why "& 8'hFF"? In Verilog, 'i' is a 32-bit integer, so (i * 2 + 1) 
     * produces a 32-bit result. When writing this to the 8-bit 'init_byte', 
     * strict simulators (and synthesis tools) will throw truncation warnings. 
     * The bitwise AND explicitly masks out the upper 24 bits, safely isolating 
     * the lower 8 bits and telling the compiler this truncation is intentional.
     * ============================================================================== */

    // ---------------------------------------------------------------
    // Stall generator: forces the master to see a real, non-zero-latency
    // waitrequest every STALL_PERIOD accepted-request attempts.
    // ---------------------------------------------------------------
    reg [15:0] stall_ctr;
    reg        stalling;

    assign waitrequest = stalling;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            stall_ctr <= 16'd0;                  
            stalling  <= 1'b0;
        end else if (STALL_PERIOD != 0) begin
            if (stalling) begin                  // if the stalling s high, meanin gwaitrequest is high, so no read possible,
                                                //make sure that such stalls are only one clock cycle long
                stalling <= 1'b0;               // release after exactly 1 cycle
            end else if (read) begin
                if (stall_ctr == STALL_PERIOD - 1) begin
                    stalling  <= 1'b1;                // after a certain number of normal bits have been sent = stall_ctr -1
                    stall_ctr <= 16'd0;               //the 1 clock cycke stall is injected and  stalling counter is reset
                end else begin
                    stall_ctr <= stall_ctr + 16'd1;
                end
            end
        end
    end

    // ---------------------------------------------------------------
    // Fixed-latency read pipeline
    // ---------------------------------------------------------------
    /*
 Stall generator (behavior & intent)

 - Signals:
   - reg [15:0] stall_ctr;  // counts read cycles
   - reg        stalling;   // drives waitrequest for exactly one cycle
   - assign waitrequest = stalling;

 - Reset:
   - On !reset_n both stall_ctr and stalling are cleared (no stalls after reset).

 - STALL_PERIOD semantics:
   - If STALL_PERIOD == 0, the whole periodic-stall logic is disabled (no artificial stalls).
   - Otherwise, the logic increments stall_ctr on every cycle when 'read' is asserted.
   - When stall_ctr reaches (STALL_PERIOD - 1) and a 'read' occurs, stalling <= 1 is set
     and stall_ctr is reset to 0. The stalling flag is cleared on the next clock edge,
     so waitrequest is asserted for exactly one clock cycle.

 - Practical effects / examples:
   - STALL_PERIOD = 5 -> a single-cycle waitrequest pulse after 5 read cycles.
   - STALL_PERIOD = 1 -> waitrequest asserted every read cycle (one-cycle stall per read).
   - STALL_PERIOD = 0 -> never stall (stalls disabled).

 - Notes:
   - The counter only advances while 'read' is asserted; idle cycles do not advance it.
   - Because waitrequest is asserted for one cycle, the master will see that read as not
     accepted for that cycle (accept is read && !waitrequest).
   - This block is intended to emulate a non-ideal slave so masters that assume an
     always-ready slave are exercised in simulation.
*/
    wire accept = read && !waitrequest;

    reg [DATA_WIDTH-1:0] data_pipe  [0:LATENCY-1];
    reg                  valid_pipe [0:LATENCY-1];

    /*
 Fixed-latency read pipeline (behavior & intent)

 - accept:
   - wire accept = read && !waitrequest;
   - 'accept' is true when the master requests a read and the slave is NOT stalling.
     This marks a read that the slave actually accepts this cycle.

 - Pipeline storage:
   - reg [DATA_WIDTH-1:0] data_pipe  [0:LATENCY-1];
   - reg                  valid_pipe [0:LATENCY-1];
   - data_pipe holds the sampled data for each stage.
   - valid_pipe holds a 1-bit flag indicating whether the corresponding data was
     produced by an accepted read (so consumers can ignore samples from non-accepted reads).

 - Reset/init:
   - On !reset_n all data_pipe entries and valid_pipe flags are cleared, and the
     outputs readdata and readdatavalid are cleared to avoid spurious valid pulses.

 - Normal operation:
   - data_pipe[0]  <= mem[address[WORD_BITS+1:2]];
     - The memory word is sampled every cycle using the word index derived from the
       byte address: address[WORD_BITS+1:2] (drops the two LSBs for 4-byte words).
   - valid_pipe[0] <= accept;
     - The stage-0 valid is asserted only when the read was accepted this cycle.
   - For j = 1..LATENCY-1:
       data_pipe[j]  <= data_pipe[j-1];
       valid_pipe[j] <= valid_pipe[j-1];
     - Data and valid bits shift down the pipeline each cycle.
   - readdata      <= data_pipe[LATENCY-1];
     readdatavalid <= valid_pipe[LATENCY-1];
     - The outputs reflect the last pipeline stage, so an accepted read at cycle t
       produces valid readdata at cycle t + LATENCY (deterministic fixed latency).

 - Important notes / gotchas:
   - The memory is sampled into data_pipe[0] every cycle regardless of 'accept', but
     valid_pipe ensures only accepted reads propagate as valid output.
   - The pipeline enforces a deterministic latency equal to LATENCY cycles from
     accept -> readdatavalid.
   - If the stall-generator prevents accept (waitrequest asserted), valid_pipe[0] is 0
     that cycle and no new valid entry enters the pipeline; existing entries continue
     shifting toward the output.
   - The address indexing uses WORD_BITS to select the correct word from a byte address:
     address[WORD_BITS+1:2] converts a byte address into a word index for 32-bit words.
*/

    integer j;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            for (j = 0; j < LATENCY; j = j + 1) begin
                data_pipe[j]  <= {DATA_WIDTH{1'b0}};
                valid_pipe[j] <= 1'b0;
            end
            readdata      <= {DATA_WIDTH{1'b0}};
            readdatavalid <= 1'b0;
        end else begin
            data_pipe[0]  <= mem[address[WORD_BITS+1:2]];
            valid_pipe[0] <= accept;

            for (j = 1; j < LATENCY; j = j + 1) begin
                data_pipe[j]  <= data_pipe[j-1];
                valid_pipe[j] <= valid_pipe[j-1];
            end

            readdata      <= data_pipe[LATENCY-1];
            readdatavalid <= valid_pipe[LATENCY-1];
        end
    end

endmodule
