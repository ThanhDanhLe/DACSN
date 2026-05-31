`timescale 1ns/1ps

module cnn_argmax #(
    parameter integer LOGIT_WIDTH = 64
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire               logit_valid,
    input  wire [3:0]         logit_index,
    input  wire signed [LOGIT_WIDTH-1:0] logit,
    output reg                output_valid,
    output reg  [3:0]         output_class
);

reg signed [LOGIT_WIDTH-1:0] max_logit;
reg [3:0] max_class;

wire better = (logit_index == 4'd0) || (logit > max_logit);
wire [3:0] next_class = better ? logit_index : max_class;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        max_logit <= {1'b1, {(LOGIT_WIDTH-1){1'b0}}};
        max_class <= 4'd0;
        output_valid <= 1'b0;
        output_class <= 4'd0;
    end else begin
        output_valid <= 1'b0;

        if (start) begin
            max_logit <= {1'b1, {(LOGIT_WIDTH-1){1'b0}}};
            max_class <= 4'd0;
            output_class <= 4'd0;
        end

        if (logit_valid) begin
            if (better) begin
                max_logit <= logit;
                max_class <= logit_index;
            end

            if (logit_index == 4'd9) begin
                output_valid <= 1'b1;
                output_class <= next_class;
            end
        end
    end
end

endmodule
