`timescale 1ns/1ps

module mnist28_upscale_renderer #(
    parameter H_RES = 800,
    parameter V_RES = 600,
    parameter ROI_X0 = 176,
    parameter ROI_Y0 = 76,
    parameter SCALE_LOG2 = 4,
    parameter MNIST_SIZE = 28,
    parameter LOOKAHEAD = 0,
    parameter OUTPUT_ADDR = 1
)(
    input  wire        pix_clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire [11:0] video_x,
    input  wire [11:0] video_y,
    input  wire        active_video,

    output wire        mnist_rd_en,
    output wire [9:0]  mnist_rd_addr,
    output wire [4:0]  mnist_rd_x,
    output wire [4:0]  mnist_rd_y,
    input  wire [15:0] mnist_rd_data,

    output wire [7:0]  out_r,
    output wire [7:0]  out_g,
    output wire [7:0]  out_b,
    output wire        out_valid
);

localparam [11:0] ROI_X0_12 = ROI_X0;
localparam [11:0] ROI_Y0_12 = ROI_Y0;
localparam [11:0] ROI_SIZE_12 = MNIST_SIZE << SCALE_LOG2;
localparam [11:0] ROI_X1_12 = ROI_X0 + ROI_SIZE_12;
localparam [11:0] ROI_Y1_12 = ROI_Y0 + ROI_SIZE_12;

wire [11:0] sample_x = (LOOKAHEAD != 0) ? (video_x + 12'd1) : video_x;
wire [11:0] sample_y = video_y;
wire        sample_active = enable && active_video &&
                            (sample_x >= ROI_X0_12) && (sample_x < ROI_X1_12) &&
                            (sample_y >= ROI_Y0_12) && (sample_y < ROI_Y1_12);

wire [11:0] sample_dx = sample_x - ROI_X0_12;
wire [11:0] sample_dy = sample_y - ROI_Y0_12;

assign mnist_rd_x = sample_dx[SCALE_LOG2 + 4:SCALE_LOG2];
assign mnist_rd_y = sample_dy[SCALE_LOG2 + 4:SCALE_LOG2];
assign mnist_rd_en = sample_active;

generate
if (OUTPUT_ADDR != 0) begin : g_output_addr
    leaf_addr_28_mul_shiftadd u_addr_28 (
        .y(mnist_rd_y),
        .x(mnist_rd_x),
        .addr(mnist_rd_addr)
    );
end else begin : g_no_output_addr
    assign mnist_rd_addr = 10'd0;
end
endgenerate

reg sample_active_d;

always @(posedge pix_clk or negedge rst_n) begin
    if (!rst_n)
        sample_active_d <= 1'b0;
    else
        sample_active_d <= sample_active;
end

assign out_valid = sample_active_d;
assign out_r = sample_active_d ? mnist_rd_data[7:0] : 8'd0;
assign out_g = sample_active_d ? mnist_rd_data[7:0] : 8'd0;
assign out_b = sample_active_d ? mnist_rd_data[7:0] : 8'd0;

endmodule
