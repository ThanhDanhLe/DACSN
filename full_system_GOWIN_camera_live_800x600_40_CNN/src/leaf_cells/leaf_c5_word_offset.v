`timescale 1ns/1ps

module leaf_c5_word_offset (
    input  wire [8:0]  idx,
    input  wire        group,
    output wire [11:0] word_offset
);

wire [6:0] block_idx;

assign block_idx = idx[8:2];
assign word_offset = 12'd522 + {2'd0, block_idx, 3'b000} +
                     {9'd0, group, 2'b00} + {10'd0, idx[1:0]};

endmodule
