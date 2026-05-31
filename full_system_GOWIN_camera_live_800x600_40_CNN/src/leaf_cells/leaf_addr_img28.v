`timescale 1ns/1ps

module leaf_addr_img28 (
    input  wire [4:0] yy,
    input  wire [4:0] xx,
    output wire [9:0] addr
);

assign addr = ({yy, 5'b00000} - {3'b000, yy, 2'b00}) + {5'd0, xx};

endmodule
