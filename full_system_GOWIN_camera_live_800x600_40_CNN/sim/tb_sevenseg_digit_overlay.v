`timescale 1ns/1ps

module tb_sevenseg_digit_overlay;

reg active;
reg [10:0] x;
reg [10:0] y;
reg [6:0] seg;
wire overlay_on;
wire [23:0] overlay_rgb;
wire overlay_on_fast;
wire [23:0] overlay_rgb_fast;
integer errors;

sevenseg_digit_overlay #(
    .X0(10),
    .Y0(20),
    .W(40),
    .H(70),
    .T(5)
) dut (
    .active(active),
    .x(x),
    .y(y),
    .seg(seg),
    .overlay_on(overlay_on),
    .overlay_rgb(overlay_rgb)
);

sevenseg_digit_overlay #(
    .X0(0),
    .Y0(0),
    .W(64),
    .H(128),
    .T(8),
    .FAST_POWER2(1)
) dut_fast (
    .active(active),
    .x(x),
    .y(y),
    .seg(seg),
    .overlay_on(overlay_on_fast),
    .overlay_rgb(overlay_rgb_fast)
);

task expect_on;
    input [10:0] t_x;
    input [10:0] t_y;
    input [6:0]  t_seg;
    input        expected;
    input [8*48-1:0] msg;
    begin
        active = 1'b1;
        x = t_x;
        y = t_y;
        seg = t_seg;
        #1;
        if (overlay_on !== expected) begin
            errors = errors + 1;
            $display("FAIL tb_sevenseg_digit_overlay %0s got=%b expected=%b",
                     msg, overlay_on, expected);
        end
    end
endtask

initial begin
    errors = 0;
    active = 1'b0;
    x = 11'd20;
    y = 11'd22;
    seg = 7'b1111111;
    #1;
    if (overlay_on !== 1'b0) begin
        errors = errors + 1;
        $display("FAIL tb_sevenseg_digit_overlay inactive gate");
    end

    expect_on(11'd20, 11'd22, 7'b1000000, 1'b1, "segment A on");
    expect_on(11'd48, 11'd30, 7'b0100000, 1'b1, "segment B on");
    expect_on(11'd48, 11'd70, 7'b0010000, 1'b1, "segment C on");
    expect_on(11'd20, 11'd87, 7'b0001000, 1'b1, "segment D on");
    expect_on(11'd12, 11'd70, 7'b0000100, 1'b1, "segment E on");
    expect_on(11'd12, 11'd30, 7'b0000010, 1'b1, "segment F on");
    expect_on(11'd20, 11'd55, 7'b0000001, 1'b1, "segment G on");
    expect_on(11'd48, 11'd30, 7'b1000000, 1'b0, "segment mask off");
    expect_on(11'd60, 11'd22, 7'b1111111, 1'b0, "outside bbox x");
    expect_on(11'd20, 11'd95, 7'b1111111, 1'b0, "outside bbox y");

    active = 1'b1;
    x = 11'd16;
    y = 11'd2;
    seg = 7'b1000000;
    #1;
    if (overlay_on_fast !== 1'b1) begin
        errors = errors + 1;
        $display("FAIL tb_sevenseg_digit_overlay fast segment A");
    end

    x = 11'd60;
    y = 11'd40;
    seg = 7'b0100000;
    #1;
    if (overlay_on_fast !== 1'b1) begin
        errors = errors + 1;
        $display("FAIL tb_sevenseg_digit_overlay fast segment B");
    end

    x = 11'd90;
    y = 11'd2;
    seg = 7'b1111111;
    #1;
    if (overlay_on_fast !== 1'b0) begin
        errors = errors + 1;
        $display("FAIL tb_sevenseg_digit_overlay fast outside bbox");
    end

    if (overlay_rgb !== 24'h00FF40) begin
        errors = errors + 1;
        $display("FAIL tb_sevenseg_digit_overlay color got=%h", overlay_rgb);
    end
    if (overlay_rgb_fast !== 24'h00FF40) begin
        errors = errors + 1;
        $display("FAIL tb_sevenseg_digit_overlay fast color got=%h", overlay_rgb_fast);
    end

    if (errors == 0)
        $display("PASS tb_sevenseg_digit_overlay");
    else
        $display("FAIL tb_sevenseg_digit_overlay errors=%0d", errors);
    $finish;
end

endmodule
