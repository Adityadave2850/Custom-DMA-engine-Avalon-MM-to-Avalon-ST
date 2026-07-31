// =============================================================================
// dma_engine.v
//
// Avalon-MM READ MASTER  +  Avalon-ST SOURCE
//
// Reads 32-bit words from an Avalon-MM slave (memory, FIFO, peripheral, ...)
// starting at address 0, wrapping at ADDR_MAX+1, and streams the low byte of
// each word out on an Avalon-ST source interface.
//
// This is a corrected, protocol-compliant rewrite of the original bring-up
// stub: the previous version asserted/deasserted amm_read in the same cycle
// and never actually looked at amm_waitrequest or amm_readdatavalid ("BYPASS"
// comments in the original), so it never really moved data from memory - it
// just echoed the address. That version cannot be reused on real memory/DMA
// fabrics. Logic below fixes that while keeping the same state names,
// interface names and overall shape as the original.
// =============================================================================

module dma_engine #(
    parameter ADDR_WIDTH = 8,     // width of amm_address
    parameter ADDR_MAX   = 255    // last valid BYTE address, then wrap to 0
)(
    input  wire                    clk,
    input  wire                    reset_n,

    // ---------------- Avalon-MM MASTER (read only) ----------------
    output reg  [ADDR_WIDTH-1:0]   amm_address,
    output reg                     amm_read,
    input  wire [31:0]             amm_readdata,
    input  wire                    amm_readdatavalid,
    input  wire                    amm_waitrequest,

    // ---------------- Avalon-ST SOURCE -----------------------------
    output reg  [7:0]              aso_data,
    output reg                     aso_valid,
    input  wire                    aso_ready
);

    localparam IDLE  = 2'd0,
               READ   = 2'd1,
               WAIT   = 2'd2,
               WRITE  = 2'd3;

    reg [1:0]            state;
    reg [ADDR_WIDTH-1:0] read_addr;
    reg [31:0]           captured_data;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state         <= IDLE;
            read_addr     <= {ADDR_WIDTH{1'b0}};
            amm_address   <= {ADDR_WIDTH{1'b0}};
            amm_read      <= 1'b0;
            aso_valid     <= 1'b0;
            aso_data      <= 8'd0;
            captured_data <= 32'd0;
        end else begin
            case (state)

                // Wait for the downstream sink to show up before issuing the
                // very first Avalon-MM request.
                IDLE: begin
                    if (aso_ready)
                        state <= READ;
                end

                // Issue a read request and hold it asserted until the slave
                // actually accepts it (amm_waitrequest == 0). This is the
                // real Avalon-MM handshake - the original bypassed it.
                //
                // NOTE on timing: amm_read/amm_address are registered
                // outputs, so a request only becomes visible to the slave
                // one cycle after we assert it here. We therefore check
                // "amm_read && !amm_waitrequest" - i.e. we only declare the
                // request accepted once amm_read has *already* been driven
                // high on a previous cycle and the slave's (combinational)
                // waitrequest response to that has come back low. Clearing
                // amm_read in the very same cycle we first raise it (as the
                // original bring-up code effectively did) would mean the
                // slave never actually sees the request asserted.
                READ: begin
                    amm_address <= read_addr;
                    amm_read    <= 1'b1;

                    if (amm_read && !amm_waitrequest) begin
                        amm_read <= 1'b0;
                        state    <= WAIT;
                    end
                end

                // Wait for the slave to actually return data. The original
                // skipped straight to WRITE regardless of readdatavalid;
                // that is fixed here.
                WAIT: begin
                    if (amm_readdatavalid) begin
                        captured_data <= amm_readdata;
                        state         <= WRITE;
                    end
                end

                // Present the real memory data (low byte) on the Avalon-ST
                // source and wait for the sink to accept it.
                WRITE: begin
                    aso_data  <= captured_data[7:0];
                    aso_valid <= 1'b1;                   // a counter mechanism can be added to send all 4 bytes of the avalon mm word to 
                                                         // the avalon st interface
                    if (aso_valid && aso_ready) begin
                        aso_valid <= 1'b0;

                        if (read_addr >= ADDR_MAX - 3)
                            read_addr <= {ADDR_WIDTH{1'b0}};
                        else
                            read_addr <= read_addr + 32'd4;

                        state <= READ;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
