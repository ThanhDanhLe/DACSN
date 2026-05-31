`timescale 1ns/1ps

module leaf_addr_28_mul_shiftadd (
    input  wire [4:0] y,
    input  wire [4:0] x,
    output wire [9:0] addr
);

wire [9:0] y_times_32 = {y, 5'b00000};
wire [9:0] y_times_4  = {3'b000, y, 2'b00};

assign addr = y_times_32 - y_times_4 + {5'd0, x};

endmodule
