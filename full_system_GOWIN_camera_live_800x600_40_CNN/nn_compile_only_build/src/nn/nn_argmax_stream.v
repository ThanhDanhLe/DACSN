`timescale 1ns/1ps
module nn_argmax_stream #(
    parameter DATA_WIDTH = 64,
    parameter INDEX_WIDTH = 4
)(
    input  wire clk,
    input  wire rst_n,
    input  wire clear,
    input  wire valid,
    input  wire signed [DATA_WIDTH-1:0] data_in,
    input  wire [INDEX_WIDTH-1:0] index_in,
    output wire signed [DATA_WIDTH-1:0] max_value,
    output wire [INDEX_WIDTH-1:0] max_index
);

localparam signed [DATA_WIDTH-1:0] MIN_VALUE = {1'b1, {(DATA_WIDTH-1){1'b0}}};

wire take_new_value = valid && (data_in > max_value);
wire load_value = clear || take_new_value;
wire signed [DATA_WIDTH-1:0] max_value_load = clear ? MIN_VALUE : data_in;
wire [INDEX_WIDTH-1:0] max_index_load = clear ? {INDEX_WIDTH{1'b0}} : index_in;

leaf_reg_bus_load_rst #(
    .WIDTH(DATA_WIDTH),
    .RESET_VALUE(MIN_VALUE)
) u_max_value_reg (
    .clk(clk),
    .rst_n(rst_n),
    .load(load_value),
    .d(max_value_load),
    .q(max_value)
);

leaf_reg_bus_load_rst #(
    .WIDTH(INDEX_WIDTH),
    .RESET_VALUE({INDEX_WIDTH{1'b0}})
) u_max_index_reg (
    .clk(clk),
    .rst_n(rst_n),
    .load(load_value),
    .d(max_index_load),
    .q(max_index)
);

endmodule
