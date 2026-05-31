`timescale 1ns/1ps

module tb_streaming_mnist_preload_pack;

reg clk = 1'b0;
always #5 clk = ~clk;

reg rst_n;
reg start;
wire ram_rd_en;
wire [9:0] ram_rd_addr;
reg [15:0] ram_rd_data;
wire preload_wr_en;
wire [8:0] preload_wr_addr;
wire [31:0] preload_wr_data;
wire busy;
wire done;

reg [15:0] mem [0:783];
integer i;
integer errors;
integer preload_count;
integer test_id;
integer timeout_count;
reg [31:0] expected_word;

streaming_mnist_preload_packer dut (
    .clk(clk),
    .rst_n(rst_n),
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

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        ram_rd_data <= 16'd0;
    else if (ram_rd_en)
        ram_rd_data <= mem[ram_rd_addr];
end

always @(posedge clk) begin
    #1;
    if (preload_wr_en) begin
        expected_word = {mem[preload_count * 2 + 1], mem[preload_count * 2]};
        if (preload_wr_addr !== preload_count[8:0]) begin
            $display("FAIL test %0d: preload addr got %0d expected %0d",
                     test_id, preload_wr_addr, preload_count);
            errors = errors + 1;
        end
        if (preload_wr_data !== expected_word) begin
            $display("FAIL test %0d: word %0d got %08h expected %08h",
                     test_id, preload_count, preload_wr_data, expected_word);
            errors = errors + 1;
        end
        preload_count = preload_count + 1;
    end
end

task fill_incrementing;
    begin
        for (i = 0; i < 784; i = i + 1)
            mem[i] = {8'd0, i[7:0]};
    end
endtask

task fill_zero;
    begin
        for (i = 0; i < 784; i = i + 1)
            mem[i] = 16'd0;
    end
endtask

task fill_onehot;
    input integer hot_idx;
    begin
        for (i = 0; i < 784; i = i + 1)
            mem[i] = (i == hot_idx) ? 16'h00a5 : 16'd0;
    end
endtask

task fill_pseudorandom;
    reg [31:0] lfsr;
    begin
        lfsr = 32'h12345678;
        for (i = 0; i < 784; i = i + 1) begin
            lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
            mem[i] = lfsr[15:0];
        end
    end
endtask

task run_case;
    input integer id;
    begin
        test_id = id;
        preload_count = 0;
        timeout_count = 0;
        repeat (3) @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        while (!done && timeout_count < 3000) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end

        if (!done) begin
            $display("FAIL test %0d: timeout waiting for done", test_id);
            errors = errors + 1;
        end

        repeat (3) @(posedge clk);
        if (preload_count != 392) begin
            $display("FAIL test %0d: preload_count got %0d expected 392",
                     test_id, preload_count);
            errors = errors + 1;
        end
    end
endtask

initial begin
    errors = 0;
    test_id = 0;
    preload_count = 0;
    start = 1'b0;
    rst_n = 1'b0;
    ram_rd_data = 16'd0;

    fill_zero();
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    fill_incrementing();
    run_case(0);

    fill_zero();
    run_case(1);

    fill_onehot(0);
    run_case(2);

    fill_onehot(1);
    run_case(3);

    fill_onehot(782);
    run_case(4);

    fill_onehot(783);
    run_case(5);

    fill_pseudorandom();
    run_case(6);

    if (errors == 0)
        $display("TB PASS: streaming_mnist_preload_packer packing checks passed");
    else
        $display("TB FAIL: %0d error(s)", errors);
    $finish;
end

endmodule
