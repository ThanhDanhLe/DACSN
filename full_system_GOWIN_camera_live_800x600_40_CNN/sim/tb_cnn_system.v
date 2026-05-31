`timescale 1ns/1ps

module tb_cnn_system;

reg clk = 1'b0;
reg rst_n = 1'b0;
always #5 clk = ~clk;

reg start;
reg image_preload_valid;
reg image_preload_wr_en;
reg [8:0] image_preload_wr_addr;
reg [31:0] image_preload_wr_data;

wire image_rd_en;
wire [9:0] image_rd_addr;
reg [15:0] image_rd_data;
wire flash_cs_n;
wire flash_sclk;
wire flash_mosi;
wire flash_miso;
wire flash_command_error;
wire busy;
wire done;
wire output_valid;
wire [3:0] output_class;
wire error;

reg [31:0] image_words [0:783];
reg [15:0] image_pixels [0:783];
reg [3:0] golden_classes [0:1];
integer sample;
integer i;
integer timeout;
integer errors;
integer valid_count;

cnn_system #(
    .ACT_ADDR_WIDTH(9),
    .SPI_DIV(1),
    .FLASH_PARAM_BASE(24'h200000)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .memory_ready(1'b1),
    .image_rd_en(image_rd_en),
    .image_rd_addr(image_rd_addr),
    .image_rd_data(image_rd_data),
    .image_preload_valid(image_preload_valid),
    .image_preload_wr_en(image_preload_wr_en),
    .image_preload_wr_addr(image_preload_wr_addr),
    .image_preload_wr_data(image_preload_wr_data),
    .flash_cs_n(flash_cs_n),
    .flash_sclk(flash_sclk),
    .flash_mosi(flash_mosi),
    .flash_miso(flash_miso),
    .busy(busy),
    .done(done),
    .output_valid(output_valid),
    .output_class(output_class),
    .error(error)
);

cnn_spi_flash_param_model u_flash (
    .flash_cs_n(flash_cs_n),
    .flash_sclk(flash_sclk),
    .flash_mosi(flash_mosi),
    .flash_miso(flash_miso),
    .command_error(flash_command_error)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        image_rd_data <= 16'd0;
    end else if (image_rd_en) begin
        image_rd_data <= image_pixels[image_rd_addr];
    end
end

task fail;
    input [255:0] msg;
    begin
        $display("FAIL tb_cnn_system: %0s", msg);
        errors = errors + 1;
    end
endtask

task preload_sample;
    input integer sample_idx;
    integer base;
    begin
        image_preload_valid <= 1'b0;
        base = sample_idx * 392;
        for (i = 0; i < 392; i = i + 1) begin
            @(posedge clk);
            image_preload_wr_en <= 1'b1;
            image_preload_wr_addr <= i[8:0];
            image_preload_wr_data <= image_words[base + i];
            image_pixels[{i[8:0], 1'b0}] <= {8'd0, image_words[base + i][7:0]};
            image_pixels[{i[8:0], 1'b1}] <= {8'd0, image_words[base + i][23:16]};
        end
        @(posedge clk);
        image_preload_wr_en <= 1'b0;
        image_preload_wr_addr <= 9'd0;
        image_preload_wr_data <= 32'd0;
        image_preload_valid <= 1'b1;
        repeat (4) @(posedge clk);
    end
endtask

task run_inference;
    input integer sample_idx;
    begin
        preload_sample(sample_idx);
        valid_count = 0;
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        repeat (20) @(posedge clk);
        if (!busy)
            fail("busy did not assert after start");

        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        timeout = 0;
        while (!output_valid && !error && (timeout < 160000000)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (output_valid)
            valid_count = valid_count + 1;

        if (timeout >= 160000000)
            fail("system timeout");
        if (error)
            fail("system error asserted");
        if (!done)
            fail("done did not pulse with output_valid");
        if (valid_count != 1) begin
            $display("valid_count=%0d", valid_count);
            fail("start while busy caused unexpected output count");
        end
        if (output_class !== golden_classes[sample_idx]) begin
            $display("sample=%0d got_class=%0d expected=%0d",
                     sample_idx, output_class, golden_classes[sample_idx]);
            fail("class mismatch");
        end

        repeat (100) begin
            @(posedge clk);
            if (output_valid)
                valid_count = valid_count + 1;
        end
        if (valid_count != 1) begin
            $display("valid_count=%0d", valid_count);
            fail("start while busy caused unexpected output count");
        end

        image_preload_valid <= 1'b0;
        repeat (20) @(posedge clk);
    end
endtask

initial begin
    errors = 0;
    start = 1'b0;
    image_preload_valid = 1'b0;
    image_preload_wr_en = 1'b0;
    image_preload_wr_addr = 9'd0;
    image_preload_wr_data = 32'd0;
    for (i = 0; i < 784; i = i + 1)
        image_pixels[i] = 16'd0;

    $readmemh("data/cnn_tb_image_words.mem", image_words);
    $readmemh("data/cnn_tb_classes.mem", golden_classes);

    repeat (8) @(posedge clk);
    rst_n <= 1'b1;
    repeat (8) @(posedge clk);

    run_inference(0);
    run_inference(1);

    if (flash_command_error)
        fail("flash model saw a non-fast-read command");

    if (errors == 0)
        $display("PASS tb_cnn_system");
    else
        $display("FAIL tb_cnn_system errors=%0d", errors);
    $finish;
end

wire image_unused = ^image_rd_addr;

endmodule
