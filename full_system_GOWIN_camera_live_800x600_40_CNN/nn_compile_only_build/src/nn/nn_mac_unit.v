`timescale 1ns/1ps
// Signed int16 x signed int16 -> signed int64 product helper.
// This module is combinational on purpose; the parent FSM owns the accumulator.
module nn_mac_unit #(
    parameter ACT_WIDTH = 16,
    parameter W_WIDTH   = 16,
    parameter PROD_WIDTH = 64
)(
    input  wire signed [ACT_WIDTH-1:0] act_in,
    input  wire signed [W_WIDTH-1:0]   weight_in,
    output wire signed [PROD_WIDTH-1:0] product_out
);

localparam RAW_PRODUCT_WIDTH = ACT_WIDTH + W_WIDTH;

wire signed [RAW_PRODUCT_WIDTH-1:0] product_raw;

leaf_multiplier #(
    .A_WIDTH(ACT_WIDTH),
    .B_WIDTH(W_WIDTH),
    .OUT_WIDTH(RAW_PRODUCT_WIDTH)
) u_multiplier (
    .a(act_in),
    .b(weight_in),
    .y(product_raw)
);

assign product_out = {{(PROD_WIDTH-RAW_PRODUCT_WIDTH){product_raw[RAW_PRODUCT_WIDTH-1]}}, product_raw};

endmodule
