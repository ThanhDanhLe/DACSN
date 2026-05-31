`timescale 1ns/1ps

module leaf_addr_7c16 (
    input  wire [4:0] yy,
    input  wire [4:0] xx,
    input  wire [4:0] cc,
    output wire [9:0] addr
);

wire [11:0] tmp;

assign tmp = ({yy, 7'b0000000} - {3'b000, yy, 4'b0000}) + {3'b000, xx, 4'b0000} + {7'd0, cc};
assign addr = tmp[9:0];

endmodule
