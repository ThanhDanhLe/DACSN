`timescale 1ns/1ps

module cnn_spi_flash_reader #(
    parameter integer SPI_DIV = 1,
    parameter integer LEN_WIDTH = 13
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [23:0] flash_addr,
    input  wire [LEN_WIDTH-1:0] length_bytes,
    output reg  [7:0]  data_out,
    output reg         data_valid,
    output reg         busy,
    output reg         done,
    output reg         spi_cs_n,
    output reg         spi_sclk,
    output reg         spi_mosi,
    input  wire        spi_miso
);

localparam [7:0] CMD_FAST_READ = 8'h0B;

localparam [1:0]
    S_IDLE   = 2'd0,
    S_TX_HDR = 2'd1,
    S_READ   = 2'd2;

reg [1:0] state;
reg [15:0] div_cnt;
reg half_phase;
reg [39:0] tx_shift;
reg [5:0] tx_bits_left;
reg [LEN_WIDTH-1:0] bytes_remaining;
reg [7:0] rx_shift;
reg [2:0] rx_bit_idx;
reg read_done_pending;

wire div_tick = (div_cnt == (SPI_DIV - 1));

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;
        div_cnt <= 16'd0;
        half_phase <= 1'b0;
        tx_shift <= 40'd0;
        tx_bits_left <= 6'd0;
        bytes_remaining <= {LEN_WIDTH{1'b0}};
        rx_shift <= 8'd0;
        rx_bit_idx <= 3'd7;
        read_done_pending <= 1'b0;
        data_out <= 8'd0;
        data_valid <= 1'b0;
        busy <= 1'b0;
        done <= 1'b0;
        spi_cs_n <= 1'b1;
        spi_sclk <= 1'b0;
        spi_mosi <= 1'b0;
    end else begin
        data_valid <= 1'b0;
        done <= 1'b0;

        case (state)
            S_IDLE: begin
                spi_cs_n <= 1'b1;
                spi_sclk <= 1'b0;
                spi_mosi <= 1'b0;
                div_cnt <= 16'd0;
                half_phase <= 1'b0;
                read_done_pending <= 1'b0;

                if (start && (length_bytes != {LEN_WIDTH{1'b0}})) begin
                    busy <= 1'b1;
                    bytes_remaining <= length_bytes;
                    tx_shift <= {CMD_FAST_READ, flash_addr, 8'h00};
                    tx_bits_left <= 6'd40;
                    spi_cs_n <= 1'b0;
                    spi_sclk <= 1'b0;
                    spi_mosi <= CMD_FAST_READ[7];
                    state <= S_TX_HDR;
                end else begin
                    busy <= 1'b0;
                end
            end

            S_TX_HDR: begin
                if (div_tick) begin
                    div_cnt <= 16'd0;
                    if (!half_phase) begin
                        spi_sclk <= 1'b1;
                        half_phase <= 1'b1;
                    end else begin
                        spi_sclk <= 1'b0;
                        half_phase <= 1'b0;
                        if (tx_bits_left == 6'd1) begin
                            state <= S_READ;
                            spi_mosi <= 1'b0;
                            rx_shift <= 8'd0;
                            rx_bit_idx <= 3'd7;
                            read_done_pending <= 1'b0;
                        end else begin
                            tx_bits_left <= tx_bits_left - 6'd1;
                            spi_mosi <= tx_shift[38];
                            tx_shift <= {tx_shift[38:0], 1'b0};
                        end
                    end
                end else begin
                    div_cnt <= div_cnt + 16'd1;
                end
            end

            S_READ: begin
                if (div_tick) begin
                    div_cnt <= 16'd0;
                    if (!half_phase) begin
                        spi_sclk <= 1'b1;
                        half_phase <= 1'b1;
                        if (rx_bit_idx == 3'd0) begin
                            data_out <= {rx_shift[6:0], spi_miso};
                            data_valid <= 1'b1;
                            rx_shift <= 8'd0;
                            rx_bit_idx <= 3'd7;
                            if (bytes_remaining == {{(LEN_WIDTH-1){1'b0}}, 1'b1}) begin
                                bytes_remaining <= {LEN_WIDTH{1'b0}};
                                read_done_pending <= 1'b1;
                            end else begin
                                bytes_remaining <= bytes_remaining - {{(LEN_WIDTH-1){1'b0}}, 1'b1};
                            end
                        end else begin
                            rx_shift <= {rx_shift[6:0], spi_miso};
                            rx_bit_idx <= rx_bit_idx - 3'd1;
                        end
                    end else begin
                        spi_sclk <= 1'b0;
                        half_phase <= 1'b0;
                        if (read_done_pending) begin
                            spi_cs_n <= 1'b1;
                            spi_mosi <= 1'b0;
                            busy <= 1'b0;
                            done <= 1'b1;
                            read_done_pending <= 1'b0;
                            state <= S_IDLE;
                        end
                    end
                end else begin
                    div_cnt <= div_cnt + 16'd1;
                end
            end

            default: begin
                state <= S_IDLE;
                busy <= 1'b0;
                spi_cs_n <= 1'b1;
                spi_sclk <= 1'b0;
                spi_mosi <= 1'b0;
            end
        endcase
    end
end

endmodule
