`timescale 1ns/1ps

module tb_capture_dump_controller;

localparam integer CLK_HZ = 1000000;
localparam integer BAUD = 250000;
localparam integer CLKS_PER_BIT = (CLK_HZ + (BAUD / 2)) / BAUD;
localparam integer PIXEL_COUNT = 784;
localparam integer HEADER_LEN = 61;
localparam integer FOOTER_LEN = 13;
localparam integer EXPECTED_MAX = 8192;

reg clk = 1'b0;
reg rst_n = 1'b0;
reg start = 1'b0;
wire ram_rd_en;
wire [9:0] ram_rd_addr;
reg [15:0] ram_rd_data = 16'd0;
wire uart_tx_o;
wire busy;
wire done;

reg [7:0] rx_bytes [0:EXPECTED_MAX-1];
reg [7:0] expected [0:EXPECTED_MAX-1];
integer rx_count;
integer expected_len;
integer errors;
integer i;
integer addr_i;
integer wait_cycles;
reg [7:0] pixel_tmp;
reg [7:0] held_pending_data;
reg       held_pending_valid;

always #5 clk = ~clk;

capture_dump_controller #(
    .CLK_HZ(CLK_HZ),
    .BAUD(BAUD),
    .PIXEL_COUNT(PIXEL_COUNT),
    .UART_TEST_MODE(0)
) u_dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .ram_rd_en(ram_rd_en),
    .ram_rd_addr(ram_rd_addr),
    .ram_rd_data(ram_rd_data),
    .uart_tx_o(uart_tx_o),
    .busy(busy),
    .done(done)
);

function [7:0] pixel_for_addr;
    input integer addr;
    begin
        pixel_for_addr = (addr * 37 + 8'h5a) & 8'hff;
    end
endfunction

function [7:0] dec_char;
    input integer value;
    begin
        dec_char = 8'h30 + value[3:0];
    end
endfunction

function [7:0] hex_char;
    input [3:0] value;
    begin
        hex_char = (value < 4'd10) ? (8'h30 + {4'd0, value}) : (8'h41 + ({4'd0, value} - 8'd10));
    end
endfunction

function [7:0] header_char;
    input integer idx;
    begin
        case (idx)
            0:  header_char = "B";
            1:  header_char = "E";
            2:  header_char = "G";
            3:  header_char = "I";
            4:  header_char = "N";
            5:  header_char = "_";
            6:  header_char = "C";
            7:  header_char = "A";
            8:  header_char = "P";
            9:  header_char = "T";
            10: header_char = "U";
            11: header_char = "R";
            12: header_char = "E";
            13: header_char = 8'h0d;
            14: header_char = 8'h0a;
            15: header_char = "t";
            16: header_char = "h";
            17: header_char = "r";
            18: header_char = "e";
            19: header_char = "s";
            20: header_char = "h";
            21: header_char = "o";
            22: header_char = "l";
            23: header_char = "d";
            24: header_char = "=";
            25: header_char = "1";
            26: header_char = "0";
            27: header_char = "0";
            28: header_char = 8'h0d;
            29: header_char = 8'h0a;
            30: header_char = "r";
            31: header_char = "o";
            32: header_char = "i";
            33: header_char = "=";
            34: header_char = "4";
            35: header_char = "4";
            36: header_char = "8";
            37: header_char = 8'h0d;
            38: header_char = 8'h0a;
            39: header_char = "b";
            40: header_char = "l";
            41: header_char = "o";
            42: header_char = "c";
            43: header_char = "k";
            44: header_char = "=";
            45: header_char = "1";
            46: header_char = "6";
            47: header_char = 8'h0d;
            48: header_char = 8'h0a;
            49: header_char = "a";
            50: header_char = "d";
            51: header_char = "d";
            52: header_char = "r";
            53: header_char = ",";
            54: header_char = "v";
            55: header_char = "a";
            56: header_char = "l";
            57: header_char = "u";
            58: header_char = "e";
            59: header_char = 8'h0d;
            60: header_char = 8'h0a;
            default: header_char = 8'h00;
        endcase
    end
endfunction

function [7:0] footer_char;
    input integer idx;
    begin
        case (idx)
            0:  footer_char = "E";
            1:  footer_char = "N";
            2:  footer_char = "D";
            3:  footer_char = "_";
            4:  footer_char = "C";
            5:  footer_char = "A";
            6:  footer_char = "P";
            7:  footer_char = "T";
            8:  footer_char = "U";
            9:  footer_char = "R";
            10: footer_char = "E";
            11: footer_char = 8'h0d;
            12: footer_char = 8'h0a;
            default: footer_char = 8'h00;
        endcase
    end
endfunction

task append_expected;
    input [7:0] value;
    begin
        expected[expected_len] = value;
        expected_len = expected_len + 1;
    end
endtask

task build_expected_dump;
    begin
        expected_len = 0;
        for (i = 0; i < HEADER_LEN; i = i + 1)
            append_expected(header_char(i));

        for (addr_i = 0; addr_i < PIXEL_COUNT; addr_i = addr_i + 1) begin
            if (addr_i >= 100)
                append_expected(dec_char(addr_i / 100));
            if (addr_i >= 10)
                append_expected(dec_char((addr_i / 10) % 10));
            append_expected(dec_char(addr_i % 10));
            append_expected(",");
            append_expected("0");
            append_expected("x");
            pixel_tmp = pixel_for_addr(addr_i);
            append_expected(hex_char(pixel_tmp[7:4]));
            append_expected(hex_char(pixel_tmp[3:0]));
            append_expected(8'h0d);
            append_expected(8'h0a);
        end

        for (i = 0; i < FOOTER_LEN; i = i + 1)
            append_expected(footer_char(i));
    end
endtask

always @(posedge clk) begin
    if (ram_rd_en)
        ram_rd_data <= {8'd0, pixel_for_addr(ram_rd_addr)};
end

always @(posedge clk) begin
    if (rst_n && u_dut.byte_accepted) begin
        if (rx_count < EXPECTED_MAX) begin
            rx_bytes[rx_count] = u_dut.pending_data;
            rx_count = rx_count + 1;
        end else begin
            $display("FAIL: received more than EXPECTED_MAX bytes");
            errors = errors + 1;
        end
    end
end

always @(posedge clk) begin
    if (!rst_n) begin
        held_pending_data <= 8'd0;
        held_pending_valid <= 1'b0;
    end else if (u_dut.pending_valid && !u_dut.byte_accepted) begin
        if (held_pending_valid && (held_pending_data !== u_dut.pending_data)) begin
            $display("FAIL: pending UART byte changed before acceptance");
            errors = errors + 1;
        end
        held_pending_data <= u_dut.pending_data;
        held_pending_valid <= 1'b1;
    end else begin
        held_pending_valid <= 1'b0;
    end
end

initial begin : main
    errors = 0;
    rx_count = 0;
    build_expected_dump();

    rst_n = 1'b0;
    start = 1'b0;
    held_pending_valid = 1'b0;
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    start = 1'b1;
    @(posedge clk);
    start = 1'b0;

    wait_cycles = 0;
    while ((rx_count < expected_len) && (wait_cycles < 2000000)) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
    end

    if (rx_count != expected_len) begin
        $display("FAIL: expected %0d UART bytes, received %0d", expected_len, rx_count);
        errors = errors + 1;
    end else begin
        for (i = 0; i < expected_len; i = i + 1) begin
            if (rx_bytes[i] !== expected[i]) begin
                $display("FAIL: byte %0d expected 0x%02x got 0x%02x", i, expected[i], rx_bytes[i]);
                errors = errors + 1;
            end
        end
    end

    repeat (2) @(posedge clk);
    if (!done)
        errors = errors + 1;

    if (errors == 0) begin
        $display("TB PASS: capture_dump_controller emitted exact 784-pixel UART dump");
    end else begin
        $display("TB FAIL: capture_dump_controller errors=%0d", errors);
    end
    $finish;
end

endmodule
