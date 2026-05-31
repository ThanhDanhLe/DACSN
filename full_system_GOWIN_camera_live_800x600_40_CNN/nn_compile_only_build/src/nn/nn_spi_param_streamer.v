`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// nn_spi_param_streamer.v
//
// Minimal read-only SPI Flash parameter service for DIRECT_SPI_PARAM_STREAM.
// It implements the same one-word parameter-service contract used by
// nn_compute_mlp16_pocket, but fetches directly from SPI Flash instead of
// HyperRAM. The expected flash layout is node-contiguous:
//
//   FC layer:
//     for each output node:
//       int32 bias
//       packed int16 weights by input index, two weights per 32-bit word
//
// Flash bytes are little-endian inside each returned 32-bit parameter word.
// -----------------------------------------------------------------------------
module nn_spi_param_streamer #(
    parameter integer SPI_DIV = 1,
    parameter [23:0]  FLASH_PARAM_BASE = 24'h200000,
    parameter integer IN_SIZE = 784,
    parameter integer L1_OUT = 100,
    parameter integer L2_OUT = 50,
    parameter integer L3_OUT = 10
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        param_req,
    input  wire [2:0]  param_layer,
    input  wire        param_is_bias,
    input  wire [31:0] param_word_offset,
    input  wire [15:0] param_len_words,
    input  wire        param_data_ready,
    output wire        param_ready,
    output wire        param_busy,
    output reg         param_done,
    output reg         param_error,
    output reg  [31:0] param_data,
    output reg         param_data_valid,

    output reg         flash_cs_n,
    output reg         flash_sclk,
    output reg         flash_mosi,
    input  wire        flash_miso
);

localparam integer L1_NODE_WORDS = 1 + ((IN_SIZE + 1) / 2);
localparam integer L2_NODE_WORDS = 1 + ((L1_OUT + 1) / 2);
localparam integer L3_NODE_WORDS = 1 + ((L2_OUT + 1) / 2);
localparam integer FC1_WORDS = L1_OUT * L1_NODE_WORDS;
localparam integer FC2_WORDS = L2_OUT * L2_NODE_WORDS;
localparam integer FC3_WORDS = L3_OUT * L3_NODE_WORDS;
localparam integer FC1_BYTES = FC1_WORDS * 4;
localparam integer FC2_BYTES = FC2_WORDS * 4;
localparam integer FC3_BYTES = FC3_WORDS * 4;
localparam integer FC1_BASE_BYTES = 0;
localparam integer FC2_BASE_BYTES = FC1_BYTES;
localparam integer FC3_BASE_BYTES = FC1_BYTES + FC2_BYTES;

localparam [3:0]
    S_IDLE  = 4'd0,
    S_CACHE = 4'd1,
    S_START = 4'd2,
    S_LOW   = 4'd3,
    S_HIGH  = 4'd4,
    S_DONE  = 4'd5,
    S_ERROR = 4'd6;

localparam [7:0] CMD_FAST_READ = 8'h0B;
localparam integer TOTAL_BITS = 72;
localparam integer DATA_START_BIT = 40;
localparam [6:0] DATA_START_BIT_7 = DATA_START_BIT;
localparam [15:0] SPI_DIV_16 = SPI_DIV;

reg [3:0] state;
reg [23:0] req_addr;
reg [23:0] cache_addr;
reg [31:0] cache_word;
reg        cache_valid;
reg [6:0]  bit_index;
reg [15:0] div_count;
reg [39:0] tx_shift;
reg [31:0] rx_shift;
reg        current_miso;

assign param_ready = (state == S_IDLE);
assign param_busy = (state != S_IDLE);

function [23:0] layer_base;
    input [2:0] layer;
    begin
        case (layer)
            3'd0: layer_base = FLASH_PARAM_BASE + FC1_BASE_BYTES;
            3'd1: layer_base = FLASH_PARAM_BASE + FC2_BASE_BYTES;
            3'd2: layer_base = FLASH_PARAM_BASE + FC3_BASE_BYTES;
            default: layer_base = FLASH_PARAM_BASE;
        endcase
    end
endfunction

function layer_offset_valid;
    input [2:0] layer;
    input [31:0] word_offset;
    begin
        case (layer)
            3'd0: layer_offset_valid = (word_offset < FC1_WORDS);
            3'd1: layer_offset_valid = (word_offset < FC2_WORDS);
            3'd2: layer_offset_valid = (word_offset < FC3_WORDS);
            default: layer_offset_valid = 1'b0;
        endcase
    end
endfunction

function tx_bit_at;
    input [6:0] idx;
    begin
        if (idx < 7'd40)
            tx_bit_at = tx_shift[7'd39 - idx];
        else
            tx_bit_at = 1'b0;
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;
        req_addr <= 24'd0;
        cache_addr <= 24'd0;
        cache_word <= 32'd0;
        cache_valid <= 1'b0;
        bit_index <= 7'd0;
        div_count <= 16'd0;
        tx_shift <= 40'd0;
        rx_shift <= 32'd0;
        current_miso <= 1'b0;
        param_done <= 1'b0;
        param_error <= 1'b0;
        param_data <= 32'd0;
        param_data_valid <= 1'b0;
        flash_cs_n <= 1'b1;
        flash_sclk <= 1'b0;
        flash_mosi <= 1'b0;
    end else begin
        param_done <= 1'b0;
        param_data_valid <= 1'b0;

        case (state)
            S_IDLE: begin
                flash_cs_n <= 1'b1;
                flash_sclk <= 1'b0;
                flash_mosi <= 1'b0;
                div_count <= 16'd0;
                if (param_req) begin
                    if ((param_len_words != 16'd1) || !layer_offset_valid(param_layer, param_word_offset)) begin
                        param_error <= 1'b1;
                        state <= S_ERROR;
                    end else begin
                        req_addr <= layer_base(param_layer) + {param_word_offset[21:0], 2'b00};
                        state <= S_CACHE;
                    end
                end
            end

            S_CACHE: begin
                if (cache_valid && (cache_addr == req_addr)) begin
                    param_data <= cache_word;
                    param_data_valid <= 1'b1;
                    param_done <= 1'b1;
                    state <= S_IDLE;
                end else begin
                    tx_shift <= {CMD_FAST_READ, req_addr, 8'h00};
                    rx_shift <= 32'd0;
                    bit_index <= 7'd0;
                    flash_cs_n <= 1'b0;
                    flash_sclk <= 1'b0;
                    flash_mosi <= CMD_FAST_READ[7];
                    state <= S_START;
                end
            end

            S_START: begin
                state <= S_LOW;
            end

            S_LOW: begin
                if (div_count >= (SPI_DIV_16 - 16'd1)) begin
                    div_count <= 16'd0;
                    flash_sclk <= 1'b1;
                    current_miso <= flash_miso;
                    if (bit_index >= DATA_START_BIT_7)
                        rx_shift <= {rx_shift[30:0], flash_miso};
                    state <= S_HIGH;
                end else begin
                    div_count <= div_count + 16'd1;
                end
            end

            S_HIGH: begin
                if (div_count >= (SPI_DIV_16 - 16'd1)) begin
                    div_count <= 16'd0;
                    flash_sclk <= 1'b0;
                    if (bit_index == (TOTAL_BITS - 1)) begin
                        flash_cs_n <= 1'b1;
                        state <= S_DONE;
                    end else begin
                        bit_index <= bit_index + 7'd1;
                        flash_mosi <= tx_bit_at(bit_index + 7'd1);
                        state <= S_LOW;
                    end
                end else begin
                    div_count <= div_count + 16'd1;
                end
            end

            S_DONE: begin
                cache_addr <= req_addr;
                cache_word <= {rx_shift[7:0], rx_shift[15:8], rx_shift[23:16], rx_shift[31:24]};
                cache_valid <= 1'b1;
                param_data <= {rx_shift[7:0], rx_shift[15:8], rx_shift[23:16], rx_shift[31:24]};
                param_data_valid <= 1'b1;
                param_done <= 1'b1;
                state <= S_IDLE;
            end

            S_ERROR: begin
                flash_cs_n <= 1'b1;
                flash_sclk <= 1'b0;
                flash_mosi <= 1'b0;
                param_done <= 1'b1;
                state <= S_IDLE;
            end

            default: begin
                param_error <= 1'b1;
                state <= S_ERROR;
            end
        endcase
    end
end

wire param_is_bias_unused = param_is_bias;
wire current_miso_unused = current_miso;

endmodule
