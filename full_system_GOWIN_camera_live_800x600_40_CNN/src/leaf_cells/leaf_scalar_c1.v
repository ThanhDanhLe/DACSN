`timescale 1ns/1ps

module leaf_scalar_c1 (
    input  wire [1:0]  ky,
    input  wire [1:0]  kx,
    input  wire [4:0]  cout,
    output wire [10:0] scalar
);

wire [3:0] kk;

assign kk = {1'b0, ky} + {ky, 1'b0} + {2'b00, kx};
assign scalar = {5'd0, kk, 2'b00} + {6'd0, cout};

endmodule
