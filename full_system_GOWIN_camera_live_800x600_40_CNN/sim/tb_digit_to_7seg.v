`timescale 1ns/1ps

module tb_digit_to_7seg;

reg [3:0] digit;
wire [6:0] seg;
integer errors;

digit_to_7seg dut (
    .digit(digit),
    .seg(seg)
);

task check_seg;
    input [3:0] t_digit;
    input [6:0] expected;
    begin
        digit = t_digit;
        #1;
        if (seg !== expected) begin
            errors = errors + 1;
            $display("FAIL tb_digit_to_7seg digit=%0d got=%b expected=%b",
                     t_digit, seg, expected);
        end
    end
endtask

initial begin
    errors = 0;

    check_seg(4'd0, 7'b1111110);
    check_seg(4'd1, 7'b0110000);
    check_seg(4'd2, 7'b1101101);
    check_seg(4'd3, 7'b1111001);
    check_seg(4'd4, 7'b0110011);
    check_seg(4'd5, 7'b1011011);
    check_seg(4'd6, 7'b1011111);
    check_seg(4'd7, 7'b1110000);
    check_seg(4'd8, 7'b1111111);
    check_seg(4'd9, 7'b1111011);
    check_seg(4'd10, 7'b0000000);
    check_seg(4'd15, 7'b0000000);

    if (errors == 0)
        $display("PASS tb_digit_to_7seg");
    else
        $display("FAIL tb_digit_to_7seg errors=%0d", errors);
    $finish;
end

endmodule
