`timescale 1ns/1ps

module tb_leaf_mnist_helpers;

reg [15:0] rgb565;
reg [7:0] avg_gray;
reg [7:0] threshold;
reg [4:0] addr_x;
reg [4:0] addr_y;
wire [7:0] gray;
wire [7:0] mnist_pixel;
wire [9:0] mnist_addr;

integer errors;

leaf_rgb565_green_to_gray u_gray (
    .rgb565(rgb565),
    .gray(gray)
);

leaf_mnist_threshold_invert u_threshold_invert (
    .gray(avg_gray),
    .threshold(threshold),
    .mnist_pixel(mnist_pixel)
);

leaf_mnist_addr_28x28 u_mnist_addr (
    .y(addr_y),
    .x(addr_x),
    .addr(mnist_addr)
);

function [7:0] ref_gray;
    input [15:0] f_rgb565;
    reg [5:0] green6;
    begin
        green6 = f_rgb565[10:5];
        ref_gray = {green6, green6[5:4]};
    end
endfunction

task check;
    input condition;
    input [8*48-1:0] msg;
    begin
        if (!condition) begin
            errors = errors + 1;
            $display("FAIL %0s", msg);
        end
    end
endtask

task check_gray;
    input [15:0] t_rgb565;
    begin
        rgb565 = t_rgb565;
        #1;
        check(gray === ref_gray(t_rgb565), "rgb565 green to gray");
    end
endtask

task check_threshold;
    input [7:0] t_gray;
    input [7:0] t_threshold;
    input [7:0] expected;
    begin
        avg_gray = t_gray;
        threshold = t_threshold;
        #1;
        check(mnist_pixel === expected, "threshold invert");
    end
endtask

task check_addr;
    input [4:0] t_y;
    input [4:0] t_x;
    input [9:0] expected;
    begin
        addr_y = t_y;
        addr_x = t_x;
        #1;
        check(mnist_addr === expected, "mnist addr");
    end
endtask

initial begin
    errors = 0;
    avg_gray = 8'd0;
    threshold = 8'd100;
    addr_x = 5'd0;
    addr_y = 5'd0;

    check_gray(16'h0000);
    check_gray(16'h07E0);
    check_gray(16'hFFFF);
    check_gray(16'h03E0);
    check_gray(16'h0420);
    check_threshold(8'd0, 8'd100, 8'd255);
    check_threshold(8'd99, 8'd100, 8'd156);
    check_threshold(8'd100, 8'd100, 8'd0);
    check_threshold(8'd255, 8'd100, 8'd0);
    check_addr(5'd0, 5'd0, 10'd0);
    check_addr(5'd1, 5'd0, 10'd28);
    check_addr(5'd13, 5'd27, 10'd391);
    check_addr(5'd27, 5'd27, 10'd783);

    if (errors == 0)
        $display("PASS tb_leaf_mnist_helpers");
    else
        $display("FAIL tb_leaf_mnist_helpers errors=%0d", errors);
    $finish;
end

endmodule
