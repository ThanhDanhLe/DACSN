`timescale 1ns/1ps

module leaf_reg_bus_en_rst #(
    parameter WIDTH = 8,
    parameter [WIDTH-1:0] RESET_VALUE = {WIDTH{1'b0}}
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             en,
    input  wire [WIDTH-1:0] d,
    output reg  [WIDTH-1:0] q
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        q <= RESET_VALUE;
    else if (en)
        q <= d;
end

endmodule
