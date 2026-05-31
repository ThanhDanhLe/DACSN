`timescale 1ns/1ps

module leaf_adder #(
    parameter WIDTH = 1
)(
    input  wire signed [WIDTH-1:0] a,
    input  wire signed [WIDTH-1:0] b,
    output wire signed [WIDTH-1:0] y
);

assign y = a + b;

endmodule
