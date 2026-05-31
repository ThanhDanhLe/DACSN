`timescale 1ns/1ps

module leaf_addr_14c4 (
    input  wire [4:0] yy,
    input  wire [4:0] xx,
    input  wire [4:0] cc,
    output wire [9:0] addr
);

wire [10:0] tmp;

assign tmp = ({yy, 6'b000000} - {3'b000, yy, 3'b000}) + {4'b0000, xx, 2'b00} + {6'd0, cc};
assign addr = tmp[9:0];

endmodule
