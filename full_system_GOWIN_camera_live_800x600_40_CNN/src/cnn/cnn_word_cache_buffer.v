`timescale 1ns/1ps

module cnn_word_cache_buffer #(
    parameter integer ADDR_WIDTH = 10,
    parameter integer DEPTH = 576
)(
    input  wire                  clk,
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [31:0]           wr_data,
    input  wire                  rd_en,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output reg  [31:0]           rd_data
);

reg [31:0] mem [0:DEPTH-1]
    /* synthesis syn_ramstyle = "block_ram" */;

always @(posedge clk) begin
    if (wr_en)
        mem[wr_addr] <= wr_data;
    if (rd_en)
        rd_data <= mem[rd_addr];
end

endmodule
