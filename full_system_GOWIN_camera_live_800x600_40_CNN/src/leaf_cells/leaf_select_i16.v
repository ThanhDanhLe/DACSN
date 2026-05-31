`timescale 1ns/1ps

module leaf_select_i16 (
    input  wire [31:0]       word,
    input  wire              half_sel,
    output wire signed [15:0] out
);

assign out = half_sel ? word[31:16] : word[15:0];

endmodule
