`timescale 1ns/1ps

module leaf_input_u8_to_i16 (
    input  wire [15:0]        pixel_word,
    output wire signed [15:0] out
);

assign out = {8'd0, pixel_word[7:0]};

endmodule
