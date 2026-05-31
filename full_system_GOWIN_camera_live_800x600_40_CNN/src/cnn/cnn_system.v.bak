`timescale 1ns/1ps

module cnn_system #(
    parameter ACT_ADDR_WIDTH = 9,
    parameter integer SPI_DIV = 1,
    parameter [23:0] FLASH_PARAM_BASE = 24'h200000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        memory_ready,

    output wire        image_rd_en,
    output wire [9:0]  image_rd_addr,
    input  wire [15:0] image_rd_data,

    input  wire                      image_preload_valid,
    input  wire                      image_preload_wr_en,
    input  wire [ACT_ADDR_WIDTH-1:0] image_preload_wr_addr,
    input  wire [31:0]               image_preload_wr_data,

    output wire        flash_cs_n,
    output wire        flash_sclk,
    output wire        flash_mosi,
    input  wire        flash_miso,

    output wire        busy,
    output wire        done,
    output wire        output_valid,
    output wire [3:0]  output_class,
    output wire        error
);

localparam integer TOTAL_PARAM_WORDS = 2340;
localparam [2:0]
    S_IDLE          = 3'd0,
    S_COMPUTE_START = 3'd1,
    S_COMPUTE       = 3'd2,
    S_DONE          = 3'd3,
    S_ERROR         = 3'd4;

reg [2:0] state;
reg start_d;
wire start_rise = start & ~start_d;

reg compute_start;
wire compute_busy;
wire compute_done;
wire compute_error;
wire compute_output_valid;
wire [3:0] compute_output_class;
wire [639:0] compute_debug_logits_flat;
wire [5:0] compute_debug_state;
wire [3:0] compute_debug_op;
wire [4:0] compute_debug_x;
wire [4:0] compute_debug_y;
wire [4:0] compute_debug_channel;
wire signed [63:0] compute_debug_accumulator;

wire compute_param_req;
wire [31:0] compute_param_word_offset;
wire [15:0] compute_param_len_words;
wire param_ready;
wire param_busy;
wire param_done;
wire param_error;
wire [31:0] param_data;
wire param_data_valid;

reg busy_r;
reg done_r;
reg valid_r;
reg [3:0] class_r;
reg error_r;

assign busy = busy_r;
assign done = done_r;
assign output_valid = valid_r;
assign output_class = class_r;
assign error = error_r | param_error | compute_error;

cnn_param_streamer #(
    .SPI_DIV(SPI_DIV),
    .FLASH_PARAM_BASE(FLASH_PARAM_BASE),
    .TOTAL_WORDS(TOTAL_PARAM_WORDS)
) u_param_streamer (
    .clk(clk),
    .rst_n(rst_n),
    .param_req(compute_param_req),
    .param_word_offset(compute_param_word_offset),
    .param_len_words(compute_param_len_words),
    .param_data_ready(1'b1),
    .param_ready(param_ready),
    .param_busy(param_busy),
    .param_done(param_done),
    .param_error(param_error),
    .param_data(param_data),
    .param_data_valid(param_data_valid),
    .flash_cs_n(flash_cs_n),
    .flash_sclk(flash_sclk),
    .flash_mosi(flash_mosi),
    .flash_miso(flash_miso)
);

cnn_compute_lwdd #(
    .ACT_ADDR_WIDTH(ACT_ADDR_WIDTH),
    .PARAM_ADDR_WIDTH(12),
    .DEBUG_LOGITS(0)
) u_compute (
    .clk(clk),
    .rst_n(rst_n),
    .start(compute_start),
    .busy(compute_busy),
    .done(compute_done),
    .error(compute_error),
    .output_valid(compute_output_valid),
    .output_class(compute_output_class),
    .input_wr_en(image_preload_wr_en),
    .input_wr_addr(image_preload_wr_addr),
    .input_wr_data(image_preload_wr_data),
    .image_rd_en(image_rd_en),
    .image_rd_addr(image_rd_addr),
    .image_rd_data(image_rd_data),
    .param_req(compute_param_req),
    .param_word_offset(compute_param_word_offset),
    .param_len_words(compute_param_len_words),
    .param_ready(param_ready),
    .param_done(param_done),
    .param_error(param_error),
    .param_data(param_data),
    .param_data_valid(param_data_valid),
    .debug_logits_flat(compute_debug_logits_flat),
    .debug_state(compute_debug_state),
    .debug_op(compute_debug_op),
    .debug_x(compute_debug_x),
    .debug_y(compute_debug_y),
    .debug_channel(compute_debug_channel),
    .debug_accumulator(compute_debug_accumulator)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;
        start_d <= 1'b0;
        compute_start <= 1'b0;
        busy_r <= 1'b0;
        done_r <= 1'b0;
        valid_r <= 1'b0;
        class_r <= 4'd0;
        error_r <= 1'b0;
    end else begin
        start_d <= start;
        compute_start <= 1'b0;
        done_r <= 1'b0;
        valid_r <= 1'b0;

        case (state)
            S_IDLE: begin
                busy_r <= 1'b0;
                error_r <= 1'b0;
                if (start_rise) begin
                    if (memory_ready && image_preload_valid) begin
                        busy_r <= 1'b1;
                        state <= S_COMPUTE_START;
                    end else if (memory_ready) begin
                        error_r <= 1'b1;
                        state <= S_ERROR;
                    end
                end
            end

            S_COMPUTE_START: begin
                compute_start <= 1'b1;
                state <= S_COMPUTE;
            end

            S_COMPUTE: begin
                if (compute_error || param_error) begin
                    error_r <= 1'b1;
                    busy_r <= 1'b0;
                    state <= S_ERROR;
                end else if (compute_output_valid) begin
                    class_r <= compute_output_class;
                    valid_r <= 1'b1;
                    done_r <= 1'b1;
                    busy_r <= 1'b0;
                    state <= S_DONE;
                end
            end

            S_DONE: begin
                if (!start)
                    state <= S_IDLE;
            end

            S_ERROR: begin
                busy_r <= 1'b0;
                if (!start)
                    state <= S_IDLE;
            end

            default: begin
                error_r <= 1'b1;
                busy_r <= 1'b0;
                state <= S_ERROR;
            end
        endcase
    end
end

wire param_busy_unused = param_busy;
wire compute_done_unused = compute_done;
wire compute_busy_unused = compute_busy;
wire compute_debug_unused = ^compute_debug_logits_flat ^ ^compute_debug_state ^
                            ^compute_debug_op ^ ^compute_debug_x ^
                            ^compute_debug_y ^ ^compute_debug_channel ^
                            ^compute_debug_accumulator;

endmodule
