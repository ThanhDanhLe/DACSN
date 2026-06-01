`timescale 1ns/1ps

module tb_cdc_result_class_latch;

reg src_clk = 1'b0;
reg dst_clk = 1'b0;
reg src_rst_n = 1'b0;
reg dst_rst_n = 1'b0;
reg src_valid = 1'b0;
reg [3:0] src_class = 4'h0;
wire [3:0] displayed_class_pix;
wire displayed_class_valid_pix;

integer errors;
integer update_count;
reg [3:0] last_displayed_class;

always #5 src_clk = ~src_clk;
always #7 dst_clk = ~dst_clk;

cdc_result_class_latch dut (
    .src_clk(src_clk),
    .src_rst_n(src_rst_n),
    .src_valid(src_valid),
    .src_class(src_class),
    .dst_clk(dst_clk),
    .dst_rst_n(dst_rst_n),
    .displayed_class_pix(displayed_class_pix),
    .displayed_class_valid_pix(displayed_class_valid_pix)
);

task fail;
    input [8*72-1:0] msg;
    begin
        errors = errors + 1;
        $display("FAIL tb_cdc_result_class_latch: %0s", msg);
    end
endtask

task wait_dst_cycles;
    input integer count;
    integer i;
    begin
        for (i = 0; i < count; i = i + 1)
            @(posedge dst_clk);
    end
endtask

task wait_src_cycles;
    input integer count;
    integer i;
    begin
        for (i = 0; i < count; i = i + 1)
            @(posedge src_clk);
    end
endtask

task start_result;
    input [3:0] klass;
    begin
        @(posedge src_clk);
        src_class <= klass;
        src_valid <= 1'b1;
    end
endtask

task clear_result;
    begin
        @(posedge src_clk);
        src_valid <= 1'b0;
    end
endtask

always @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
        update_count <= 0;
        last_displayed_class <= 4'hF;
    end else begin
        if ((displayed_class_pix !== last_displayed_class) &&
            displayed_class_valid_pix) begin
            update_count <= update_count + 1;
        end
        last_displayed_class <= displayed_class_pix;
    end
end

initial begin
    errors = 0;

    wait_src_cycles(3);
    wait_dst_cycles(3);
    src_rst_n = 1'b1;
    dst_rst_n = 1'b1;
    wait_dst_cycles(5);

    if (displayed_class_valid_pix !== 1'b0)
        fail("valid asserted after reset without a result");

    start_result(4'd3);
    wait_dst_cycles(8);
    if (displayed_class_valid_pix !== 1'b1)
        fail("display valid did not assert for first result");
    if (displayed_class_pix !== 4'd3)
        fail("first class was not captured");

    wait_dst_cycles(6);
    if (displayed_class_pix !== 4'd3)
        fail("displayed class changed without a new result");

    clear_result();
    wait_dst_cycles(6);
    if (displayed_class_valid_pix !== 1'b0)
        fail("display valid did not clear after source valid fell");

    start_result(4'd8);
    wait_dst_cycles(8);
    if (displayed_class_valid_pix !== 1'b1)
        fail("display valid did not assert for second result");
    if (displayed_class_pix !== 4'd8)
        fail("second class was not captured");

    if (update_count < 2)
        fail("class update count missed result events");

    if (errors == 0)
        $display("PASS tb_cdc_result_class_latch");
    else
        $display("FAIL tb_cdc_result_class_latch errors=%0d", errors);
    $finish;
end

endmodule
