`timescale 1ns/1ps

module leaf_rgb565_green_to_gray (
    input  wire [15:0] rgb565,
    output wire [7:0]  gray
);

wire [5:0] green6 = rgb565[10:5];

assign gray = {green6, green6[5:4]};

endmodule
