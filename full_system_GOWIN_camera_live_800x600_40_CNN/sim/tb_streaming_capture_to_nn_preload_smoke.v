`timescale 1ns/1ps

module tb_streaming_capture_to_nn_preload_smoke;

reg wr_clk = 1'b0;
reg rd_clk = 1'b0;
always #7 wr_clk = ~wr_clk;
always #5 rd_clk = ~rd_clk;

reg wr_rst_n;
reg rd_rst_n;
reg wr_en;
reg [9:0] wr_addr;
reg [15:0] wr_data;
reg start;
wire ram_rd_en;
wire [9:0] ram_rd_addr;
wire [15:0] ram_rd_data;
wire preload_wr_en;
wire [8:0] preload_wr_addr;
wire [31:0] preload_wr_data;
wire busy;
wire done;

reg [7:0] expected [0:783];
integer i;
integer errors;
integer preload_count;
integer timeout_count;
reg [31:0] expected_word;

mnist_image_buffer_dualclk u_buf (
    .wr_clk(wr_clk),
    .wr_rst_n(wr_rst_n),
    .wr_en(wr_en),
    .wr_addr(wr_addr),
    .wr_data(wr_data),
    .rd_clk(rd_clk),
    .rd_rst_n(rd_rst_n),
    .rd0_en(ram_rd_en),
    .rd0_addr(ram_rd_addr),
    .rd0_data(ram_rd_data),
    .rd1_en(1'b0),
    .rd1_addr(10'd0),
    .rd1_data()
);

streaming_mnist_preload_packer u_pack (
    .clk(rd_clk),
    .rst_n(rd_rst_n),
    .start(start),
    .ram_rd_en(ram_rd_en),
    .ram_rd_addr(ram_rd_addr),
    .ram_rd_data(ram_rd_data),
    .preload_wr_en(preload_wr_en),
    .preload_wr_addr(preload_wr_addr),
    .preload_wr_data(preload_wr_data),
    .busy(busy),
    .done(done)
);

always @(posedge rd_clk) begin
    #1;
    if (preload_wr_en) begin
        expected_word = {8'd0, expected[preload_count * 2 + 1],
                         8'd0, expected[preload_count * 2]};
        if (preload_wr_addr !== preload_count[8:0]) begin
            $display("FAIL: preload addr got %0d expected %0d",
                     preload_wr_addr, preload_count);
            errors = errors + 1;
        end
        if (preload_wr_data !== expected_word) begin
            $display("FAIL: preload data[%0d] got %08h expected %08h",
                     preload_count, preload_wr_data, expected_word);
            errors = errors + 1;
        end
        preload_count = preload_count + 1;
    end
end

task write_frame;
    begin
        wr_en = 1'b0;
        @(posedge wr_clk);
        for (i = 0; i < 784; i = i + 1) begin
            expected[i] = ((i * 17) + 8'h35) & 8'hFF;
            wr_addr = i[9:0];
            wr_data = {8'd0, expected[i]};
            wr_en = 1'b1;
            @(posedge wr_clk);
        end
        wr_en = 1'b0;
    end
endtask

initial begin
    errors = 0;
    preload_count = 0;
    timeout_count = 0;
    wr_rst_n = 1'b0;
    rd_rst_n = 1'b0;
    wr_en = 1'b0;
    wr_addr = 10'd0;
    wr_data = 16'd0;
    start = 1'b0;

    repeat (6) @(posedge rd_clk);
    wr_rst_n = 1'b1;
    rd_rst_n = 1'b1;
    repeat (6) @(posedge rd_clk);

    write_frame();
    repeat (8) @(posedge rd_clk);

    start = 1'b1;
    @(posedge rd_clk);
    start = 1'b0;

    while (!done && timeout_count < 3000) begin
        @(posedge rd_clk);
        timeout_count = timeout_count + 1;
    end

    if (!done) begin
        $display("FAIL: timeout waiting for preload done");
        errors = errors + 1;
    end

    repeat (4) @(posedge rd_clk);
    if (preload_count != 392) begin
        $display("FAIL: preload_count got %0d expected 392", preload_count);
        errors = errors + 1;
    end

    if (errors == 0)
        $display("TB PASS: dual-clock MNIST RAM to preload packer smoke passed");
    else
        $display("TB FAIL: %0d error(s)", errors);
    $finish;
end

endmodule

