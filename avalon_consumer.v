// =============================================================================
// avalon_consumer.v
//
// Avalon-ST SINK. This module was referenced by the original avalon_test.v
// top level but never actually existed in the project - the design could not
// elaborate without it. It is added here to complete the architecture.
//
// Behaviour: accepts one byte per valid/ready handshake and latches it into
// an output register (e.g. LEDs). An optional stall generator can be enabled
// (STALL_PERIOD != 0) to model a sink that occasionally can't accept data,
// which exercises the upstream source's valid/ready backpressure handling in
// simulation.
// =============================================================================

module avalon_consumer #(
    parameter STALL_PERIOD = 0   // assert !ready for 1 cycle every N accepted
                                  // transfers (0 = always ready, no backpressure)
)(
    input  wire       clk,
    input  wire       reset_n,

    // Avalon-ST Sink Interface (asi)
    input  wire [7:0] asi_data,
    input  wire       asi_valid,
    output reg        asi_ready,

    output reg  [7:0] led_output,     // last accepted byte, mirrored on LEDs
    output reg [15:0] xfer_count      // debug: total accepted transfers
);

    reg [15:0] stall_ctr;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            asi_ready  <= 1'b1;
            led_output <= 8'd0;
            xfer_count <= 16'd0;
            stall_ctr  <= 16'd0;
        end else begin

            // Default: ready, unless the stall generator says otherwise
            asi_ready <= 1'b1;

            if (asi_valid && asi_ready) begin
                led_output <= asi_data;
                xfer_count <= xfer_count + 16'd1;

                if (STALL_PERIOD != 0) begin
                    if (stall_ctr == STALL_PERIOD - 1) begin
                        asi_ready <= 1'b0;   // insert one cycle of backpressure
                        stall_ctr <= 16'd0;
                    end else begin
                        stall_ctr <= stall_ctr + 16'd1;
                    end
                end
            end
        end
    end

endmodule
