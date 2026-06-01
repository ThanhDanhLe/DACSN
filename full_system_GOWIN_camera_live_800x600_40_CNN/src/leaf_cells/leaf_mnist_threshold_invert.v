`timescale 1ns/1ps

module leaf_mnist_threshold_invert (
    input  wire [7:0] gray,
    input  wire [7:0] threshold,
    output wire [7:0] mnist_pixel
);

wire [7:0] inverted = 8'd255 - gray;

assign mnist_pixel = (gray < threshold) ? inverted : 8'd0;

endmodule
