`timescale 1ns/1ps

module leaf_c5_cache_word (
    input  wire [1:0] ky,
    input  wire [1:0] kx,
    input  wire [4:0] cin,
    input  wire [4:0] cout,
    output wire [8:0] cache_word
);

wire [3:0] kk;
wire [6:0] block_idx;

assign kk = {1'b0, ky} + {ky, 1'b0} + {2'b00, kx};
assign block_idx = {kk, 3'b000} + cin[2:0];
assign cache_word = {block_idx, 2'b00} + {7'd0, cout[2:1]};

endmodule
