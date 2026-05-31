`timescale 1ns/1ps

module leaf_multiplier #(
    parameter A_WIDTH = 1,
    parameter B_WIDTH = 1,
    parameter OUT_WIDTH = A_WIDTH + B_WIDTH
)(
    input  wire signed [A_WIDTH-1:0]   a,
    input  wire signed [B_WIDTH-1:0]   b,
    output wire signed [OUT_WIDTH-1:0] y
);

assign y = a * b;

endmodule
