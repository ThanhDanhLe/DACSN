`timescale 1ns/1ps
// Select one signed int16 lane from a 32-bit word.
// Little-endian lane convention:
//   lane 0 -> word[15:0]
//   lane 1 -> word[31:16]
module nn_weight16_unpack2 (
    input  wire [31:0] word_data,
    input  wire        lane_sel,
    output wire signed [15:0] value
);
    assign value = lane_sel ? word_data[31:16] : word_data[15:0];
endmodule
