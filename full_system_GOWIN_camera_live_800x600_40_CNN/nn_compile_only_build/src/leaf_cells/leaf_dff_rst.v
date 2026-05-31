`timescale 1ns/1ps

module leaf_dff_rst #(
    parameter RESET_VALUE = 1'b0
)(
    input  wire clk,
    input  wire rst_n,
    input  wire d,
    output reg  q
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        q <= RESET_VALUE;
    else
        q <= d;
end

endmodule
