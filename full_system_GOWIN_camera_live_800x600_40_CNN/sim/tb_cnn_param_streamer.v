`timescale 1ns/1ps

module tb_cnn_param_streamer;

reg clk = 1'b0;
reg rst_n = 1'b0;
always #5 clk = ~clk;

reg param_req;
reg [31:0] param_word_offset;
reg [15:0] param_len_words;
wire param_ready;
wire param_busy;
wire param_done;
wire param_error;
wire [31:0] param_data;
wire param_data_valid;

wire flash_cs_n;
wire flash_sclk;
wire flash_mosi;
wire flash_miso;
wire flash_command_error;

reg [7:0] param_bytes [0:9359];
integer fd;
integer nread;
integer errors;
integer collected;
reg [31:0] collected_words [0:15];
integer timeout;
integer i;

cnn_param_streamer #(
    .SPI_DIV(1),
    .FLASH_PARAM_BASE(24'h200000),
    .TOTAL_WORDS(2340)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .param_req(param_req),
    .param_word_offset(param_word_offset),
    .param_len_words(param_len_words),
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

cnn_spi_flash_param_model u_flash (
    .flash_cs_n(flash_cs_n),
    .flash_sclk(flash_sclk),
    .flash_mosi(flash_mosi),
    .flash_miso(flash_miso),
    .command_error(flash_command_error)
);

function [31:0] expected_word;
    input integer word_idx;
    integer byte_idx;
    begin
        byte_idx = word_idx * 4;
        expected_word = {param_bytes[byte_idx + 3],
                         param_bytes[byte_idx + 2],
                         param_bytes[byte_idx + 1],
                         param_bytes[byte_idx + 0]};
    end
endfunction

task fail;
    input [255:0] msg;
    begin
        $display("FAIL tb_cnn_param_streamer: %0s", msg);
        errors = errors + 1;
    end
endtask

task request_and_check;
    input [31:0] word_offset;
    input [15:0] len_words;
    integer k;
    begin
        collected = 0;
        timeout = 0;
        @(posedge clk);
        while (!param_ready) @(posedge clk);
        param_word_offset <= word_offset;
        param_len_words <= len_words;
        param_req <= 1'b1;
        @(posedge clk);
        param_req <= 1'b0;

        while (!param_done && (timeout < 200000)) begin
            @(posedge clk);
            if (param_data_valid) begin
                if (collected < 16)
                    collected_words[collected] = param_data;
                collected = collected + 1;
            end
            timeout = timeout + 1;
        end
        if (timeout >= 200000) begin
            fail("timeout");
        end else begin
            if (param_error)
                fail("param_error asserted on valid request");
            if (collected != len_words) begin
                $display("expected %0d words, got %0d", len_words, collected);
                fail("word count mismatch");
            end
            for (k = 0; k < len_words; k = k + 1) begin
                if (collected_words[k] !== expected_word(word_offset + k)) begin
                    $display("offset=%0d got=%08h expected=%08h",
                             word_offset + k, collected_words[k], expected_word(word_offset + k));
                    fail("little-endian word mismatch");
                end
            end
        end
        repeat (4) @(posedge clk);
    end
endtask

initial begin
    errors = 0;
    param_req = 1'b0;
    param_word_offset = 32'd0;
    param_len_words = 16'd1;
    for (i = 0; i < 16; i = i + 1)
        collected_words[i] = 32'd0;

    fd = $fopen("data/lwdd_params_int16_int32.bin", "rb");
    if (fd == 0) begin
        $display("FAIL tb_cnn_param_streamer: cannot open parameter bin");
        $fatal;
    end
    nread = $fread(param_bytes, fd);
    $fclose(fd);
    if (nread != 9360) begin
        $display("FAIL tb_cnn_param_streamer: read %0d bytes", nread);
        $fatal;
    end

    repeat (8) @(posedge clk);
    rst_n <= 1'b1;
    repeat (4) @(posedge clk);

    request_and_check(32'd0, 16'd2);
    request_and_check(32'd17, 16'd1);
    request_and_check(32'd18, 16'd2);
    request_and_check(32'd89, 16'd1);
    request_and_check(32'd90, 16'd2);
    request_and_check(32'd2339, 16'd1);

    @(posedge clk);
    while (!param_ready) @(posedge clk);
    param_word_offset <= 32'd2340;
    param_len_words <= 16'd1;
    param_req <= 1'b1;
    @(posedge clk);
    param_req <= 1'b0;
    repeat (10) @(posedge clk);
    if (!param_error)
        fail("out-of-range request did not assert error");

    if (flash_command_error)
        fail("flash model saw a non-fast-read command");

    if (errors == 0)
        $display("PASS tb_cnn_param_streamer");
    else
        $display("FAIL tb_cnn_param_streamer errors=%0d", errors);
    $finish;
end

wire param_busy_unused = param_busy;

endmodule
