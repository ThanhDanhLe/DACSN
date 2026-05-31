`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// nn_compute_mlp16_pocket.v
// Modular 3-layer MLP compute engine using helper submodules:
//   nn_bram_sdp          : input/hidden activation buffers, packed 2 int16/word
//   nn_weight16_unpack2  : selects low/high signed int16 from param_data
//   local sign extension: sign-extends int32 bias to int64
//   nn_mac_unit          : signed int16 x signed int16 -> signed int64 product
//   nn_pocket_tanh_activation_seq : exact PocketNN pocket_tanh activation
//   nn_argmax_stream     : final pocket_tanh-output argmax
//
// Data format:
//   weight      = signed int16, two per 32-bit word
//   bias        = signed int32, one per 32-bit word
//   activation  = signed int16, two per 32-bit word
//   accumulator = signed int64
// Default weight layout in Flash/PSRAM is input-major:
//   scalar_index = input_index * OUT_SIZE + output_index
//   param_word_offset = scalar_index / 2
//   lane_sel = scalar_index[0]
// DIRECT_SPI_PARAM_STREAM can select node-contiguous layer blocks:
//   for each output node: int32 bias, then packed int16 weights by input index
// -----------------------------------------------------------------------------
module nn_compute_mlp16_pocket #(
    parameter IN_SIZE   = 784,
    parameter L1_OUT    = 100,
    parameter L2_OUT    = 50,
    parameter L3_OUT    = 10,
    parameter ACT_ADDR_WIDTH = 10,
    parameter PARAM_LAYOUT_NODE_CONTIGUOUS = 0
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire loader_done,
    output reg  busy,
    output reg  done,
    output reg  error,
    output reg  [3:0] predict_class,
    output reg        predict_valid,

    input  wire                      input_wr_en,
    input  wire [ACT_ADDR_WIDTH-1:0] input_wr_addr,
    input  wire [31:0]               input_wr_data,

    output reg         param_req,
    output reg  [2:0]  param_layer,
    output reg         param_is_bias,
    output reg  [31:0] param_word_offset,
    output wire [15:0] param_len_words,
    output wire        param_data_ready,

    input  wire        param_ready,
    input  wire        param_busy,
    input  wire        param_done,
    input  wire        param_error,
    input  wire [31:0] param_data,
    input  wire        param_data_valid
);
    assign param_len_words = 16'd1;

    localparam [5:0]
        S_IDLE       = 6'd0,
        S_L1_INIT    = 6'd1,  S_L1_PREP      = 6'd2,  S_L1_WAIT_W    = 6'd3,
        S_L1_B_REQ   = 6'd4,  S_L1_B_WAIT    = 6'd5,  S_L1_ACT_START = 6'd6,
        S_L1_ACT_WAIT= 6'd7,  S_L1_WRITE     = 6'd8,
        S_L2_INIT    = 6'd9,  S_L2_PREP      = 6'd10, S_L2_WAIT_W    = 6'd11,
        S_L2_B_REQ   = 6'd12, S_L2_B_WAIT    = 6'd13, S_L2_ACT_START = 6'd14,
        S_L2_ACT_WAIT= 6'd15, S_L2_WRITE     = 6'd16,
        S_L3_INIT    = 6'd17, S_L3_PREP      = 6'd18, S_L3_WAIT_W    = 6'd19,
        S_L3_B_REQ   = 6'd20, S_L3_B_WAIT    = 6'd21, S_L3_ACT_START = 6'd22,
        S_L3_ACT_WAIT= 6'd23, S_L3_SCORE     = 6'd24,
        S_L3_ARGMAX_WAIT = 6'd25,
        S_L3_FINAL       = 6'd26,
        S_DONE           = 6'd27,
        S_ERROR          = 6'd28;

    reg [5:0] state;
    assign param_data_ready = (state == S_L1_WAIT_W) || (state == S_L1_B_WAIT) ||
                              (state == S_L2_WAIT_W) || (state == S_L2_B_WAIT) ||
                              (state == S_L3_WAIT_W) || (state == S_L3_B_WAIT);

    function [15:0] u16_cast;
        input integer value;
        begin
            u16_cast = value[15:0];
        end
    endfunction

    localparam [15:0] IN_SIZE_16 = u16_cast(IN_SIZE);
    localparam [15:0] L1_OUT_16  = u16_cast(L1_OUT);
    localparam [15:0] L2_OUT_16  = u16_cast(L2_OUT);
    localparam [15:0] L3_OUT_16  = u16_cast(L3_OUT);
    localparam [15:0] IN_SIZE_LAST = IN_SIZE_16 - 16'd1;
    localparam [15:0] L1_OUT_LAST  = L1_OUT_16  - 16'd1;
    localparam [15:0] L2_OUT_LAST  = L2_OUT_16  - 16'd1;
    localparam [15:0] L3_OUT_LAST  = L3_OUT_16  - 16'd1;

    localparam integer ACT_MEM_WORDS = (1 << ACT_ADDR_WIDTH);
    localparam integer INPUT_WORDS_NEEDED = (IN_SIZE + 1) / 2;
    localparam integer L1_WORDS_NEEDED = (L1_OUT + 1) / 2;
    localparam integer L2_WORDS_NEEDED = (L2_OUT + 1) / 2;

    // synthesis translate_off
    initial begin
        if ((INPUT_WORDS_NEEDED > ACT_MEM_WORDS) ||
            (L1_WORDS_NEEDED > ACT_MEM_WORDS) ||
            (L2_WORDS_NEEDED > ACT_MEM_WORDS)) begin
            $display("FAIL nn_compute_mlp16: ACT_ADDR_WIDTH=%0d is too small (need input=%0d, l1=%0d, l2=%0d words)",
                     ACT_ADDR_WIDTH, INPUT_WORDS_NEEDED, L1_WORDS_NEEDED, L2_WORDS_NEEDED);
            $stop;
        end
    end
    // synthesis translate_on

    reg start_d;
    wire start_rise = start & ~start_d;

    reg [15:0] i_idx, o_idx;
    reg signed [63:0] acc;
    reg signed [63:0] score_with_bias_r;
    reg [3:0] score_index_r;
    reg [31:0] act_pack_temp;
    reg        weight_half_sel;

    // BSRAM ports
    reg input_rd_en, act1_rd_en, act2_rd_en;
    reg [ACT_ADDR_WIDTH-1:0] input_rd_addr, act1_rd_addr, act2_rd_addr;
    wire [31:0] input_rd_data, act1_rd_data, act2_rd_data;
    reg act1_wr_en, act2_wr_en;
    reg [ACT_ADDR_WIDTH-1:0] act1_wr_addr, act2_wr_addr;
    reg [31:0] act1_wr_data, act2_wr_data;

    nn_bram_sdp #(.ADDR_WIDTH(ACT_ADDR_WIDTH), .DATA_WIDTH(32)) u_input_bram (
        .clk(clk), .rst_n(rst_n), .wr_en(input_wr_en), .wr_addr(input_wr_addr),
        .wr_data(input_wr_data), .rd_en(input_rd_en), .rd_addr(input_rd_addr), .rd_data(input_rd_data)
    );
    nn_bram_sdp #(.ADDR_WIDTH(ACT_ADDR_WIDTH), .DATA_WIDTH(32)) u_act1_bram (
        .clk(clk), .rst_n(rst_n), .wr_en(act1_wr_en), .wr_addr(act1_wr_addr),
        .wr_data(act1_wr_data), .rd_en(act1_rd_en), .rd_addr(act1_rd_addr), .rd_data(act1_rd_data)
    );
    nn_bram_sdp #(.ADDR_WIDTH(ACT_ADDR_WIDTH), .DATA_WIDTH(32)) u_act2_bram (
        .clk(clk), .rst_n(rst_n), .wr_en(act2_wr_en), .wr_addr(act2_wr_addr),
        .wr_data(act2_wr_data), .rd_en(act2_rd_en), .rd_addr(act2_rd_addr), .rd_data(act2_rd_data)
    );

    // synthesis translate_off
    wire input_bram_same_addr_rw = input_wr_en && input_rd_en && (input_wr_addr == input_rd_addr);
    wire act1_bram_same_addr_rw  = act1_wr_en  && act1_rd_en  && (act1_wr_addr  == act1_rd_addr);
    wire act2_bram_same_addr_rw  = act2_wr_en  && act2_rd_en  && (act2_wr_addr  == act2_rd_addr);

    always @(posedge clk) begin
        if (rst_n) begin
            if (input_bram_same_addr_rw) begin
                $display("FAIL nn_compute_mlp16: input BSRAM same-address read/write at addr=%0d", input_wr_addr);
                $stop;
            end
            if (act1_bram_same_addr_rw) begin
                $display("FAIL nn_compute_mlp16: act1 BSRAM same-address read/write at addr=%0d", act1_wr_addr);
                $stop;
            end
            if (act2_bram_same_addr_rw) begin
                $display("FAIL nn_compute_mlp16: act2 BSRAM same-address read/write at addr=%0d", act2_wr_addr);
                $stop;
            end
        end
    end
    // synthesis translate_on

    // Helper submodules
    wire signed [15:0] current_weight;
    nn_weight16_unpack2 u_weight_unpack (.word_data(param_data), .lane_sel(weight_half_sel), .value(current_weight));

    wire signed [63:0] current_bias64 = {{32{param_data[31]}}, param_data};

    reg [31:0] selected_act_word;
    reg        act_half_sel;
    wire signed [15:0] current_act = act_half_sel ? selected_act_word[31:16] : selected_act_word[15:0];

    wire signed [63:0] mac_product;
    nn_mac_unit #(.ACT_WIDTH(16), .W_WIDTH(16), .PROD_WIDTH(64)) u_mac (
        .act_in(current_act), .weight_in(current_weight), .product_out(mac_product)
    );

    wire signed [63:0] acc_mac_next;
    leaf_adder #(.WIDTH(64)) u_acc_mac_adder (
        .a(acc),
        .b(mac_product),
        .y(acc_mac_next)
    );

    wire signed [63:0] score_with_bias_next;
    leaf_adder #(.WIDTH(64)) u_score_bias_adder (
        .a(acc),
        .b(current_bias64),
        .y(score_with_bias_next)
    );

    localparam [31:0] L1_POCKET_DIVISOR = 32'd256 * IN_SIZE;
    localparam [31:0] L2_POCKET_DIVISOR = 32'd256 * L1_OUT;
    localparam [31:0] L3_POCKET_DIVISOR = 32'd256 * L2_OUT;

    reg act_start;
    reg [31:0] act_divisor;
    wire act_busy;
    wire act_done;
    wire signed [15:0] act_out;
    wire signed [63:0] act_argmax_value = {{48{act_out[15]}}, act_out};

    nn_pocket_tanh_activation_seq_runtime #(.ACC_WIDTH(64), .OUT_WIDTH(16)) u_pocket_act (
        .clk(clk), .rst_n(rst_n), .start(act_start), .acc(score_with_bias_r),
        .divisor(act_divisor), .busy(act_busy), .done(act_done), .act(act_out)
    );

    reg argmax_clear, argmax_valid;
    wire signed [63:0] argmax_value;
    wire [3:0] argmax_index;
    nn_argmax_stream #(.DATA_WIDTH(64), .INDEX_WIDTH(4)) u_argmax (
        .clk(clk), .rst_n(rst_n), .clear(argmax_clear), .valid(argmax_valid),
        .data_in(act_argmax_value), .index_in(score_index_r), .max_value(argmax_value), .max_index(argmax_index)
    );

    function [31:0] weight_word_offset;
        input [15:0] in_index;
        input [15:0] out_index;
        input [15:0] out_size;
        input [15:0] in_size;
        reg [31:0] scalar_index;
        reg [31:0] node_words;
        begin
            if (PARAM_LAYOUT_NODE_CONTIGUOUS != 0) begin
                node_words = 32'd1 + (({16'd0, in_size} + 32'd1) >> 1);
                weight_word_offset = ({16'd0, out_index} * node_words) +
                                     32'd1 + ({16'd0, in_index} >> 1);
            end else begin
                scalar_index = in_index * out_size + out_index;
                weight_word_offset = scalar_index >> 1;
            end
        end
    endfunction

    function weight_half_index;
        input [15:0] in_index;
        input [15:0] out_index;
        input [15:0] out_size;
        reg [31:0] scalar_index;
        begin
            if (PARAM_LAYOUT_NODE_CONTIGUOUS != 0) begin
                weight_half_index = in_index[0];
            end else begin
                scalar_index = in_index * out_size + out_index;
                weight_half_index = scalar_index[0];
            end
        end
    endfunction

    function [31:0] bias_word_offset;
        input [15:0] out_index;
        input [15:0] in_size;
        reg [31:0] node_words;
        begin
            if (PARAM_LAYOUT_NODE_CONTIGUOUS != 0) begin
                node_words = 32'd1 + (({16'd0, in_size} + 32'd1) >> 1);
                bias_word_offset = {16'd0, out_index} * node_words;
            end else begin
                bias_word_offset = {16'd0, out_index};
            end
        end
    endfunction

    always @(*) begin
        selected_act_word = 32'd0;
        if (state == S_L1_WAIT_W) selected_act_word = input_rd_data;
        else if (state == S_L2_WAIT_W) selected_act_word = act1_rd_data;
        else if (state == S_L3_WAIT_W) selected_act_word = act2_rd_data;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; start_d <= 1'b0;
            busy <= 1'b0; done <= 1'b0; error <= 1'b0; predict_class <= 4'd0; predict_valid <= 1'b0;
            param_req <= 1'b0; param_layer <= 3'd0; param_is_bias <= 1'b0; param_word_offset <= 32'd0;
            input_rd_en <= 1'b0; act1_rd_en <= 1'b0; act2_rd_en <= 1'b0;
            input_rd_addr <= 0; act1_rd_addr <= 0; act2_rd_addr <= 0;
            act1_wr_en <= 1'b0; act2_wr_en <= 1'b0; act1_wr_addr <= 0; act2_wr_addr <= 0;
            act1_wr_data <= 32'd0; act2_wr_data <= 32'd0; act_pack_temp <= 32'd0;
            i_idx <= 16'd0; o_idx <= 16'd0; acc <= 64'sd0; score_with_bias_r <= 64'sd0;
            score_index_r <= 4'd0;
            weight_half_sel <= 1'b0; act_half_sel <= 1'b0; argmax_clear <= 1'b0; argmax_valid <= 1'b0;
            act_start <= 1'b0; act_divisor <= L1_POCKET_DIVISOR;
        end else begin
            start_d <= start;
            param_req <= 1'b0; done <= 1'b0;
            input_rd_en <= 1'b0; act1_rd_en <= 1'b0; act2_rd_en <= 1'b0;
            act1_wr_en <= 1'b0; act2_wr_en <= 1'b0;
            argmax_clear <= 1'b0; argmax_valid <= 1'b0;
            act_start <= 1'b0;

            if (param_error) begin
                state <= S_ERROR; error <= 1'b1; busy <= 1'b0;
            end else begin
                case (state)
                    S_IDLE: begin
                        busy <= 1'b0; predict_valid <= 1'b0; error <= 1'b0;
                        if (start_rise && loader_done) begin
                            busy <= 1'b1; state <= S_L1_INIT;
                        end
                    end

                    S_L1_INIT: begin i_idx <= 0; o_idx <= 0; acc <= 0; state <= S_L1_PREP; end
                    S_L1_PREP: begin
                        if (param_ready && !param_busy) begin
                            input_rd_en <= 1'b1; input_rd_addr <= i_idx[ACT_ADDR_WIDTH:1]; act_half_sel <= i_idx[0];
                            param_req <= 1'b1; param_layer <= 3'd0; param_is_bias <= 1'b0;
                            param_word_offset <= weight_word_offset(i_idx, o_idx, L1_OUT_16, IN_SIZE_16);
                            weight_half_sel <= weight_half_index(i_idx, o_idx, L1_OUT_16);
                            state <= S_L1_WAIT_W;
                        end
                    end
                    S_L1_WAIT_W: begin
                        if (param_data_valid) begin
                            acc <= acc_mac_next;
                            if (i_idx == IN_SIZE_LAST) begin i_idx <= 0; state <= S_L1_B_REQ; end
                            else begin i_idx <= i_idx + 1'b1; state <= S_L1_PREP; end
                        end
                    end
                    S_L1_B_REQ: begin
                        if (param_ready && !param_busy) begin
                            param_req <= 1'b1; param_layer <= 3'd0; param_is_bias <= 1'b1; param_word_offset <= bias_word_offset(o_idx, IN_SIZE_16); state <= S_L1_B_WAIT;
                        end
                    end
                    S_L1_B_WAIT: begin
                        if (param_data_valid) begin score_with_bias_r <= score_with_bias_next; act_divisor <= L1_POCKET_DIVISOR; state <= S_L1_ACT_START; end
                    end
                    S_L1_ACT_START: begin
                        act_start <= 1'b1;
                        state <= S_L1_ACT_WAIT;
                    end
                    S_L1_ACT_WAIT: begin
                        if (act_done) state <= S_L1_WRITE;
                    end
                    S_L1_WRITE: begin
                        if (o_idx[0] == 1'b0) begin
                            act_pack_temp <= {16'd0, act_out};
                        end else begin
                            act1_wr_en <= 1'b1; act1_wr_addr <= o_idx[ACT_ADDR_WIDTH:1]; act1_wr_data <= {act_out, act_pack_temp[15:0]};
                        end
                        acc <= 0;
                        if (o_idx == L1_OUT_LAST) begin
                            if (o_idx[0] == 1'b0) begin act1_wr_en <= 1'b1; act1_wr_addr <= o_idx[ACT_ADDR_WIDTH:1]; act1_wr_data <= {16'd0, act_out}; end
                            o_idx <= 0; i_idx <= 0; state <= S_L2_INIT;
                        end else begin o_idx <= o_idx + 1'b1; i_idx <= 0; state <= S_L1_PREP; end
                    end

                    S_L2_INIT: begin i_idx <= 0; o_idx <= 0; acc <= 0; state <= S_L2_PREP; end
                    S_L2_PREP: begin
                        if (param_ready && !param_busy) begin
                            act1_rd_en <= 1'b1; act1_rd_addr <= i_idx[ACT_ADDR_WIDTH:1]; act_half_sel <= i_idx[0];
                            param_req <= 1'b1; param_layer <= 3'd1; param_is_bias <= 1'b0;
                            param_word_offset <= weight_word_offset(i_idx, o_idx, L2_OUT_16, L1_OUT_16);
                            weight_half_sel <= weight_half_index(i_idx, o_idx, L2_OUT_16);
                            state <= S_L2_WAIT_W;
                        end
                    end
                    S_L2_WAIT_W: begin
                        if (param_data_valid) begin
                            acc <= acc_mac_next;
                            if (i_idx == L1_OUT_LAST) begin i_idx <= 0; state <= S_L2_B_REQ; end
                            else begin i_idx <= i_idx + 1'b1; state <= S_L2_PREP; end
                        end
                    end
                    S_L2_B_REQ: begin
                        if (param_ready && !param_busy) begin
                            param_req <= 1'b1; param_layer <= 3'd1; param_is_bias <= 1'b1; param_word_offset <= bias_word_offset(o_idx, L1_OUT_16); state <= S_L2_B_WAIT;
                        end
                    end
                    S_L2_B_WAIT: begin
                        if (param_data_valid) begin score_with_bias_r <= score_with_bias_next; act_divisor <= L2_POCKET_DIVISOR; state <= S_L2_ACT_START; end
                    end
                    S_L2_ACT_START: begin
                        act_start <= 1'b1;
                        state <= S_L2_ACT_WAIT;
                    end
                    S_L2_ACT_WAIT: begin
                        if (act_done) state <= S_L2_WRITE;
                    end
                    S_L2_WRITE: begin
                        if (o_idx[0] == 1'b0) begin
                            act_pack_temp <= {16'd0, act_out};
                        end else begin
                            act2_wr_en <= 1'b1; act2_wr_addr <= o_idx[ACT_ADDR_WIDTH:1]; act2_wr_data <= {act_out, act_pack_temp[15:0]};
                        end
                        acc <= 0;
                        if (o_idx == L2_OUT_LAST) begin
                            if (o_idx[0] == 1'b0) begin act2_wr_en <= 1'b1; act2_wr_addr <= o_idx[ACT_ADDR_WIDTH:1]; act2_wr_data <= {16'd0, act_out}; end
                            o_idx <= 0; i_idx <= 0; state <= S_L3_INIT;
                        end else begin o_idx <= o_idx + 1'b1; i_idx <= 0; state <= S_L2_PREP; end
                    end

                    S_L3_INIT: begin i_idx <= 0; o_idx <= 0; acc <= 0; argmax_clear <= 1'b1; predict_class <= 0; state <= S_L3_PREP; end
                    S_L3_PREP: begin
                        if (param_ready && !param_busy) begin
                            act2_rd_en <= 1'b1; act2_rd_addr <= i_idx[ACT_ADDR_WIDTH:1]; act_half_sel <= i_idx[0];
                            param_req <= 1'b1; param_layer <= 3'd2; param_is_bias <= 1'b0;
                            param_word_offset <= weight_word_offset(i_idx, o_idx, L3_OUT_16, L2_OUT_16);
                            weight_half_sel <= weight_half_index(i_idx, o_idx, L3_OUT_16);
                            state <= S_L3_WAIT_W;
                        end
                    end
                    S_L3_WAIT_W: begin
                        if (param_data_valid) begin
                            acc <= acc_mac_next;
                            if (i_idx == L2_OUT_LAST) begin i_idx <= 0; state <= S_L3_B_REQ; end
                            else begin i_idx <= i_idx + 1'b1; state <= S_L3_PREP; end
                        end
                    end
                    S_L3_B_REQ: begin
                        if (param_ready && !param_busy) begin
                            param_req <= 1'b1; param_layer <= 3'd2; param_is_bias <= 1'b1; param_word_offset <= bias_word_offset(o_idx, L2_OUT_16); state <= S_L3_B_WAIT;
                        end
                    end
                    S_L3_B_WAIT: begin
                        if (param_data_valid) begin
                            score_with_bias_r <= score_with_bias_next;
                            score_index_r <= o_idx[3:0];
                            act_divisor <= L3_POCKET_DIVISOR;
                            state <= S_L3_ACT_START;
                        end
                    end
                    S_L3_ACT_START: begin
                        act_start <= 1'b1;
                        state <= S_L3_ACT_WAIT;
                    end
                    S_L3_ACT_WAIT: begin
                        if (act_done) state <= S_L3_SCORE;
                    end
                    S_L3_SCORE: begin
                        argmax_valid <= 1'b1;
                        acc <= 0;
                        if (o_idx == L3_OUT_LAST) begin
                            state <= S_L3_ARGMAX_WAIT;
                        end else begin o_idx <= o_idx + 1'b1; i_idx <= 0; state <= S_L3_PREP; end
                    end
                    S_L3_ARGMAX_WAIT: begin
                        state <= S_L3_FINAL;
                    end
                    S_L3_FINAL: begin
                        predict_class <= argmax_index;
                        predict_valid <= 1'b1;
                        busy <= 1'b0;
                        done <= 1'b1;
                        state <= S_DONE;
                    end
                    S_DONE: begin busy <= 1'b0; if (!start) state <= S_IDLE; end
                    S_ERROR: begin busy <= 1'b0; error <= 1'b1; if (!start) state <= S_IDLE; end
                    default: begin state <= S_ERROR; error <= 1'b1; busy <= 1'b0; end
                endcase
            end
        end
    end
endmodule
