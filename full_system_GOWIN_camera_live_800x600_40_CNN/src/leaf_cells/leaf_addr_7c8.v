`timescale 1ns/1ps

module leaf_addr_7c8 (
    input  wire [4:0] yy,
    input  wire [4:0] xx,
    input  wire [4:0] cc,
    output wire [9:0] addr
);

wire [10:0] tmp;

assign tmp = ({yy, 6'b000000} - {3'b000, yy, 3'b000}) + {3'b000, xx, 3'b000} + {6'd0, cc};
assign addr = tmp[9:0];

endmodule
