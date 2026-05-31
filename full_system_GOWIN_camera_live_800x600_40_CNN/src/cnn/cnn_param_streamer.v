`timescale 1ns/1ps

module cnn_param_streamer #(
    parameter integer SPI_DIV = 1,
    parameter [23:0]  FLASH_PARAM_BASE = 24'h200000,
    parameter integer TOTAL_WORDS = 2340
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        param_req,
    input  wire [31:0] param_word_offset,
    input  wire [15:0] param_len_words,
    input  wire        param_data_ready,
    output wire        param_ready,
    output wire        param_busy,
    output reg         param_done,
    output reg         param_error,
    output reg  [31:0] param_data,
    output reg         param_data_valid,
    output wire        flash_cs_n,
    output wire        flash_sclk,
    output wire        flash_mosi,
    input  wire        flash_miso
);

localparam [1:0]
    S_IDLE = 2'd0,
    S_READ = 2'd1,
    S_ERR  = 2'd2;
localparam [12:0] TOTAL_WORDS_13 = TOTAL_WORDS;

reg [1:0] state;
reg reader_start;
wire [7:0] reader_data;
wire reader_data_valid;
wire reader_busy;
wire reader_done;
reg [31:0] word_acc;
reg [1:0] byte_pos;
reg [9:0] words_seen;

assign param_ready = (state == S_IDLE);
assign param_busy = (state != S_IDLE);

wire [9:0] req_len = param_len_words[9:0];
wire [12:0] request_end_word = {1'b0, param_word_offset[11:0]} + {3'd0, req_len};
wire request_valid = (param_len_words[15:10] == 6'd0) &&
                     (param_word_offset[31:12] == 20'd0) &&
                     (req_len != 10'd0) &&
                     ({1'b0, param_word_offset[11:0]} < TOTAL_WORDS_13) &&
                     (request_end_word <= TOTAL_WORDS_13);

cnn_spi_flash_reader #(
    .SPI_DIV(SPI_DIV),
    .LEN_WIDTH(13)
) u_reader (
    .clk(clk),
    .rst_n(rst_n),
    .start(reader_start),
    .flash_addr(FLASH_PARAM_BASE + {param_word_offset[11:0], 2'b00}),
    .length_bytes({1'b0, req_len, 2'b00}),
    .data_out(reader_data),
    .data_valid(reader_data_valid),
    .busy(reader_busy),
    .done(reader_done),
    .spi_cs_n(flash_cs_n),
    .spi_sclk(flash_sclk),
    .spi_mosi(flash_mosi),
    .spi_miso(flash_miso)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;
        reader_start <= 1'b0;
        word_acc <= 32'd0;
        byte_pos <= 2'd0;
        words_seen <= 10'd0;
        param_done <= 1'b0;
        param_error <= 1'b0;
        param_data <= 32'd0;
        param_data_valid <= 1'b0;
    end else begin
        reader_start <= 1'b0;
        param_done <= 1'b0;
        param_data_valid <= 1'b0;

        case (state)
            S_IDLE: begin
                word_acc <= 32'd0;
                byte_pos <= 2'd0;
                words_seen <= 10'd0;
                if (param_req) begin
                    if (!request_valid) begin
                        param_error <= 1'b1;
                        state <= S_ERR;
                    end else begin
                        reader_start <= 1'b1;
                        state <= S_READ;
                    end
                end
            end

            S_READ: begin
                if (reader_data_valid) begin
                    case (byte_pos)
                        2'd0: word_acc[7:0] <= reader_data;
                        2'd1: word_acc[15:8] <= reader_data;
                        2'd2: word_acc[23:16] <= reader_data;
                        default: begin
                            word_acc[31:24] <= reader_data;
                            if (param_data_ready) begin
                                param_data <= {reader_data, word_acc[23:0]};
                                param_data_valid <= 1'b1;
                            end else begin
                                param_error <= 1'b1;
                                state <= S_ERR;
                            end
                            words_seen <= words_seen + 10'd1;
                        end
                    endcase
                    byte_pos <= byte_pos + 2'd1;
                end

                if (reader_done) begin
                    if ((words_seen == req_len) || ((words_seen + 10'd1) == req_len)) begin
                        param_done <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        param_error <= 1'b1;
                        state <= S_ERR;
                    end
                end
            end

            S_ERR: begin
                param_done <= 1'b1;
                if (!param_req && !reader_busy)
                    state <= S_IDLE;
            end

            default: begin
                param_error <= 1'b1;
                state <= S_ERR;
            end
        endcase
    end
end

endmodule
