`timescale 1ns/1ps

module mnist_image_buffer_dualclk #(
    parameter DATA_WIDTH = 16,
    parameter ADDR_WIDTH = 10,
    parameter DEPTH = 784
)(
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [DATA_WIDTH-1:0] wr_data,

    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire                  rd0_en,
    input  wire [ADDR_WIDTH-1:0] rd0_addr,
    output wire [DATA_WIDTH-1:0] rd0_data,
    input  wire                  rd1_en,
    input  wire [ADDR_WIDTH-1:0] rd1_addr,
    output wire [DATA_WIDTH-1:0] rd1_data
);

localparam [ADDR_WIDTH-1:0] DEPTH_AW = DEPTH;

wire rd_req = rd0_en || rd1_en;
wire [ADDR_WIDTH-1:0] rd_addr_mux = rd0_en ? rd0_addr : rd1_addr;
wire rd_in_range = rd_addr_mux < DEPTH_AW;
wire wr_in_range = wr_addr < DEPTH_AW;

`ifdef SIMULATION
reg [7:0] mem [0:DEPTH-1];
reg [7:0] rd_byte;
integer i;

initial begin
    for (i = 0; i < DEPTH; i = i + 1)
        mem[i] = 8'd0;
end

always @(posedge wr_clk) begin
    if (wr_en && wr_in_range)
        mem[wr_addr] <= wr_data[7:0];
end

always @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
        rd_byte <= 8'd0;
    end else if (rd_req) begin
        rd_byte <= rd_in_range ? mem[rd_addr_mux] : 8'd0;
    end
end
`else
wire [31:0] sdpb_do;
wire [13:0] wr_addr_bram = {1'b0, wr_addr, 3'b000};
wire [13:0] rd_addr_bram = {1'b0, rd_addr_mux, 3'b000};

SDPB u_sdpb (
    .DO(sdpb_do),
    .DI({24'd0, wr_data[7:0]}),
    .BLKSELA(3'b000),
    .BLKSELB(3'b000),
    .ADA(wr_addr_bram),
    .ADB(rd_addr_bram),
    .CLKA(wr_clk),
    .CLKB(rd_clk),
    .CEA(wr_en && wr_in_range),
    .CEB(rd_req && rd_in_range),
    .OCE(1'b1),
    .RESETA(~wr_rst_n),
    .RESETB(~rd_rst_n)
);
defparam u_sdpb.READ_MODE = 1'b0;
defparam u_sdpb.BIT_WIDTH_0 = 8;
defparam u_sdpb.BIT_WIDTH_1 = 8;
defparam u_sdpb.BLK_SEL_0 = 3'b000;
defparam u_sdpb.BLK_SEL_1 = 3'b000;
defparam u_sdpb.RESET_MODE = "SYNC";

wire [7:0] rd_byte = sdpb_do[7:0];
`endif

wire [DATA_WIDTH-1:0] rd_word = {{(DATA_WIDTH-8){1'b0}}, rd_byte};

assign rd0_data = rd_word;
assign rd1_data = rd_word;

endmodule
