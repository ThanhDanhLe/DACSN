`timescale 1ns/1ps

module cnn_feature_buffer #(
    parameter integer ADDR_WIDTH = 12,
    parameter integer DEPTH = 3136
)(
    input  wire                         clk,
    input  wire                         wr_en,
    input  wire [ADDR_WIDTH-1:0]        wr_addr,
    input  wire signed [15:0]           wr_data,
    input  wire                         rd_en,
    input  wire [ADDR_WIDTH-1:0]        rd_addr,
    output reg  signed [15:0]           rd_data
);

reg signed [15:0] mem [0:DEPTH-1]
    /* synthesis syn_ramstyle = "block_ram" */;

always @(posedge clk) begin
    if (wr_en)
        mem[wr_addr] <= wr_data;
    if (rd_en)
        rd_data <= mem[rd_addr];
end

endmodule
