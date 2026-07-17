// =============================================================================
// avalon_producer.v
//
// Simple free-running Avalon-ST SOURCE that just counts up (0,1,2,...,255,0,...)
// and offers a new byte every cycle the sink is ready for. Kept from the
// original project as a lightweight, standalone alternative source IP for
// simple bring-up/test scenarios where a full DMA engine isn't needed -
// logic is unchanged from the original, only comments clarify the protocol.
// =============================================================================

module avalon_producer (
    input  wire       clk,
    input  wire       reset_n,

    // Avalon-ST Source Interface (aso)
    output reg [7:0]  aso_data,   // 8-bit data
    output reg        aso_valid,  // "Here is data"
    input  wire       aso_ready   // "Can you take it?"
);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            aso_data  <= 8'd0;
            aso_valid <= 1'b0;
        end else begin
            // We always have data to give
            aso_valid <= 1'b1;

            // THE AVALON HANDSHAKE (latency 0):
            // Advance the counter only once the sink actually accepts data
            if (aso_valid && aso_ready) begin
                aso_data <= aso_data + 1'b1;
            end
        end
    end
endmodule
