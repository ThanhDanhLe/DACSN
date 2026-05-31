`timescale 1ns/1ps

module tb_mnist28_upscale_renderer;

localparam H_RES = 800;
localparam V_RES = 600;
localparam ROI_X0 = 176;
localparam ROI_Y0 = 76;
localparam SCALE_LOG2 = 4;
localparam MNIST_SIZE = 28;
localparam ROI_SIZE = MNIST_SIZE << SCALE_LOG2;
localparam ROI_X1 = ROI_X0 + ROI_SIZE;
localparam ROI_Y1 = ROI_Y0 + ROI_SIZE;

reg pix_clk = 1'b0;
reg i_clk = 1'b0;
reg pix_rst_n = 1'b0;
reg i_rst_n = 1'b0;

always #12.5 pix_clk = ~pix_clk;
always #18.5 i_clk = ~i_clk;

reg enable;
reg [11:0] video_x;
reg [11:0] video_y;
reg active_video;

wire renderer_rd_en;
wire [9:0] renderer_rd_addr;
wire [4:0] renderer_rd_x;
wire [4:0] renderer_rd_y;
wire [15:0] renderer_rd_data;
wire [7:0] out_r;
wire [7:0] out_g;
wire [7:0] out_b;
wire out_valid;

wire rd_en_i;
wire [9:0] rd_addr_i;
reg [15:0] rd_data_i;

reg [7:0] mem [0:783];
integer i;
integer sx;
integer sy;
integer errors;
integer checked_inside;
integer checked_outside;

mnist28_row_cache_bridge #(
    .ROI_X0(ROI_X0),
    .ROI_Y0(ROI_Y0),
    .SCALE_LOG2(SCALE_LOG2),
    .MNIST_SIZE(MNIST_SIZE)
) dut_bridge (
    .i_clk(i_clk),
    .i_rst_n(i_rst_n),
    .pix_clk(pix_clk),
    .pix_rst_n(pix_rst_n),
    .enable_i(enable),
    .enable_pix(enable),
    .video_x(video_x),
    .video_y(video_y),
    .active_video(active_video),
    .mnist_rd_en_i(rd_en_i),
    .mnist_rd_addr_i(rd_addr_i),
    .mnist_rd_data_i(rd_data_i),
    .renderer_rd_en(renderer_rd_en),
    .renderer_rd_x(renderer_rd_x),
    .renderer_rd_y(renderer_rd_y),
    .renderer_rd_data(renderer_rd_data)
);

mnist28_upscale_renderer #(
    .H_RES(H_RES),
    .V_RES(V_RES),
    .ROI_X0(ROI_X0),
    .ROI_Y0(ROI_Y0),
    .SCALE_LOG2(SCALE_LOG2),
    .MNIST_SIZE(MNIST_SIZE),
    .LOOKAHEAD(0),
    .OUTPUT_ADDR(0)
) dut_renderer (
    .pix_clk(pix_clk),
    .rst_n(pix_rst_n),
    .enable(enable),
    .video_x(video_x),
    .video_y(video_y),
    .active_video(active_video),
    .mnist_rd_en(renderer_rd_en),
    .mnist_rd_addr(renderer_rd_addr),
    .mnist_rd_x(renderer_rd_x),
    .mnist_rd_y(renderer_rd_y),
    .mnist_rd_data(renderer_rd_data),
    .out_r(out_r),
    .out_g(out_g),
    .out_b(out_b),
    .out_valid(out_valid)
);

always @(posedge i_clk) begin
    if (rd_en_i && (rd_addr_i >= 10'd784)) begin
        fail("bridge requested address outside 28x28 image");
    end

    if (rd_en_i)
        rd_data_i <= {8'd0, mem[rd_addr_i]};
    else
        rd_data_i <= 16'd0;
end

function [9:0] addr_for_screen;
    input [11:0] x;
    input [11:0] y;
    reg [4:0] mx;
    reg [4:0] my;
    begin
        mx = (x - ROI_X0) >> SCALE_LOG2;
        my = (y - ROI_Y0) >> SCALE_LOG2;
        addr_for_screen = ({my, 5'b00000} - {my, 2'b00}) + mx;
    end
endfunction

function [7:0] gray_for_addr;
    input [9:0] addr;
    reg [7:0] mixed;
    begin
        mixed = (addr[7:0] ^ {addr[3:0], addr[7:4]}) + 8'd17;
        gray_for_addr = (mixed == 8'd0) ? 8'd90 : mixed;
    end
endfunction

task fail;
    input [255:0] msg;
    begin
        if (errors < 20)
            $display("FAIL tb_mnist28_upscale_renderer: %0s", msg);
        errors = errors + 1;
    end
endtask

task drive_and_check;
    input [11:0] x;
    input [11:0] y;
    input        active;
    reg inside;
    reg [9:0] expected_addr;
    reg [7:0] expected_gray;
    begin
        @(negedge pix_clk);
        video_x = x;
        video_y = y;
        active_video = active;

        inside = enable && active &&
                 (x >= ROI_X0) && (x < ROI_X1) &&
                 (y >= ROI_Y0) && (y < ROI_Y1);

        #1;
        if (inside) begin
            expected_addr = addr_for_screen(x, y);
            if (!renderer_rd_en)
                fail("renderer did not assert rd_en inside ROI");
            if (renderer_rd_addr !== 10'd0)
                fail("renderer address output should be disabled in top configuration");
            if (renderer_rd_x !== ((x - ROI_X0) >> SCALE_LOG2))
                fail("renderer x mapping mismatch");
            if (renderer_rd_y !== ((y - ROI_Y0) >> SCALE_LOG2))
                fail("renderer y mapping mismatch");
        end else if (renderer_rd_en) begin
            fail("renderer asserted rd_en outside ROI");
        end

        @(posedge pix_clk);
        #1;
        if (inside) begin
            expected_addr = addr_for_screen(x, y);
            expected_gray = gray_for_addr(expected_addr);
            checked_inside = checked_inside + 1;
            if (!out_valid)
                fail("inside ROI did not assert out_valid");
            if ((out_r !== expected_gray) ||
                (out_g !== expected_gray) ||
                (out_b !== expected_gray)) begin
                if (errors < 20) begin
                    $display("screen=(%0d,%0d) addr=%0d got_rgb=(%0d,%0d,%0d) expected=%0d",
                             x, y, expected_addr, out_r, out_g, out_b, expected_gray);
                end
                fail("bridge/renderer gray output mismatch");
            end
        end else begin
            checked_outside = checked_outside + 1;
            if (out_valid)
                fail("outside ROI asserted out_valid");
            if ((out_r !== 8'd0) || (out_g !== 8'd0) || (out_b !== 8'd0))
                fail("outside ROI was not black");
        end
    end
endtask

initial begin
    errors = 0;
    checked_inside = 0;
    checked_outside = 0;
    enable = 1'b0;
    active_video = 1'b0;
    video_x = 12'd0;
    video_y = 12'd0;
    rd_data_i = 16'd0;

    for (i = 0; i < 784; i = i + 1)
        mem[i] = gray_for_addr(i[9:0]);

    repeat (8) @(posedge pix_clk);
    i_rst_n = 1'b1;
    pix_rst_n = 1'b1;
    enable = 1'b1;

    drive_and_check(12'd0, ROI_Y0 - 1, 1'b1);
    for (sx = ROI_X0; sx < ROI_X1; sx = sx + 1)
        drive_and_check(sx[11:0], ROI_Y0 - 1, 1'b1);

    for (sy = ROI_Y0; sy < ROI_Y1; sy = sy + 1) begin
        for (sx = 0; sx < ROI_X1 + 2; sx = sx + 1)
            drive_and_check(sx[11:0], sy[11:0], 1'b1);
    end

    for (sx = ROI_X0; sx < ROI_X1; sx = sx + 1)
        drive_and_check(sx[11:0], ROI_Y1[11:0], 1'b1);

    enable = 1'b0;
    drive_and_check(ROI_X0[11:0], ROI_Y0[11:0], 1'b1);

    if (errors == 0) begin
        $display("PASS tb_mnist28_upscale_renderer continuous bridge scan inside=%0d outside=%0d",
                 checked_inside, checked_outside);
    end else begin
        $display("FAIL tb_mnist28_upscale_renderer errors=%0d inside=%0d outside=%0d",
                 errors, checked_inside, checked_outside);
    end
    $finish;
end

wire unused = ^renderer_rd_data ^ ^rd_addr_i;

endmodule
