`timescale 1ns/1ps

module uart_tx #(
    parameter integer CLK_HZ = 27000000,
    parameter integer BAUD = 115200
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx,
    output reg        tx_busy,
    output wire       tx_ready
);

localparam integer CLKS_PER_BIT = (CLK_HZ + (BAUD / 2)) / BAUD;
localparam integer DIV_WIDTH = 16;

localparam [1:0]
    S_IDLE  = 2'd0,
    S_START = 2'd1,
    S_DATA  = 2'd2,
    S_STOP  = 2'd3;

reg [1:0] state;
reg [DIV_WIDTH-1:0] clk_count;
reg [2:0] bit_index;
reg [7:0] data_r;

assign tx_ready = (state == S_IDLE);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;
        clk_count <= {DIV_WIDTH{1'b0}};
        bit_index <= 3'd0;
        data_r <= 8'd0;
        tx <= 1'b1;
        tx_busy <= 1'b0;
    end else begin
        case (state)
            S_IDLE: begin
                tx <= 1'b1;
                tx_busy <= 1'b0;
                clk_count <= {DIV_WIDTH{1'b0}};
                bit_index <= 3'd0;
                if (tx_start) begin
                    data_r <= tx_data;
                    tx_busy <= 1'b1;
                    tx <= 1'b0;
                    state <= S_START;
                end
            end

            S_START: begin
                tx <= 1'b0;
                tx_busy <= 1'b1;
                if (clk_count == CLKS_PER_BIT - 1) begin
                    clk_count <= {DIV_WIDTH{1'b0}};
                    state <= S_DATA;
                end else begin
                    clk_count <= clk_count + 1'b1;
                end
            end

            S_DATA: begin
                tx <= data_r[bit_index];
                tx_busy <= 1'b1;
                if (clk_count == CLKS_PER_BIT - 1) begin
                    clk_count <= {DIV_WIDTH{1'b0}};
                    if (bit_index == 3'd7) begin
                        bit_index <= 3'd0;
                        state <= S_STOP;
                    end else begin
                        bit_index <= bit_index + 1'b1;
                    end
                end else begin
                    clk_count <= clk_count + 1'b1;
                end
            end

            S_STOP: begin
                tx <= 1'b1;
                tx_busy <= 1'b1;
                if (clk_count == CLKS_PER_BIT - 1) begin
                    clk_count <= {DIV_WIDTH{1'b0}};
                    state <= S_IDLE;
                end else begin
                    clk_count <= clk_count + 1'b1;
                end
            end

            default: begin
                state <= S_IDLE;
                tx <= 1'b1;
                tx_busy <= 1'b0;
            end
        endcase
    end
end

endmodule
