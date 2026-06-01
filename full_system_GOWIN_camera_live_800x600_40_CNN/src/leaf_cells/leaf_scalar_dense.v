`timescale 1ns/1ps

module leaf_scalar_dense (
    input wire [4:0] in_idx,
    input wire [3:0] out_idx,
    output wire [10:0] scalar
);

assign scalar = {in_idx, 3'b000} + {in_idx, 1'b0} + {7'd0, out_idx};

endmodule
