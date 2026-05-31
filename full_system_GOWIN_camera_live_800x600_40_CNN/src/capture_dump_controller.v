`timescale 1ns/1ps

module capture_dump_controller #(
    parameter integer CLK_HZ = 27000000,
    parameter integer BAUD = 115200,
    parameter integer PIXEL_COUNT = 784,
    parameter integer UART_TEST_MODE = 0
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output wire        ram_rd_en,
    output wire [9:0]  ram_rd_addr,
    input  wire [15:0] ram_rd_data,
    output wire        uart_tx_o,
    output reg         busy,
    output reg         done
);

localparam integer HEADER_LEN = 61;
localparam integer FOOTER_LEN = 13;
localparam integer TEST_LEN = 17;

localparam [4:0]
    S_IDLE       = 5'd0,
    S_TEST       = 5'd1,
    S_HEADER     = 5'd2,
    S_READ       = 5'd3,
    S_CAPTURE    = 5'd4,
    S_ADDR_HUND  = 5'd5,
    S_ADDR_TENS  = 5'd6,
    S_ADDR_ONES  = 5'd7,
    S_COMMA      = 5'd8,
    S_ZERO       = 5'd9,
    S_X          = 5'd10,
    S_HEX_HI     = 5'd11,
    S_HEX_LO     = 5'd12,
    S_CR         = 5'd13,
    S_LF         = 5'd14,
    S_NEXT       = 5'd15,
    S_FOOTER     = 5'd16,
    S_DONE       = 5'd17;

reg [4:0] state;
reg [9:0] pixel_index;
reg [7:0] pixel_value;
reg [6:0] text_index;
reg [3:0] addr_hundreds;
reg [3:0] addr_tens;
reg [3:0] addr_ones;
reg [7:0] pending_data;
reg       pending_valid;

wire uart_ready;
wire uart_start = pending_valid & uart_ready;
wire byte_accepted = uart_start;
wire uart_busy_unused;

assign ram_rd_en = (state == S_READ);
assign ram_rd_addr = pixel_index;

uart_tx #(
    .CLK_HZ(CLK_HZ),
    .BAUD(BAUD)
) u_uart_tx (
    .clk(clk),
    .rst_n(rst_n),
    .tx_start(uart_start),
    .tx_data(pending_data),
    .tx(uart_tx_o),
    .tx_busy(uart_busy_unused),
    .tx_ready(uart_ready)
);

function [7:0] dec_char;
    input [3:0] value;
    begin
        dec_char = 8'h30 + {4'd0, value};
    end
endfunction

function [7:0] header_char;
    input [6:0] idx;
    begin
        case (idx)
            7'd0:  header_char = "B";
            7'd1:  header_char = "E";
            7'd2:  header_char = "G";
            7'd3:  header_char = "I";
            7'd4:  header_char = "N";
            7'd5:  header_char = "_";
            7'd6:  header_char = "C";
            7'd7:  header_char = "A";
            7'd8:  header_char = "P";
            7'd9:  header_char = "T";
            7'd10: header_char = "U";
            7'd11: header_char = "R";
            7'd12: header_char = "E";
            7'd13: header_char = 8'h0d;
            7'd14: header_char = 8'h0a;
            7'd15: header_char = "t";
            7'd16: header_char = "h";
            7'd17: header_char = "r";
            7'd18: header_char = "e";
            7'd19: header_char = "s";
            7'd20: header_char = "h";
            7'd21: header_char = "o";
            7'd22: header_char = "l";
            7'd23: header_char = "d";
            7'd24: header_char = "=";
            7'd25: header_char = "1";
            7'd26: header_char = "0";
            7'd27: header_char = "0";
            7'd28: header_char = 8'h0d;
            7'd29: header_char = 8'h0a;
            7'd30: header_char = "r";
            7'd31: header_char = "o";
            7'd32: header_char = "i";
            7'd33: header_char = "=";
            7'd34: header_char = "4";
            7'd35: header_char = "4";
            7'd36: header_char = "8";
            7'd37: header_char = 8'h0d;
            7'd38: header_char = 8'h0a;
            7'd39: header_char = "b";
            7'd40: header_char = "l";
            7'd41: header_char = "o";
            7'd42: header_char = "c";
            7'd43: header_char = "k";
            7'd44: header_char = "=";
            7'd45: header_char = "1";
            7'd46: header_char = "6";
            7'd47: header_char = 8'h0d;
            7'd48: header_char = 8'h0a;
            7'd49: header_char = "a";
            7'd50: header_char = "d";
            7'd51: header_char = "d";
            7'd52: header_char = "r";
            7'd53: header_char = ",";
            7'd54: header_char = "v";
            7'd55: header_char = "a";
            7'd56: header_char = "l";
            7'd57: header_char = "u";
            7'd58: header_char = "e";
            7'd59: header_char = 8'h0d;
            7'd60: header_char = 8'h0a;
            default: header_char = 8'h00;
        endcase
    end
endfunction

function [7:0] footer_char;
    input [6:0] idx;
    begin
        case (idx)
            7'd0:  footer_char = "E";
            7'd1:  footer_char = "N";
            7'd2:  footer_char = "D";
            7'd3:  footer_char = "_";
            7'd4:  footer_char = "C";
            7'd5:  footer_char = "A";
            7'd6:  footer_char = "P";
            7'd7:  footer_char = "T";
            7'd8:  footer_char = "U";
            7'd9:  footer_char = "R";
            7'd10: footer_char = "E";
            7'd11: footer_char = 8'h0d;
            7'd12: footer_char = 8'h0a;
            default: footer_char = 8'h00;
        endcase
    end
endfunction

function [7:0] test_char;
    input [6:0] idx;
    begin
        case (idx)
            7'd0:  test_char = "H";
            7'd1:  test_char = "E";
            7'd2:  test_char = "L";
            7'd3:  test_char = "L";
            7'd4:  test_char = "O";
            7'd5:  test_char = "_";
            7'd6:  test_char = "U";
            7'd7:  test_char = "A";
            7'd8:  test_char = "R";
            7'd9:  test_char = "T";
            7'd10: test_char = "_";
            7'd11: test_char = "T";
            7'd12: test_char = "E";
            7'd13: test_char = "S";
            7'd14: test_char = "T";
            7'd15: test_char = 8'h0d;
            7'd16: test_char = 8'h0a;
            default: test_char = 8'h00;
        endcase
    end
endfunction

function [7:0] hex_char;
    input [3:0] value;
    begin
        hex_char = (value < 4'd10) ? (8'h30 + {4'd0, value}) : (8'h41 + ({4'd0, value} - 8'd10));
    end
endfunction

task queue_byte;
    input [7:0] value;
    begin
        pending_data <= value;
        pending_valid <= 1'b1;
    end
endtask

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;
        pixel_index <= 10'd0;
        pixel_value <= 8'd0;
        text_index <= 7'd0;
        addr_hundreds <= 4'd0;
        addr_tens <= 4'd0;
        addr_ones <= 4'd0;
        pending_data <= 8'd0;
        pending_valid <= 1'b0;
        busy <= 1'b0;
        done <= 1'b0;
    end else begin
        done <= 1'b0;
        if (byte_accepted)
            pending_valid <= 1'b0;

        case (state)
            S_IDLE: begin
                busy <= 1'b0;
                text_index <= 7'd0;
                pending_valid <= 1'b0;
                if (UART_TEST_MODE != 0) begin
                    busy <= 1'b1;
                    state <= S_TEST;
                end else if (start) begin
                    busy <= 1'b1;
                    pixel_index <= 10'd0;
                    addr_hundreds <= 4'd0;
                    addr_tens <= 4'd0;
                    addr_ones <= 4'd0;
                    state <= S_HEADER;
                end
            end

            S_TEST: begin
                busy <= 1'b1;
                if (byte_accepted) begin
                    text_index <= (text_index == TEST_LEN - 1) ? 7'd0 : (text_index + 1'b1);
                end else if (!pending_valid) begin
                    queue_byte(test_char(text_index));
                end
            end

            S_HEADER: begin
                if (byte_accepted) begin
                    if (text_index == HEADER_LEN - 1) begin
                        text_index <= 7'd0;
                        state <= S_READ;
                    end else begin
                        text_index <= text_index + 1'b1;
                    end
                end else if (!pending_valid) begin
                    queue_byte(header_char(text_index));
                end
            end

            S_READ: begin
                state <= S_CAPTURE;
            end

            S_CAPTURE: begin
                pixel_value <= ram_rd_data[7:0];
                state <= S_ADDR_HUND;
            end

            S_ADDR_HUND: begin
                if (addr_hundreds != 4'd0) begin
                    if (byte_accepted)
                        state <= S_ADDR_TENS;
                    else if (!pending_valid)
                        queue_byte(dec_char(addr_hundreds));
                end else begin
                    state <= S_ADDR_TENS;
                end
            end

            S_ADDR_TENS: begin
                if ((addr_hundreds != 4'd0) || (addr_tens != 4'd0)) begin
                    if (byte_accepted)
                        state <= S_ADDR_ONES;
                    else if (!pending_valid)
                        queue_byte(dec_char(addr_tens));
                end else begin
                    state <= S_ADDR_ONES;
                end
            end

            S_ADDR_ONES: begin
                if (byte_accepted)
                    state <= S_COMMA;
                else if (!pending_valid)
                    queue_byte(dec_char(addr_ones));
            end

            S_COMMA: begin
                if (byte_accepted)
                    state <= S_ZERO;
                else if (!pending_valid)
                    queue_byte(",");
            end

            S_ZERO: begin
                if (byte_accepted)
                    state <= S_X;
                else if (!pending_valid)
                    queue_byte("0");
            end

            S_X: begin
                if (byte_accepted)
                    state <= S_HEX_HI;
                else if (!pending_valid)
                    queue_byte("x");
            end

            S_HEX_HI: begin
                if (byte_accepted)
                    state <= S_HEX_LO;
                else if (!pending_valid)
                    queue_byte(hex_char(pixel_value[7:4]));
            end

            S_HEX_LO: begin
                if (byte_accepted)
                    state <= S_CR;
                else if (!pending_valid)
                    queue_byte(hex_char(pixel_value[3:0]));
            end

            S_CR: begin
                if (byte_accepted)
                    state <= S_LF;
                else if (!pending_valid)
                    queue_byte(8'h0d);
            end

            S_LF: begin
                if (byte_accepted)
                    state <= S_NEXT;
                else if (!pending_valid)
                    queue_byte(8'h0a);
            end

            S_NEXT: begin
                if (pixel_index == PIXEL_COUNT - 1) begin
                    text_index <= 7'd0;
                    state <= S_FOOTER;
                end else begin
                    pixel_index <= pixel_index + 1'b1;
                    if (addr_ones == 4'd9) begin
                        addr_ones <= 4'd0;
                        if (addr_tens == 4'd9) begin
                            addr_tens <= 4'd0;
                            addr_hundreds <= addr_hundreds + 1'b1;
                        end else begin
                            addr_tens <= addr_tens + 1'b1;
                        end
                    end else begin
                        addr_ones <= addr_ones + 1'b1;
                    end
                    state <= S_READ;
                end
            end

            S_FOOTER: begin
                if (byte_accepted) begin
                    if (text_index == FOOTER_LEN - 1) begin
                        state <= S_DONE;
                    end else begin
                        text_index <= text_index + 1'b1;
                    end
                end else if (!pending_valid) begin
                    queue_byte(footer_char(text_index));
                end
            end

            S_DONE: begin
                busy <= 1'b0;
                done <= 1'b1;
                state <= S_IDLE;
            end

            default: begin
                state <= S_IDLE;
                busy <= 1'b0;
                pending_valid <= 1'b0;
            end
        endcase
    end
end

endmodule
