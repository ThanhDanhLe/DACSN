`timescale 1ns/1ps
`include "cnn_quant_params.vh"

module cnn_compute_lwdd #(
    parameter ACT_ADDR_WIDTH = 9,
    parameter PARAM_ADDR_WIDTH = 12,
    parameter DEBUG_LOGITS = 1
)(
    input  wire                       clk,
    input  wire                       rst_n,
    input  wire                       start,
    output reg                        busy,
    output reg                        done,
    output reg                        error,
    output reg                        output_valid,
    output reg  [3:0]                 output_class,

    input  wire                       input_wr_en,
    input  wire [ACT_ADDR_WIDTH-1:0]  input_wr_addr,
    input  wire [31:0]                input_wr_data,

    output reg                        image_rd_en,
    output reg  [9:0]                 image_rd_addr,
    input  wire [15:0]                image_rd_data,

    output reg                        param_req,
    output reg  [31:0]                param_word_offset,
    output reg  [15:0]                param_len_words,
    input  wire                       param_ready,
    input  wire                       param_done,
    input  wire                       param_error,
    input  wire [31:0]                param_data,
    input  wire                       param_data_valid,

    output wire [639:0]               debug_logits_flat,
    output wire [5:0]                 debug_state,
    output wire [3:0]                 debug_op,
    output wire [4:0]                 debug_x,
    output wire [4:0]                 debug_y,
    output wire [4:0]                 debug_channel,
    output wire signed [63:0]         debug_accumulator
);

localparam integer FBUF_DEPTH = 784;
localparam integer WCACHE_DEPTH = 512;
localparam integer ACC_WIDTH = 36;

localparam [6:0]
    S_IDLE              = 7'd0,
    S_LOAD_REQ          = 7'd1,
    S_LOAD_STREAM       = 7'd2,
    S_B1_POOL_INIT      = 7'd3,
    S_B1_C2_INIT        = 7'd4,
    S_B1_C2_PREP        = 7'd5,
    S_B1_C2_ACC_SUB     = 7'd6,
    S_B1_C2_WWAIT       = 7'd7,
    S_B1_C2_WACC        = 7'd8,
    S_B1_C2_NEXT        = 7'd9,
    S_B1_C2_DONE        = 7'd10,
    S_B1_C1_INIT        = 7'd11,
    S_B1_C1_PREP        = 7'd12,
    S_B1_C1_WAIT        = 7'd13,
    S_B1_C1_ACC         = 7'd14,
    S_B1_C1_WWAIT       = 7'd15,
    S_B1_C1_WACC        = 7'd16,
    S_B1_C1_NEXT        = 7'd17,
    S_B1_C1_DONE        = 7'd18,
    S_B2_POOL_INIT      = 7'd19,
    S_B2_C4_INIT        = 7'd20,
    S_B2_C4_PREP        = 7'd21,
    S_B2_C4_ACC_SUB     = 7'd22,
    S_B2_C4_WWAIT       = 7'd23,
    S_B2_C4_WACC        = 7'd24,
    S_B2_C4_NEXT        = 7'd25,
    S_B2_C4_DONE        = 7'd26,
    S_B2_C3_INIT        = 7'd27,
    S_B2_C3_PREP        = 7'd28,
    S_B2_C3_WAIT        = 7'd29,
    S_B2_C3_ACC         = 7'd30,
    S_B2_C3_WWAIT       = 7'd31,
    S_B2_C3_WACC        = 7'd32,
    S_B2_C3_NEXT        = 7'd33,
    S_B2_C3_DONE        = 7'd34,
    S_C5_INIT           = 7'd35,
    S_C5_PREP           = 7'd36,
    S_C5_WAIT           = 7'd37,
    S_C5_ACC            = 7'd38,
    S_C5_WWAIT          = 7'd39,
    S_C5_WACC           = 7'd40,
    S_C5_NEXT           = 7'd41,
    S_C5_WRITE          = 7'd42,
    S_C6_LOAD_REQ       = 7'd43,
    S_C6_LOAD_WAIT      = 7'd44,
    S_C6_INIT           = 7'd45,
    S_C6_PREP           = 7'd46,
    S_C6_WAIT           = 7'd47,
    S_C6_ACC            = 7'd48,
    S_C6_WWAIT          = 7'd49,
    S_C6_WACC           = 7'd50,
    S_C6_NEXT           = 7'd51,
    S_C6_DONE_ACT       = 7'd52,
    S_DENSE_INIT        = 7'd53,
    S_DENSE_CLASS_INIT  = 7'd54,
    S_DENSE_BIAS_WAIT   = 7'd55,
    S_DENSE_BIAS_ACC    = 7'd56,
    S_DENSE_MAC         = 7'd57,
    S_DENSE_WWAIT       = 7'd58,
    S_DENSE_WACC        = 7'd59,
    S_DENSE_LOGIT       = 7'd60,
    S_WAIT_ARGMAX       = 7'd61,
    S_DONE              = 7'd62,
    S_ERROR             = 7'd63,
    S_MUL_APPLY         = 7'd64,
    S_C5_TILE_LOAD_REQ  = 7'd65,
    S_C5_TILE_LOAD_WAIT = 7'd66;

localparam [3:0]
    OP_LOAD_B1 = 4'd0,
    OP_POOL1   = 4'd1,
    OP_LOAD_B2 = 4'd2,
    OP_POOL2   = 4'd3,
    OP_LOAD_C5 = 4'd4,
    OP_CONV5   = 4'd5,
    OP_CONV6   = 4'd6,
    OP_DENSE   = 4'd7;

localparam [1:0]
    MUL_TO_ACC   = 2'd0,
    MUL_TO_SUB   = 2'd1,
    MUL_TO_DENSE = 2'd2;

reg [6:0] state;
reg [3:0] op;
reg [6:0] load_next_state;
reg [11:0] load_offset;
reg [8:0] load_len;
reg [8:0] load_count;

reg [4:0] x;
reg [4:0] y;
reg [4:0] ch;
reg [4:0] cout;
reg [4:0] cin;
reg [1:0] ky;
reg [1:0] kx;
reg [1:0] pool_idx;
reg c5_group;
reg signed [ACC_WIDTH-1:0] acc;
reg signed [ACC_WIDTH-1:0] sub_acc;
reg signed [15:0] sub_act;
reg signed [15:0] pool_max;
reg signed [15:0] gpool_max;

reg [4:0] work_y;
reg [4:0] work_x;
reg [4:0] sub_y;
reg [4:0] sub_x;
reg [4:0] sub_ch;
reg [1:0] sub_ky;
reg [1:0] sub_kx;
reg [4:0] sub_cin;

reg signed [15:0] fmap_a_wr_data;
reg [9:0] fmap_a_wr_addr;
reg fmap_a_wr_en;
reg [9:0] fmap_a_rd_addr;
reg fmap_a_rd_en;
wire signed [15:0] fmap_a_rd_data;

reg signed [15:0] fmap_b_wr_data;
reg [9:0] fmap_b_wr_addr;
reg fmap_b_wr_en;
reg [9:0] fmap_b_rd_addr;
reg fmap_b_rd_en;
wire signed [15:0] fmap_b_rd_data;

wire cache_wr_en;
wire [8:0] cache_wr_addr;
wire [31:0] cache_wr_data;
reg cache_rd_en;
reg [8:0] cache_rd_addr;
wire [31:0] cache_rd_data;
reg cache_half_sel;
reg signed [15:0] pending_act;
reg signed [15:0] mul_a;
reg signed [15:0] mul_b;
reg [1:0] mul_target;
reg [6:0] mul_next_state;
wire signed [31:0] mul_product;
wire signed [ACC_WIDTH-1:0] mul_product_acc = {{(ACC_WIDTH-32){mul_product[31]}}, mul_product};

reg signed [ACC_WIDTH-1:0] logits [0:9];
reg signed [15:0] gpool [0:15];
reg [4:0] dense_in_idx;
reg [3:0] dense_out_idx;
reg signed [ACC_WIDTH-1:0] dense_acc;

reg signed [ACC_WIDTH-1:0] best_logit;
reg [3:0] best_class;
reg signed [6:0] src_y_s;
reg signed [6:0] src_x_s;

assign debug_state = (DEBUG_LOGITS != 0) ? state[5:0] : 6'd0;
assign debug_op = (DEBUG_LOGITS != 0) ? op : 4'd0;
assign debug_x = (DEBUG_LOGITS != 0) ? x : 5'd0;
assign debug_y = (DEBUG_LOGITS != 0) ? y : 5'd0;
assign debug_channel = (DEBUG_LOGITS != 0) ? ((op == OP_DENSE) ? dense_in_idx : cout) : 5'd0;
assign debug_accumulator = (DEBUG_LOGITS != 0) ?
                           ((op == OP_DENSE) ?
                            {{(64-ACC_WIDTH){dense_acc[ACC_WIDTH-1]}}, dense_acc} :
                            {{(64-ACC_WIDTH){acc[ACC_WIDTH-1]}}, acc}) :
                           64'd0;

assign debug_logits_flat[ 63:  0] = (DEBUG_LOGITS != 0) ? {{(64-ACC_WIDTH){logits[0][ACC_WIDTH-1]}}, logits[0]} : 64'd0;
assign debug_logits_flat[127: 64] = (DEBUG_LOGITS != 0) ? {{(64-ACC_WIDTH){logits[1][ACC_WIDTH-1]}}, logits[1]} : 64'd0;
assign debug_logits_flat[191:128] = (DEBUG_LOGITS != 0) ? {{(64-ACC_WIDTH){logits[2][ACC_WIDTH-1]}}, logits[2]} : 64'd0;
assign debug_logits_flat[255:192] = (DEBUG_LOGITS != 0) ? {{(64-ACC_WIDTH){logits[3][ACC_WIDTH-1]}}, logits[3]} : 64'd0;
assign debug_logits_flat[319:256] = (DEBUG_LOGITS != 0) ? {{(64-ACC_WIDTH){logits[4][ACC_WIDTH-1]}}, logits[4]} : 64'd0;
assign debug_logits_flat[383:320] = (DEBUG_LOGITS != 0) ? {{(64-ACC_WIDTH){logits[5][ACC_WIDTH-1]}}, logits[5]} : 64'd0;
assign debug_logits_flat[447:384] = (DEBUG_LOGITS != 0) ? {{(64-ACC_WIDTH){logits[6][ACC_WIDTH-1]}}, logits[6]} : 64'd0;
assign debug_logits_flat[511:448] = (DEBUG_LOGITS != 0) ? {{(64-ACC_WIDTH){logits[7][ACC_WIDTH-1]}}, logits[7]} : 64'd0;
assign debug_logits_flat[575:512] = (DEBUG_LOGITS != 0) ? {{(64-ACC_WIDTH){logits[8][ACC_WIDTH-1]}}, logits[8]} : 64'd0;
assign debug_logits_flat[639:576] = (DEBUG_LOGITS != 0) ? {{(64-ACC_WIDTH){logits[9][ACC_WIDTH-1]}}, logits[9]} : 64'd0;

cnn_feature_buffer #(
    .ADDR_WIDTH(10),
    .DEPTH(FBUF_DEPTH)
) u_fmap_a (
    .clk(clk),
    .wr_en(fmap_a_wr_en),
    .wr_addr(fmap_a_wr_addr),
    .wr_data(fmap_a_wr_data),
    .rd_en(fmap_a_rd_en),
    .rd_addr(fmap_a_rd_addr),
    .rd_data(fmap_a_rd_data)
);

cnn_feature_buffer #(
    .ADDR_WIDTH(10),
    .DEPTH(FBUF_DEPTH)
) u_fmap_b (
    .clk(clk),
    .wr_en(fmap_b_wr_en),
    .wr_addr(fmap_b_wr_addr),
    .wr_data(fmap_b_wr_data),
    .rd_en(fmap_b_rd_en),
    .rd_addr(fmap_b_rd_addr),
    .rd_data(fmap_b_rd_data)
);

assign cache_wr_en = (((state == S_LOAD_STREAM) ||
                       (state == S_C5_TILE_LOAD_WAIT) ||
                       (state == S_C6_LOAD_WAIT)) &&
                      param_data_valid);
assign cache_wr_addr = load_count;
assign cache_wr_data = param_data;

cnn_word_cache_buffer #(
    .ADDR_WIDTH(9),
    .DEPTH(WCACHE_DEPTH)
) u_weight_cache (
    .clk(clk),
    .wr_en(cache_wr_en),
    .wr_addr(cache_wr_addr),
    .wr_data(cache_wr_data),
    .rd_en(cache_rd_en),
    .rd_addr(cache_rd_addr),
    .rd_data(cache_rd_data)
);

leaf_multiplier #(
    .A_WIDTH(16),
    .B_WIDTH(16),
    .OUT_WIDTH(32)
) u_cnn_mac_multiplier (
    .a(mul_a),
    .b(mul_b),
    .y(mul_product)
);

wire [9:0] leaf_img28_src_addr;
wire [9:0] leaf_14c4_addr;
wire [9:0] leaf_7c8_addr;
wire [9:0] leaf_7c16_addr;
wire signed [15:0] leaf_cache_i16;
wire signed [ACC_WIDTH-1:0] leaf_cache_acc;
wire signed [15:0] leaf_image_i16;
wire signed [15:0] leaf_acc_relu15;
wire signed [15:0] leaf_acc_relu16;
wire signed [15:0] leaf_sub_acc_relu15;
wire signed [15:0] leaf_sub_acc_relu16;
wire [11:0] leaf_c5_word_offset_out;
wire [11:0] leaf_conv6_word_offset_out;
wire [8:0] leaf_c5_cache_word_out;
wire [10:0] leaf_scalar_c5_out;
wire [10:0] leaf_scalar_c1_out;
wire [10:0] leaf_scalar_c2_out;
wire signed [6:0] b1_c1_src_y_s = $signed({1'b0, sub_y}) + $signed({4'd0, sub_ky}) - 7'sd1;
wire signed [6:0] b1_c1_src_x_s = $signed({1'b0, sub_x}) + $signed({4'd0, sub_kx}) - 7'sd1;
wire signed [6:0] b2_c3_src_y_s = $signed({1'b0, sub_y}) + $signed({4'd0, sub_ky}) - 7'sd1;
wire signed [6:0] b2_c3_src_x_s = $signed({1'b0, sub_x}) + $signed({4'd0, sub_kx}) - 7'sd1;
wire signed [6:0] c5_src_y_s = $signed({1'b0, y}) + $signed({4'd0, ky}) - 7'sd1;
wire signed [6:0] c5_src_x_s = $signed({1'b0, x}) + $signed({4'd0, kx}) - 7'sd1;
wire signed [6:0] c6_src_y_s = $signed({1'b0, y}) + $signed({4'd0, ky}) - 7'sd1;
wire signed [6:0] c6_src_x_s = $signed({1'b0, x}) + $signed({4'd0, kx}) - 7'sd1;
wire leaf_14c4_use_src = (state == S_B2_C3_PREP);
wire leaf_7c8_use_src = (state == S_C5_PREP);
wire leaf_7c16_use_src = (state == S_C6_PREP);
wire [4:0] leaf_14c4_yy = leaf_14c4_use_src ? b2_c3_src_y_s[4:0] : y;
wire [4:0] leaf_14c4_xx = leaf_14c4_use_src ? b2_c3_src_x_s[4:0] : x;
wire [4:0] leaf_14c4_cc = leaf_14c4_use_src ? sub_cin : ch;
wire [4:0] leaf_7c8_yy = leaf_7c8_use_src ? c5_src_y_s[4:0] : y;
wire [4:0] leaf_7c8_xx = leaf_7c8_use_src ? c5_src_x_s[4:0] : x;
wire [4:0] leaf_7c8_cc = leaf_7c8_use_src ? cin : ch;
wire [4:0] leaf_7c16_yy = leaf_7c16_use_src ? c6_src_y_s[4:0] : y;
wire [4:0] leaf_7c16_xx = leaf_7c16_use_src ? c6_src_x_s[4:0] : x;
wire [4:0] leaf_7c16_cc = leaf_7c16_use_src ? cin : cout;

leaf_addr_img28 u_leaf_addr_img28_src (
    .yy(b1_c1_src_y_s[4:0]),
    .xx(b1_c1_src_x_s[4:0]),
    .addr(leaf_img28_src_addr)
);

leaf_addr_14c4 u_leaf_addr_14c4 (
    .yy(leaf_14c4_yy),
    .xx(leaf_14c4_xx),
    .cc(leaf_14c4_cc),
    .addr(leaf_14c4_addr)
);

leaf_addr_7c8 u_leaf_addr_7c8 (
    .yy(leaf_7c8_yy),
    .xx(leaf_7c8_xx),
    .cc(leaf_7c8_cc),
    .addr(leaf_7c8_addr)
);

leaf_addr_7c16 u_leaf_addr_7c16 (
    .yy(leaf_7c16_yy),
    .xx(leaf_7c16_xx),
    .cc(leaf_7c16_cc),
    .addr(leaf_7c16_addr)
);

leaf_c5_word_offset u_leaf_c5_word_offset (
    .idx(load_count),
    .group(c5_group),
    .word_offset(leaf_c5_word_offset_out)
);

leaf_conv6_word_offset u_leaf_conv6_word_offset (
    .idx(load_count),
    .out_ch(cout),
    .word_offset(leaf_conv6_word_offset_out)
);

leaf_c5_cache_word u_leaf_c5_cache_word (
    .ky(ky),
    .kx(kx),
    .cin(cin),
    .cout(cout),
    .cache_word(leaf_c5_cache_word_out)
);

leaf_scalar_c5 u_leaf_scalar_c5 (
    .ky(ky),
    .kx(kx),
    .cin(cin),
    .cout(cout),
    .scalar(leaf_scalar_c5_out)
);

leaf_scalar_c1 u_leaf_scalar_c1 (
    .ky(sub_ky),
    .kx(sub_kx),
    .cout(sub_ch),
    .scalar(leaf_scalar_c1_out)
);

leaf_scalar_c2 u_leaf_scalar_c2 (
    .ky(ky),
    .kx(kx),
    .cin(cin),
    .cout(ch),
    .scalar(leaf_scalar_c2_out)
);

leaf_select_i16 u_leaf_select_cache_i16 (
    .word(cache_rd_data),
    .half_sel(cache_half_sel),
    .out(leaf_cache_i16)
);

leaf_sext32_to_acc #(
    .ACC_WIDTH(ACC_WIDTH)
) u_leaf_sext32_cache (
    .value(cache_rd_data),
    .out(leaf_cache_acc)
);

leaf_input_u8_to_i16 u_leaf_input_image_i16 (
    .pixel_word(image_rd_data),
    .out(leaf_image_i16)
);

leaf_relu_shift_sat #(
    .ACC_WIDTH(ACC_WIDTH),
    .SHIFT(15)
) u_leaf_acc_relu15 (
    .value(acc),
    .out(leaf_acc_relu15)
);

leaf_relu_shift_sat #(
    .ACC_WIDTH(ACC_WIDTH),
    .SHIFT(16)
) u_leaf_acc_relu16 (
    .value(acc),
    .out(leaf_acc_relu16)
);

leaf_relu_shift_sat #(
    .ACC_WIDTH(ACC_WIDTH),
    .SHIFT(15)
) u_leaf_sub_acc_relu15 (
    .value(sub_acc),
    .out(leaf_sub_acc_relu15)
);

leaf_relu_shift_sat #(
    .ACC_WIDTH(ACC_WIDTH),
    .SHIFT(16)
) u_leaf_sub_acc_relu16 (
    .value(sub_acc),
    .out(leaf_sub_acc_relu16)
);

function [10:0] scalar_c3;
    input [1:0] f_ky;
    input [1:0] f_kx;
    input [4:0] f_cin;
    input [4:0] f_cout;
    reg [3:0] kk;
    begin
        kk = {1'b0, f_ky} + {f_ky, 1'b0} + {2'b00, f_kx};
        scalar_c3 = {2'd0, kk, 5'b00000} + {3'd0, f_cin, 3'b000} + {6'd0, f_cout};
    end
endfunction

function [10:0] scalar_c4;
    input [1:0] f_ky;
    input [1:0] f_kx;
    input [4:0] f_cin;
    input [4:0] f_cout;
    reg [3:0] kk;
    begin
        kk = {1'b0, f_ky} + {f_ky, 1'b0} + {2'b00, f_kx};
        scalar_c4 = {1'b0, kk, 6'b000000} + {3'd0, f_cin, 3'b000} + {6'd0, f_cout};
    end
endfunction

function [10:0] scalar_dense;
    input [4:0] in_idx;
    input [3:0] out_idx;
    begin
        scalar_dense = {in_idx, 3'b000} + {in_idx, 1'b0} + out_idx;
    end
endfunction

task start_contiguous_load;
    input [11:0] offset;
    input [8:0] len_words;
    input [6:0] next_state;
    begin
        load_offset <= offset;
        load_len <= len_words;
        load_next_state <= next_state;
        load_count <= 9'd0;
        state <= S_LOAD_REQ;
    end
endtask

task next_3x3_loop;
    input [4:0] max_cin;
    input [6:0] next_state;
    input [6:0] done_state;
    begin
        if ((cin + 5'd1) < max_cin) begin
            cin <= cin + 5'd1;
            state <= next_state;
        end else begin
            cin <= 5'd0;
            if (kx != 2'd2) begin
                kx <= kx + 2'd1;
                state <= next_state;
            end else begin
                kx <= 2'd0;
                if (ky != 2'd2) begin
                    ky <= ky + 2'd1;
                    state <= next_state;
                end else begin
                    ky <= 2'd0;
                    state <= done_state;
                end
            end
        end
    end
endtask

task next_sub_3x3_loop;
    input [4:0] max_cin;
    input [6:0] next_state;
    input [6:0] done_state;
    begin
        if ((sub_cin + 5'd1) < max_cin) begin
            sub_cin <= sub_cin + 5'd1;
            state <= next_state;
        end else begin
            sub_cin <= 5'd0;
            if (sub_kx != 2'd2) begin
                sub_kx <= sub_kx + 2'd1;
                state <= next_state;
            end else begin
                sub_kx <= 2'd0;
                if (sub_ky != 2'd2) begin
                    sub_ky <= sub_ky + 2'd1;
                    state <= next_state;
                end else begin
                    sub_ky <= 2'd0;
                    state <= done_state;
                end
            end
        end
    end
endtask

integer i;
reg [10:0] scalar;
reg [8:0] cache_addr;
reg signed [15:0] weight_value;
reg signed [15:0] act_value;
reg signed [15:0] next_pool_max;
reg signed [15:0] next_gpool_max;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;
        op <= OP_LOAD_B1;
        load_next_state <= S_IDLE;
        load_offset <= 12'd0;
        load_len <= 9'd0;
        load_count <= 9'd0;
        x <= 5'd0;
        y <= 5'd0;
        ch <= 5'd0;
        cout <= 5'd0;
        cin <= 5'd0;
        ky <= 2'd0;
        kx <= 2'd0;
        pool_idx <= 2'd0;
        c5_group <= 1'b0;
        acc <= {ACC_WIDTH{1'b0}};
        sub_acc <= {ACC_WIDTH{1'b0}};
        sub_act <= 16'sd0;
        pool_max <= 16'sd0;
        gpool_max <= 16'sd0;
        work_y <= 5'd0;
        work_x <= 5'd0;
        sub_y <= 5'd0;
        sub_x <= 5'd0;
        sub_ch <= 5'd0;
        sub_ky <= 2'd0;
        sub_kx <= 2'd0;
        sub_cin <= 5'd0;
        fmap_a_wr_en <= 1'b0;
        fmap_a_wr_addr <= 10'd0;
        fmap_a_wr_data <= 16'sd0;
        fmap_a_rd_en <= 1'b0;
        fmap_a_rd_addr <= 10'd0;
        fmap_b_wr_en <= 1'b0;
        fmap_b_wr_addr <= 10'd0;
        fmap_b_wr_data <= 16'sd0;
        fmap_b_rd_en <= 1'b0;
        fmap_b_rd_addr <= 10'd0;
        cache_rd_en <= 1'b0;
        cache_rd_addr <= 9'd0;
        cache_half_sel <= 1'b0;
        pending_act <= 16'sd0;
        mul_a <= 16'sd0;
        mul_b <= 16'sd0;
        mul_target <= MUL_TO_ACC;
        mul_next_state <= S_IDLE;
        image_rd_en <= 1'b0;
        image_rd_addr <= 10'd0;
        param_req <= 1'b0;
        param_word_offset <= 32'd0;
        param_len_words <= 16'd0;
        dense_in_idx <= 5'd0;
        dense_out_idx <= 4'd0;
        dense_acc <= {ACC_WIDTH{1'b0}};
        best_logit <= {1'b1, {(ACC_WIDTH-1){1'b0}}};
        best_class <= 4'd0;
        busy <= 1'b0;
        done <= 1'b0;
        error <= 1'b0;
        output_valid <= 1'b0;
        output_class <= 4'd0;
        for (i = 0; i < 10; i = i + 1)
            logits[i] <= {ACC_WIDTH{1'b0}};
        for (i = 0; i < 16; i = i + 1)
            gpool[i] <= 16'sd0;
    end else begin
        done <= 1'b0;
        output_valid <= 1'b0;
        fmap_a_wr_en <= 1'b0;
        fmap_a_rd_en <= 1'b0;
        fmap_b_wr_en <= 1'b0;
        fmap_b_rd_en <= 1'b0;
        cache_rd_en <= 1'b0;
        image_rd_en <= 1'b0;
        param_req <= 1'b0;

        case (state)
            S_IDLE: begin
                busy <= 1'b0;
                error <= 1'b0;
                if (start) begin
                    busy <= 1'b1;
                    op <= OP_LOAD_B1;
                    start_contiguous_load(12'd0, 9'd90, S_B1_POOL_INIT);
                end
            end

            S_LOAD_REQ: begin
                if (param_ready) begin
                    param_req <= 1'b1;
                    param_word_offset <= {20'd0, load_offset};
                    param_len_words <= {7'd0, load_len};
                    state <= S_LOAD_STREAM;
                end
            end

            S_LOAD_STREAM: begin
                if (param_error) begin
                    state <= S_ERROR;
                end else begin
                    if (param_data_valid) begin
                        load_count <= load_count + 9'd1;
                    end
                    if (param_done) begin
                        op <= (load_next_state == S_B1_POOL_INIT) ? OP_POOL1 :
                              (load_next_state == S_B2_POOL_INIT) ? OP_POOL2 :
                              (load_next_state == S_C5_INIT)      ? OP_CONV5 :
                              (load_next_state == S_DENSE_INIT)   ? OP_DENSE : op;
                        state <= load_next_state;
                    end
                end
            end

            S_B1_POOL_INIT: begin
                x <= 5'd0;
                y <= 5'd0;
                ch <= 5'd0;
                pool_idx <= 2'd0;
                pool_max <= 16'sd0;
                state <= S_B1_C2_INIT;
            end

            S_B1_C2_INIT: begin
                work_y <= {y[3:0], 1'b0} + {4'd0, pool_idx[1]};
                work_x <= {x[3:0], 1'b0} + {4'd0, pool_idx[0]};
                acc <= {ACC_WIDTH{1'b0}};
                ky <= 2'd0;
                kx <= 2'd0;
                cin <= 5'd0;
                state <= S_B1_C2_PREP;
            end

            S_B1_C2_PREP: begin
                src_y_s = $signed({1'b0, work_y}) + $signed({4'd0, ky}) - 7'sd1;
                src_x_s = $signed({1'b0, work_x}) + $signed({4'd0, kx}) - 7'sd1;
                if (((work_y != 5'd0)  || (ky != 2'd0)) &&
                    ((work_y != 5'd27) || (ky != 2'd2)) &&
                    ((work_x != 5'd0)  || (kx != 2'd0)) &&
                    ((work_x != 5'd27) || (kx != 2'd2))) begin
                    sub_y <= src_y_s[4:0];
                    sub_x <= src_x_s[4:0];
                    sub_ch <= cin;
                    state <= S_B1_C1_INIT;
                end else begin
                    state <= S_B1_C2_NEXT;
                end
            end

            S_B1_C2_ACC_SUB: begin
                scalar = leaf_scalar_c2_out;
                cache_rd_en <= 1'b1;
                cache_rd_addr <= 9'd18 + scalar[9:1];
                cache_half_sel <= scalar[0];
                pending_act <= sub_act;
                state <= S_B1_C2_WWAIT;
            end

            S_B1_C2_WWAIT: begin
                state <= S_B1_C2_WACC;
            end

            S_B1_C2_WACC: begin
                weight_value = leaf_cache_i16;
                mul_a <= pending_act;
                mul_b <= weight_value;
                mul_target <= MUL_TO_ACC;
                mul_next_state <= S_B1_C2_NEXT;
                state <= S_MUL_APPLY;
            end

            S_B1_C2_NEXT: begin
                next_3x3_loop(5'd4, S_B1_C2_PREP, S_B1_C2_DONE);
            end

            S_B1_C2_DONE: begin
                act_value = leaf_acc_relu16;
                if ((pool_idx == 2'd0) || (act_value > pool_max))
                    next_pool_max = act_value;
                else
                    next_pool_max = pool_max;
                pool_max <= next_pool_max;

                if (pool_idx == 2'd3) begin
                    fmap_a_wr_en <= 1'b1;
                    fmap_a_wr_addr <= leaf_14c4_addr;
                    fmap_a_wr_data <= next_pool_max;
                    pool_idx <= 2'd0;
                    pool_max <= 16'sd0;
                    if (ch != 5'd3) begin
                        ch <= ch + 5'd1;
                        state <= S_B1_C2_INIT;
                    end else begin
                        ch <= 5'd0;
                        if (x != 5'd13) begin
                            x <= x + 5'd1;
                            state <= S_B1_C2_INIT;
                        end else begin
                            x <= 5'd0;
                            if (y != 5'd13) begin
                                y <= y + 5'd1;
                                state <= S_B1_C2_INIT;
                            end else begin
                                y <= 5'd0;
                                op <= OP_LOAD_B2;
                                start_contiguous_load(12'd90, 9'd432, S_B2_POOL_INIT);
                            end
                        end
                    end
                end else begin
                    pool_idx <= pool_idx + 2'd1;
                    state <= S_B1_C2_INIT;
                end
            end

            S_B1_C1_INIT: begin
                sub_acc <= {ACC_WIDTH{1'b0}};
                sub_ky <= 2'd0;
                sub_kx <= 2'd0;
                sub_cin <= 5'd0;
                state <= S_B1_C1_PREP;
            end

            S_B1_C1_PREP: begin
                src_y_s = $signed({1'b0, sub_y}) + $signed({4'd0, sub_ky}) - 7'sd1;
                src_x_s = $signed({1'b0, sub_x}) + $signed({4'd0, sub_kx}) - 7'sd1;
                if (((sub_y != 5'd0)  || (sub_ky != 2'd0)) &&
                    ((sub_y != 5'd27) || (sub_ky != 2'd2)) &&
                    ((sub_x != 5'd0)  || (sub_kx != 2'd0)) &&
                    ((sub_x != 5'd27) || (sub_kx != 2'd2))) begin
                    image_rd_en <= 1'b1;
                    image_rd_addr <= leaf_img28_src_addr;
                    state <= S_B1_C1_WAIT;
                end else begin
                    state <= S_B1_C1_NEXT;
                end
            end

            S_B1_C1_WAIT: begin
                state <= S_B1_C1_ACC;
            end

            S_B1_C1_ACC: begin
                scalar = leaf_scalar_c1_out;
                cache_rd_en <= 1'b1;
                cache_rd_addr <= scalar[9:1];
                cache_half_sel <= scalar[0];
                pending_act <= leaf_image_i16;
                state <= S_B1_C1_WWAIT;
            end

            S_B1_C1_WWAIT: begin
                state <= S_B1_C1_WACC;
            end

            S_B1_C1_WACC: begin
                weight_value = leaf_cache_i16;
                mul_a <= pending_act;
                mul_b <= weight_value;
                mul_target <= MUL_TO_SUB;
                mul_next_state <= S_B1_C1_NEXT;
                state <= S_MUL_APPLY;
            end

            S_B1_C1_NEXT: begin
                next_sub_3x3_loop(5'd1, S_B1_C1_PREP, S_B1_C1_DONE);
            end

            S_B1_C1_DONE: begin
                sub_act <= leaf_sub_acc_relu15;
                state <= S_B1_C2_ACC_SUB;
            end

            S_B2_POOL_INIT: begin
                x <= 5'd0;
                y <= 5'd0;
                ch <= 5'd0;
                pool_idx <= 2'd0;
                pool_max <= 16'sd0;
                state <= S_B2_C4_INIT;
            end

            S_B2_C4_INIT: begin
                work_y <= {y[3:0], 1'b0} + {4'd0, pool_idx[1]};
                work_x <= {x[3:0], 1'b0} + {4'd0, pool_idx[0]};
                acc <= {ACC_WIDTH{1'b0}};
                ky <= 2'd0;
                kx <= 2'd0;
                cin <= 5'd0;
                state <= S_B2_C4_PREP;
            end

            S_B2_C4_PREP: begin
                src_y_s = $signed({1'b0, work_y}) + $signed({4'd0, ky}) - 7'sd1;
                src_x_s = $signed({1'b0, work_x}) + $signed({4'd0, kx}) - 7'sd1;
                if (((work_y != 5'd0)  || (ky != 2'd0)) &&
                    ((work_y != 5'd13) || (ky != 2'd2)) &&
                    ((work_x != 5'd0)  || (kx != 2'd0)) &&
                    ((work_x != 5'd13) || (kx != 2'd2))) begin
                    sub_y <= src_y_s[4:0];
                    sub_x <= src_x_s[4:0];
                    sub_ch <= cin;
                    state <= S_B2_C3_INIT;
                end else begin
                    state <= S_B2_C4_NEXT;
                end
            end

            S_B2_C4_ACC_SUB: begin
                scalar = scalar_c4(ky, kx, cin, ch);
                cache_rd_en <= 1'b1;
                cache_rd_addr <= 9'd144 + scalar[9:1];
                cache_half_sel <= scalar[0];
                pending_act <= sub_act;
                state <= S_B2_C4_WWAIT;
            end

            S_B2_C4_WWAIT: begin
                state <= S_B2_C4_WACC;
            end

            S_B2_C4_WACC: begin
                weight_value = leaf_cache_i16;
                mul_a <= pending_act;
                mul_b <= weight_value;
                mul_target <= MUL_TO_ACC;
                mul_next_state <= S_B2_C4_NEXT;
                state <= S_MUL_APPLY;
            end

            S_B2_C4_NEXT: begin
                next_3x3_loop(5'd8, S_B2_C4_PREP, S_B2_C4_DONE);
            end

            S_B2_C4_DONE: begin
                act_value = leaf_acc_relu16;
                if ((pool_idx == 2'd0) || (act_value > pool_max))
                    next_pool_max = act_value;
                else
                    next_pool_max = pool_max;
                pool_max <= next_pool_max;

                if (pool_idx == 2'd3) begin
                    fmap_b_wr_en <= 1'b1;
                    fmap_b_wr_addr <= leaf_7c8_addr;
                    fmap_b_wr_data <= next_pool_max;
                    pool_idx <= 2'd0;
                    pool_max <= 16'sd0;
                    if (ch != 5'd7) begin
                        ch <= ch + 5'd1;
                        state <= S_B2_C4_INIT;
                    end else begin
                        ch <= 5'd0;
                        if (x != 5'd6) begin
                            x <= x + 5'd1;
                            state <= S_B2_C4_INIT;
                        end else begin
                            x <= 5'd0;
                            if (y != 5'd6) begin
                                y <= y + 5'd1;
                                state <= S_B2_C4_INIT;
                            end else begin
                                y <= 5'd0;
                                op <= OP_LOAD_C5;
                                c5_group <= 1'b0;
                                load_count <= 9'd0;
                                op <= OP_LOAD_C5;
                                state <= S_C5_TILE_LOAD_REQ;
                            end
                        end
                    end
                end else begin
                    pool_idx <= pool_idx + 2'd1;
                    state <= S_B2_C4_INIT;
                end
            end

            S_B2_C3_INIT: begin
                sub_acc <= {ACC_WIDTH{1'b0}};
                sub_ky <= 2'd0;
                sub_kx <= 2'd0;
                sub_cin <= 5'd0;
                state <= S_B2_C3_PREP;
            end

            S_B2_C3_PREP: begin
                src_y_s = $signed({1'b0, sub_y}) + $signed({4'd0, sub_ky}) - 7'sd1;
                src_x_s = $signed({1'b0, sub_x}) + $signed({4'd0, sub_kx}) - 7'sd1;
                if (((sub_y != 5'd0)  || (sub_ky != 2'd0)) &&
                    ((sub_y != 5'd13) || (sub_ky != 2'd2)) &&
                    ((sub_x != 5'd0)  || (sub_kx != 2'd0)) &&
                    ((sub_x != 5'd13) || (sub_kx != 2'd2))) begin
                    fmap_a_rd_en <= 1'b1;
                    fmap_a_rd_addr <= leaf_14c4_addr;
                    state <= S_B2_C3_WAIT;
                end else begin
                    state <= S_B2_C3_NEXT;
                end
            end

            S_B2_C3_WAIT: begin
                state <= S_B2_C3_ACC;
            end

            S_B2_C3_ACC: begin
                scalar = scalar_c3(sub_ky, sub_kx, sub_cin, sub_ch);
                cache_rd_en <= 1'b1;
                cache_rd_addr <= scalar[9:1];
                cache_half_sel <= scalar[0];
                pending_act <= fmap_a_rd_data;
                state <= S_B2_C3_WWAIT;
            end

            S_B2_C3_WWAIT: begin
                state <= S_B2_C3_WACC;
            end

            S_B2_C3_WACC: begin
                weight_value = leaf_cache_i16;
                mul_a <= pending_act;
                mul_b <= weight_value;
                mul_target <= MUL_TO_SUB;
                mul_next_state <= S_B2_C3_NEXT;
                state <= S_MUL_APPLY;
            end

            S_B2_C3_NEXT: begin
                next_sub_3x3_loop(5'd4, S_B2_C3_PREP, S_B2_C3_DONE);
            end

            S_B2_C3_DONE: begin
                sub_act <= leaf_sub_acc_relu16;
                state <= S_B2_C4_ACC_SUB;
            end

            S_C5_TILE_LOAD_REQ: begin
                if (param_ready) begin
                    param_req <= 1'b1;
                    param_word_offset <= {20'd0, leaf_c5_word_offset_out};
                    param_len_words <= 16'd1;
                    state <= S_C5_TILE_LOAD_WAIT;
                end
            end

            S_C5_TILE_LOAD_WAIT: begin
                if (param_error) begin
                    state <= S_ERROR;
                end else begin
                    if (param_done) begin
                        if (load_count == 9'd287) begin
                            state <= S_C5_INIT;
                        end else begin
                            load_count <= load_count + 9'd1;
                            state <= S_C5_TILE_LOAD_REQ;
                        end
                    end
                end
            end

            S_C5_INIT: begin
                op <= OP_CONV5;
                x <= 5'd0;
                y <= 5'd0;
                cout <= c5_group ? 5'd8 : 5'd0;
                cin <= 5'd0;
                ky <= 2'd0;
                kx <= 2'd0;
                acc <= {ACC_WIDTH{1'b0}};
                state <= S_C5_PREP;
            end

            S_C5_PREP: begin
                src_y_s = $signed({1'b0, y}) + $signed({4'd0, ky}) - 7'sd1;
                src_x_s = $signed({1'b0, x}) + $signed({4'd0, kx}) - 7'sd1;
                if (((y != 5'd0) || (ky != 2'd0)) &&
                    ((y != 5'd6) || (ky != 2'd2)) &&
                    ((x != 5'd0) || (kx != 2'd0)) &&
                    ((x != 5'd6) || (kx != 2'd2))) begin
                    fmap_b_rd_en <= 1'b1;
                    fmap_b_rd_addr <= leaf_7c8_addr;
                    state <= S_C5_WAIT;
                end else begin
                    state <= S_C5_NEXT;
                end
            end

            S_C5_WAIT: begin
                state <= S_C5_ACC;
            end

            S_C5_ACC: begin
                scalar = leaf_scalar_c5_out;
                cache_rd_en <= 1'b1;
                cache_rd_addr <= leaf_c5_cache_word_out;
                cache_half_sel <= scalar[0];
                pending_act <= fmap_b_rd_data;
                state <= S_C5_WWAIT;
            end

            S_C5_WWAIT: begin
                state <= S_C5_WACC;
            end

            S_C5_WACC: begin
                weight_value = leaf_cache_i16;
                mul_a <= pending_act;
                mul_b <= weight_value;
                mul_target <= MUL_TO_ACC;
                mul_next_state <= S_C5_NEXT;
                state <= S_MUL_APPLY;
            end

            S_C5_NEXT: begin
                next_3x3_loop(5'd8, S_C5_PREP, S_C5_WRITE);
            end

            S_C5_WRITE: begin
                fmap_a_wr_en <= 1'b1;
                fmap_a_wr_addr <= leaf_7c16_addr;
                fmap_a_wr_data <= leaf_acc_relu16;
                acc <= {ACC_WIDTH{1'b0}};
                if (cout != (c5_group ? 5'd15 : 5'd7)) begin
                    cout <= cout + 5'd1;
                    state <= S_C5_PREP;
                end else begin
                    cout <= c5_group ? 5'd8 : 5'd0;
                    if (x != 5'd6) begin
                        x <= x + 5'd1;
                        state <= S_C5_PREP;
                    end else begin
                        x <= 5'd0;
                        if (y != 5'd6) begin
                            y <= y + 5'd1;
                            state <= S_C5_PREP;
                        end else begin
                            y <= 5'd0;
                            if (!c5_group) begin
                                c5_group <= 1'b1;
                                load_count <= 9'd0;
                                op <= OP_LOAD_C5;
                                state <= S_C5_TILE_LOAD_REQ;
                            end else begin
                                cout <= 5'd0;
                                load_count <= 9'd0;
                                op <= OP_CONV6;
                                state <= S_C6_LOAD_REQ;
                            end
                        end
                    end
                end
            end

            S_C6_LOAD_REQ: begin
                if (param_ready) begin
                    param_req <= 1'b1;
                    param_word_offset <= {20'd0, leaf_conv6_word_offset_out};
                    param_len_words <= 16'd1;
                    state <= S_C6_LOAD_WAIT;
                end
            end

            S_C6_LOAD_WAIT: begin
                if (param_error) begin
                    state <= S_ERROR;
                end else begin
                    if (param_done) begin
                        if (load_count == 9'd143) begin
                            state <= S_C6_INIT;
                        end else begin
                            load_count <= load_count + 9'd1;
                            state <= S_C6_LOAD_REQ;
                        end
                    end
                end
            end

            S_C6_INIT: begin
                x <= 5'd0;
                y <= 5'd0;
                cin <= 5'd0;
                ky <= 2'd0;
                kx <= 2'd0;
                acc <= {ACC_WIDTH{1'b0}};
                gpool_max <= 16'sd0;
                state <= S_C6_PREP;
            end

            S_C6_PREP: begin
                src_y_s = $signed({1'b0, y}) + $signed({4'd0, ky}) - 7'sd1;
                src_x_s = $signed({1'b0, x}) + $signed({4'd0, kx}) - 7'sd1;
                if (((y != 5'd0) || (ky != 2'd0)) &&
                    ((y != 5'd6) || (ky != 2'd2)) &&
                    ((x != 5'd0) || (kx != 2'd0)) &&
                    ((x != 5'd6) || (kx != 2'd2))) begin
                    fmap_a_rd_en <= 1'b1;
                    fmap_a_rd_addr <= leaf_7c16_addr;
                    state <= S_C6_WAIT;
                end else begin
                    state <= S_C6_NEXT;
                end
            end

            S_C6_WAIT: begin
                state <= S_C6_ACC;
            end

            S_C6_ACC: begin
                cache_addr = ((({5'd0, ky} << 1) + ky + kx) << 4) + cin;
                cache_rd_en <= 1'b1;
                cache_rd_addr <= cache_addr;
                cache_half_sel <= cout[0];
                pending_act <= fmap_a_rd_data;
                state <= S_C6_WWAIT;
            end

            S_C6_WWAIT: begin
                state <= S_C6_WACC;
            end

            S_C6_WACC: begin
                weight_value = leaf_cache_i16;
                mul_a <= pending_act;
                mul_b <= weight_value;
                mul_target <= MUL_TO_ACC;
                mul_next_state <= S_C6_NEXT;
                state <= S_MUL_APPLY;
            end

            S_C6_NEXT: begin
                next_3x3_loop(5'd16, S_C6_PREP, S_C6_DONE_ACT);
            end

            S_C6_DONE_ACT: begin
                act_value = leaf_acc_relu16;
                if (((x == 5'd0) && (y == 5'd0)) || (act_value > gpool_max))
                    next_gpool_max = act_value;
                else
                    next_gpool_max = gpool_max;
                gpool_max <= next_gpool_max;
                acc <= {ACC_WIDTH{1'b0}};

                if (x != 5'd6) begin
                    x <= x + 5'd1;
                    state <= S_C6_PREP;
                end else begin
                    x <= 5'd0;
                    if (y != 5'd6) begin
                        y <= y + 5'd1;
                        state <= S_C6_PREP;
                    end else begin
                        y <= 5'd0;
                        gpool[cout] <= next_gpool_max;
                        if (cout == 5'd15) begin
                            start_contiguous_load(12'd2250, 9'd90, S_DENSE_INIT);
                        end else begin
                            cout <= cout + 5'd1;
                            if (cout[0] == 1'b0) begin
                                state <= S_C6_INIT;
                            end else begin
                                load_count <= 9'd0;
                                state <= S_C6_LOAD_REQ;
                            end
                        end
                    end
                end
            end

            S_DENSE_INIT: begin
                op <= OP_DENSE;
                dense_out_idx <= 4'd0;
                dense_in_idx <= 5'd0;
                best_logit <= {1'b1, {(ACC_WIDTH-1){1'b0}}};
                best_class <= 4'd0;
                state <= S_DENSE_CLASS_INIT;
            end

            S_DENSE_CLASS_INIT: begin
                dense_in_idx <= 5'd0;
                cache_rd_en <= 1'b1;
                cache_rd_addr <= 9'd80 + {5'd0, dense_out_idx};
                state <= S_DENSE_BIAS_WAIT;
            end

            S_DENSE_BIAS_WAIT: begin
                state <= S_DENSE_BIAS_ACC;
            end

            S_DENSE_BIAS_ACC: begin
                dense_acc <= leaf_cache_acc >>> `CNN_DENSE_BIAS_SHIFT;
                state <= S_DENSE_MAC;
            end

            S_DENSE_MAC: begin
                scalar = scalar_dense(dense_in_idx, dense_out_idx);
                cache_rd_en <= 1'b1;
                cache_rd_addr <= scalar[9:1];
                cache_half_sel <= scalar[0];
                pending_act <= gpool[dense_in_idx];
                state <= S_DENSE_WWAIT;
            end

            S_DENSE_WWAIT: begin
                state <= S_DENSE_WACC;
            end

            S_DENSE_WACC: begin
                weight_value = leaf_cache_i16;
                mul_a <= pending_act;
                mul_b <= weight_value;
                mul_target <= MUL_TO_DENSE;
                if (dense_in_idx != 5'd15) begin
                    dense_in_idx <= dense_in_idx + 5'd1;
                    mul_next_state <= S_DENSE_MAC;
                end else begin
                    mul_next_state <= S_DENSE_LOGIT;
                end
                state <= S_MUL_APPLY;
            end

            S_MUL_APPLY: begin
                case (mul_target)
                    MUL_TO_SUB:   sub_acc <= sub_acc + mul_product_acc;
                    MUL_TO_DENSE: dense_acc <= dense_acc + mul_product_acc;
                    default:      acc <= acc + mul_product_acc;
                endcase
                state <= mul_next_state;
            end

            S_DENSE_LOGIT: begin
                if (DEBUG_LOGITS != 0)
                    logits[dense_out_idx] <= dense_acc;
                if ((dense_out_idx == 4'd0) || (dense_acc > best_logit)) begin
                    best_logit <= dense_acc;
                    best_class <= dense_out_idx;
                end
                if (dense_out_idx != 4'd9) begin
                    dense_out_idx <= dense_out_idx + 4'd1;
                    state <= S_DENSE_CLASS_INIT;
                end else begin
                    if ((dense_out_idx == 4'd0) || (dense_acc > best_logit))
                        output_class <= dense_out_idx;
                    else
                        output_class <= best_class;
                    output_valid <= 1'b1;
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= S_DONE;
                end
            end

            S_DONE: begin
                if (!start)
                    state <= S_IDLE;
            end

            S_ERROR: begin
                busy <= 1'b0;
                error <= 1'b1;
                if (!start)
                    state <= S_IDLE;
            end

            default: begin
                state <= S_ERROR;
            end
        endcase
    end
end

wire width_unused = ^PARAM_ADDR_WIDTH;

endmodule
