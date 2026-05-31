`timescale 1ns/1ps

module camera_byte_packer (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       href,
    input  wire [9:2] pixdata,
    output wire [15:0] pixel_rgb565,
    output wire       pixel_valid
);

wire [9:2] pixdata_d1;
wire       byte_phase;
wire       second_byte = href && byte_phase;
wire       byte_phase_next = href ? ~byte_phase : 1'b0;

leaf_reg_bus_en_rst #(
    .WIDTH(8),
    .RESET_VALUE(8'd0)
) u_prev_byte (
    .clk(clk),
    .rst_n(rst_n),
    .en(href),
    .d(pixdata),
    .q(pixdata_d1)
);

leaf_dff_rst #(.RESET_VALUE(1'b0)) u_byte_phase (
    .clk(clk),
    .rst_n(rst_n),
    .d(byte_phase_next),
    .q(byte_phase)
);

leaf_reg_bus_en_rst #(
    .WIDTH(16),
    .RESET_VALUE(16'd0)
) u_pixel_rgb565 (
    .clk(clk),
    .rst_n(rst_n),
    .en(second_byte),
    .d({pixdata_d1, pixdata}),
    .q(pixel_rgb565)
);

leaf_dff_rst #(.RESET_VALUE(1'b0)) u_pixel_valid (
    .clk(clk),
    .rst_n(rst_n),
    .d(second_byte),
    .q(pixel_valid)
);

endmodule
