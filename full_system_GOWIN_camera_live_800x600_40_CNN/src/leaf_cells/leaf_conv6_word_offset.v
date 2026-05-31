`timescale 1ns/1ps

module leaf_conv6_word_offset (
    input  wire [8:0]  idx,
    input  wire [4:0]  out_ch,
    output wire [11:0] word_offset
);

wire [11:0] scalar;

assign scalar = {idx[7:0], 4'b0000} + {7'd0, out_ch};
assign word_offset = 12'd1098 + scalar[11:1];

endmodule
