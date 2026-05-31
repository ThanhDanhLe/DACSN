`timescale 1ns/1ps

// Direct-SPI/image-preload NN wrapper for the final Gowin build.
// Parameters are streamed only from SPI Flash; HyperRAM is not an NN owner.
module nn_system #(
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

assign image_rd_en = 1'b0;
assign image_rd_addr = 10'd0;

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
    wire [3:0] predict_class;
    wire predict_valid;

    wire cmp_param_req;
    wire [2:0] cmp_param_layer;
    wire cmp_param_is_bias;
    wire [31:0] cmp_param_word_offset;
    wire [15:0] cmp_param_len_words;
    wire cmp_param_data_ready;
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
    assign error = error_r | compute_error | param_error;

    nn_spi_param_streamer #(
        .SPI_DIV(SPI_DIV),
        .FLASH_PARAM_BASE(FLASH_PARAM_BASE)
    ) u_param_service (
        .clk(clk),
        .rst_n(rst_n),
        .param_req(cmp_param_req),
        .param_layer(cmp_param_layer),
        .param_is_bias(cmp_param_is_bias),
        .param_word_offset(cmp_param_word_offset),
        .param_len_words(cmp_param_len_words),
        .param_data_ready(cmp_param_data_ready),
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

    nn_compute_mlp16_pocket #(
        .ACT_ADDR_WIDTH(ACT_ADDR_WIDTH),
        .PARAM_LAYOUT_NODE_CONTIGUOUS(1)
    ) u_compute (
        .clk(clk),
        .rst_n(rst_n),
        .start(compute_start),
        .loader_done(1'b1),
        .busy(compute_busy),
        .done(compute_done),
        .error(compute_error),
        .predict_class(predict_class),
        .predict_valid(predict_valid),
        .input_wr_en(image_preload_wr_en),
        .input_wr_addr(image_preload_wr_addr),
        .input_wr_data(image_preload_wr_data),
        .param_req(cmp_param_req),
        .param_layer(cmp_param_layer),
        .param_is_bias(cmp_param_is_bias),
        .param_word_offset(cmp_param_word_offset),
        .param_len_words(cmp_param_len_words),
        .param_data_ready(cmp_param_data_ready),
        .param_ready(param_ready),
        .param_busy(param_busy),
        .param_done(param_done),
        .param_error(param_error),
        .param_data(param_data),
        .param_data_valid(param_data_valid)
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
                        busy_r <= 1'b1;
                        if (memory_ready && image_preload_valid) begin
                            state <= S_COMPUTE_START;
                        end else if (memory_ready) begin
                            error_r <= 1'b1;
                            busy_r <= 1'b0;
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
                    end else if (predict_valid) begin
                        class_r <= predict_class;
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

    wire compute_done_unused = compute_done;

wire image_rd_data_unused = |image_rd_data;

endmodule
