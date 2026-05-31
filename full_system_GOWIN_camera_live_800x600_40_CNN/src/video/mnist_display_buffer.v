`timescale 1ns/1ps

module mnist_display_buffer #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 10,
    parameter DEPTH = 784
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [DATA_WIDTH-1:0] wr_data,
    input  wire                  rd_en,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output reg  [DATA_WIDTH-1:0] rd_data
);

localparam [ADDR_WIDTH-1:0] DEPTH_AW = DEPTH;

reg [7:0] mem [0:DEPTH-1] /* synthesis syn_ramstyle = "distributed_ram" */;

wire wr_in_range = (wr_addr < DEPTH_AW);
wire rd_in_range = (rd_addr < DEPTH_AW);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rd_data <= {DATA_WIDTH{1'b0}};
    end else begin
        if (wr_en && wr_in_range)
            mem[wr_addr] <= wr_data[7:0];

        if (rd_en)
            rd_data <= rd_in_range ? {{(DATA_WIDTH-8){1'b0}}, mem[rd_addr]} :
                                     {DATA_WIDTH{1'b0}};
        else
            rd_data <= {DATA_WIDTH{1'b0}};
    end
end

endmodule
