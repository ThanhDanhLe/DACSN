`timescale 1ns/1ps

module cnn_spi_flash_param_model #(
    parameter [23:0] FLASH_BASE = 24'h200000,
    parameter integer TOTAL_BYTES = 9360,
    parameter PARAM_BIN = "data/lwdd_params_int16_int32.bin"
)(
    input  wire flash_cs_n,
    input  wire flash_sclk,
    input  wire flash_mosi,
    output reg  flash_miso,
    output reg  command_error
);

reg [7:0] param_bytes [0:TOTAL_BYTES-1];
reg [7:0] cmd_shift;
reg [23:0] addr_shift;
integer bit_count;
integer active_addr;
integer bit_idx;
integer fd;
integer nread;
integer i;
reg [7:0] current_byte;

function [7:0] flash_byte;
    input integer byte_addr;
    integer rel_addr;
    begin
        rel_addr = byte_addr - FLASH_BASE;
        if ((rel_addr >= 0) && (rel_addr < TOTAL_BYTES))
            flash_byte = param_bytes[rel_addr];
        else
            flash_byte = 8'h00;
    end
endfunction

initial begin
    for (i = 0; i < TOTAL_BYTES; i = i + 1)
        param_bytes[i] = 8'h00;
    fd = $fopen(PARAM_BIN, "rb");
    if (fd == 0) begin
        $display("FAIL cnn_spi_flash_param_model: cannot open %0s", PARAM_BIN);
        $fatal;
    end
    nread = $fread(param_bytes, fd);
    $fclose(fd);
    if (nread != TOTAL_BYTES) begin
        $display("FAIL cnn_spi_flash_param_model: read %0d bytes, expected %0d", nread, TOTAL_BYTES);
        $fatal;
    end
    flash_miso = 1'b0;
    command_error = 1'b0;
    bit_count = 0;
    active_addr = 0;
    bit_idx = 7;
    cmd_shift = 8'd0;
    addr_shift = 24'd0;
end

always @(posedge flash_sclk or posedge flash_cs_n) begin
    if (flash_cs_n) begin
        bit_count <= 0;
        active_addr <= 0;
        bit_idx <= 7;
        cmd_shift <= 8'd0;
        addr_shift <= 24'd0;
    end else begin
        if (bit_count < 8) begin
            cmd_shift <= {cmd_shift[6:0], flash_mosi};
            if ((bit_count == 7) && ({cmd_shift[6:0], flash_mosi} != 8'h0B)) begin
                command_error <= 1'b1;
                $display("FAIL cnn_spi_flash_param_model: SPI command is 0x%02h, expected 0x0B",
                         {cmd_shift[6:0], flash_mosi});
            end
        end else if (bit_count < 32) begin
            addr_shift <= {addr_shift[22:0], flash_mosi};
            if (bit_count == 31)
                active_addr <= {addr_shift[22:0], flash_mosi};
        end
        bit_count <= bit_count + 1;
    end
end

always @(negedge flash_sclk or posedge flash_cs_n) begin
    if (flash_cs_n) begin
        flash_miso <= 1'b0;
    end else if (bit_count >= 40) begin
        current_byte = flash_byte(active_addr);
        flash_miso <= current_byte[bit_idx];
        if (bit_idx == 0) begin
            bit_idx <= 7;
            active_addr <= active_addr + 1;
        end else begin
            bit_idx <= bit_idx - 1;
        end
    end
end

endmodule
