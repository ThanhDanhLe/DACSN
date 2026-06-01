`timescale 1ns/1ps

module tb_leaf_cnn_helpers;
localparam ACC_WIDTH = 36;

reg [4:0] yy;
reg [4:0] xx;
reg [4:0] cc;
wire [9:0] addr_img28;
wire [9:0] addr_14c4;
wire [9:0] addr_7c8;
wire [9:0] addr_7c16;

reg [31:0] word;
reg half_sel;
wire signed [15:0] selected;

reg [31:0] value32;
wire signed [ACC_WIDTH-1:0] sext_acc;

reg [15:0] pixel_word;
wire signed [15:0] pixel_i16;

reg signed [ACC_WIDTH-1:0] acc_value;
wire signed [15:0] relu15;
wire signed [15:0] relu16;

integer errors;
integer y_i;
integer x_i;
integer c_i;

leaf_addr_img28 u_img28(.yy(yy), .xx(xx), .addr(addr_img28));
leaf_addr_14c4 u_14c4(.yy(yy), .xx(xx), .cc(cc), .addr(addr_14c4));
leaf_addr_7c8 u_7c8(.yy(yy), .xx(xx), .cc(cc), .addr(addr_7c8));
leaf_addr_7c16 u_7c16(.yy(yy), .xx(xx), .cc(cc), .addr(addr_7c16));
leaf_select_i16 u_select(.word(word), .half_sel(half_sel), .out(selected));
leaf_sext32_to_acc #(.ACC_WIDTH(ACC_WIDTH)) u_sext(.value(value32), .out(sext_acc));
leaf_input_u8_to_i16 u_input(.pixel_word(pixel_word), .out(pixel_i16));
leaf_relu_shift_sat #(.ACC_WIDTH(ACC_WIDTH), .SHIFT(15)) u_relu15(.value(acc_value), .out(relu15));
leaf_relu_shift_sat #(.ACC_WIDTH(ACC_WIDTH), .SHIFT(16)) u_relu16(.value(acc_value), .out(relu16));

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

initial begin
    errors = 0;

    for (y_i = 0; y_i < 28; y_i = y_i + 1) begin
        for (x_i = 0; x_i < 28; x_i = x_i + 1) begin
            yy = y_i[4:0];
            xx = x_i[4:0];
            #1;
            check(addr_img28 === ((y_i * 28) + x_i), "img28 address");
        end
    end

    for (y_i = 0; y_i < 14; y_i = y_i + 1) begin
        for (x_i = 0; x_i < 14; x_i = x_i + 1) begin
            for (c_i = 0; c_i < 4; c_i = c_i + 1) begin
                yy = y_i[4:0];
                xx = x_i[4:0];
                cc = c_i[4:0];
                #1;
                check(addr_14c4 === ((y_i * 56) + (x_i * 4) + c_i), "14c4 address");
            end
        end
    end

    for (y_i = 0; y_i < 7; y_i = y_i + 1) begin
        for (x_i = 0; x_i < 7; x_i = x_i + 1) begin
            for (c_i = 0; c_i < 8; c_i = c_i + 1) begin
                yy = y_i[4:0];
                xx = x_i[4:0];
                cc = c_i[4:0];
                #1;
                check(addr_7c8 === ((y_i * 56) + (x_i * 8) + c_i), "7c8 address");
            end
            for (c_i = 0; c_i < 16; c_i = c_i + 1) begin
                yy = y_i[4:0];
                xx = x_i[4:0];
                cc = c_i[4:0];
                #1;
                check(addr_7c16 === ((y_i * 112) + (x_i * 16) + c_i), "7c16 address");
            end
        end
    end

    word = 32'h8001_7fff;
    half_sel = 1'b0;
    #1;
    check(selected === 16'sh7fff, "select low");
    half_sel = 1'b1;
    #1;
    check(selected === 16'sh8001, "select high");

    value32 = 32'h8000_0001;
    #1;
    check(sext_acc === {{(ACC_WIDTH-32){1'b1}}, value32}, "sign extend negative");
    value32 = 32'h0000_1234;
    #1;
    check(sext_acc === {{(ACC_WIDTH-32){1'b0}}, value32}, "sign extend positive");

    pixel_word = 16'hab5c;
    #1;
    check(pixel_i16 === 16'sh005c, "input u8 to i16");

    acc_value = -36'sd1;
    #1;
    check(relu15 === 16'sd0 && relu16 === 16'sd0, "relu negative");
    acc_value = 36'sd0;
    #1;
    check(relu15 === 16'sd0 && relu16 === 16'sd0, "relu zero");
    acc_value = 36'sd65536;
    #1;
    check(relu15 === 16'sd2 && relu16 === 16'sd1, "relu shifts");
    acc_value = 36'sd32768 <<< 16;
    #1;
    check(relu16 === 16'sd32767, "relu saturation");

    if (errors == 0)
        $display("PASS tb_leaf_cnn_helpers");
    else
        $display("FAIL tb_leaf_cnn_helpers errors=%0d", errors);
    $finish;
end

endmodule
