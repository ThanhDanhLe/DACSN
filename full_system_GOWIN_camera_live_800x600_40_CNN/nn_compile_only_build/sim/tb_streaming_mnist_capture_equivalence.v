`timescale 1ns/1ps

module tb_streaming_mnist_capture_equivalence;

localparam H_RES = 528;
localparam V_RES = 528;
localparam ROI_X0 = 32;
localparam ROI_Y0 = 32;
localparam ROI_SIZE = 448;
localparam MNIST_SIZE = 28;

localparam TEST_WHITE   = 0;
localparam TEST_BLACK   = 1;
localparam TEST_VSTROKE = 2;
localparam TEST_HSTROKE = 3;
localparam TEST_SQUARE  = 4;
localparam TEST_DIGIT0  = 5;
localparam TEST_DIGIT1  = 6;
localparam TEST_NOISY   = 7;

reg clk = 1'b0;
reg rst_n = 1'b0;

reg ref_start = 1'b0;
reg ref_frame_start = 1'b0;
reg ref_pixel_valid = 1'b0;
reg [11:0] ref_pixel_x = 12'd0;
reg [11:0] ref_pixel_y = 12'd0;
reg [15:0] ref_rgb565 = 16'hFFFF;

reg dut_arm = 1'b0;
reg dut_vsync = 1'b0;
reg dut_href = 1'b0;
reg dut_pixel_valid = 1'b0;
reg [15:0] dut_rgb565 = 16'hFFFF;

wire ref_wr_en;
wire [9:0] ref_wr_addr;
wire [15:0] ref_wr_data;
wire ref_done;
wire ref_error;

wire dut_wr_en;
wire [9:0] dut_wr_addr;
wire [15:0] dut_wr_data;
wire dut_done;
wire dut_error;

integer errors;
integer pattern_id;
integer x;
integer y;
integer i;
integer ref_write_count;
integer dut_write_count;
integer ref_done_seen;
integer dut_done_seen;
integer dut_error_seen;
integer early_error_seen;

reg [7:0] ref_mem [0:783];
reg [7:0] dut_mem [0:783];

always #5 clk = ~clk;

image_processing_vfb_stream #(
    .H_RES(H_RES),
    .V_RES(V_RES),
    .ROI_X0(ROI_X0),
    .ROI_Y0(ROI_Y0),
    .ROI_SIZE(ROI_SIZE),
    .BLOCK_SIZE(16),
    .MNIST_SIZE(MNIST_SIZE),
    .THRESHOLD(8'd100)
) u_ref (
    .clk(clk),
    .rst_n(rst_n),
    .start(ref_start),
    .frame_start(ref_frame_start),
    .pixel_valid(ref_pixel_valid),
    .pixel_x(ref_pixel_x),
    .pixel_y(ref_pixel_y),
    .pixel_rgb565(ref_rgb565),
    .mnist_wr_en(ref_wr_en),
    .mnist_wr_addr(ref_wr_addr),
    .mnist_wr_data(ref_wr_data),
    .busy(),
    .done(ref_done),
    .error(ref_error)
);

streaming_mnist_capture #(
    .H_RES(H_RES),
    .V_RES(V_RES),
    .ROI_X0(ROI_X0),
    .ROI_Y0(ROI_Y0),
    .ROI_SIZE(ROI_SIZE),
    .BLOCK_SIZE(16),
    .MNIST_SIZE(MNIST_SIZE),
    .THRESHOLD(8'd100)
) u_dut (
    .clk(clk),
    .rst_n(rst_n),
    .capture_arm(dut_arm),
    .vsync(dut_vsync),
    .href(dut_href),
    .pixel_valid(dut_pixel_valid),
    .rgb565(dut_rgb565),
    .mnist_wr_en(dut_wr_en),
    .mnist_wr_addr(dut_wr_addr),
    .mnist_wr_data(dut_wr_data),
    .capture_busy(),
    .capture_done(dut_done),
    .capture_error(dut_error),
    .waiting_for_frame(),
    .x_count(),
    .y_count(),
    .roi_pixel_count(),
    .mnist_write_count()
);

function [15:0] rgb_from_gray;
    input [7:0] gray;
    begin
        rgb_from_gray = {gray[7:3], gray[7:2], gray[7:3]};
    end
endfunction

function in_digit0;
    input integer px;
    input integer py;
    integer lx;
    integer ly;
    begin
        lx = px - ROI_X0;
        ly = py - ROI_Y0;
        in_digit0 = ((lx >= 112) && (lx < 336) && (ly >= 80) && (ly < 368) &&
                     ((lx < 144) || (lx >= 304) || (ly < 112) || (ly >= 336)));
    end
endfunction

function in_digit1;
    input integer px;
    input integer py;
    integer lx;
    integer ly;
    begin
        lx = px - ROI_X0;
        ly = py - ROI_Y0;
        in_digit1 = (((lx >= 216) && (lx < 248) && (ly >= 80) && (ly < 360)) ||
                     ((lx >= 176) && (lx < 248) && (ly >= 80) && (ly < 120)) ||
                     ((lx >= 168) && (lx < 296) && (ly >= 328) && (ly < 360)));
    end
endfunction

function [15:0] pixel_for_pattern;
    input integer test_id;
    input integer px;
    input integer py;
    integer lx;
    integer ly;
    reg [7:0] bg_gray;
    begin
        lx = px - ROI_X0;
        ly = py - ROI_Y0;
        bg_gray = 8'd255;
        if (test_id == TEST_NOISY)
            bg_gray = 8'd235 - ((px + (py * 3)) & 8'h0F);

        if (test_id == TEST_BLACK) begin
            pixel_for_pattern = rgb_from_gray(8'd0);
        end else if ((test_id == TEST_VSTROKE) &&
                     (lx >= (12 * 16)) && (lx < (13 * 16)) &&
                     (ly >= 0) && (ly < ROI_SIZE)) begin
            pixel_for_pattern = rgb_from_gray(8'd0);
        end else if ((test_id == TEST_HSTROKE) &&
                     (ly >= (13 * 16)) && (ly < (14 * 16)) &&
                     (lx >= 0) && (lx < ROI_SIZE)) begin
            pixel_for_pattern = rgb_from_gray(8'd0);
        end else if ((test_id == TEST_SQUARE) &&
                     (lx >= 176) && (lx < 272) &&
                     (ly >= 176) && (ly < 272)) begin
            pixel_for_pattern = rgb_from_gray(8'd0);
        end else if ((test_id == TEST_DIGIT0) && in_digit0(px, py)) begin
            pixel_for_pattern = rgb_from_gray(8'd0);
        end else if ((test_id == TEST_DIGIT1) && in_digit1(px, py)) begin
            pixel_for_pattern = rgb_from_gray(8'd0);
        end else if ((test_id == TEST_NOISY) &&
                     (lx >= 192) && (lx < 240) &&
                     (ly >= 80) && (ly < 368)) begin
            pixel_for_pattern = rgb_from_gray(8'd0);
        end else begin
            pixel_for_pattern = rgb_from_gray(bg_gray);
        end
    end
endfunction

always @(posedge clk) begin
    if (ref_done)
        ref_done_seen = 1;
    if (dut_done)
        dut_done_seen = 1;
    if (dut_error)
        dut_error_seen = 1;

    if (ref_wr_en) begin
        if (ref_wr_addr !== ref_write_count[9:0]) begin
            $display("FAIL pattern %0d: ref addr got %0d expected %0d",
                     pattern_id, ref_wr_addr, ref_write_count);
            errors = errors + 1;
        end
        if (ref_wr_addr < 784)
            ref_mem[ref_wr_addr] = ref_wr_data[7:0];
        ref_write_count = ref_write_count + 1;
    end

    if (dut_wr_en) begin
        if (dut_wr_addr !== dut_write_count[9:0]) begin
            $display("FAIL pattern %0d: dut addr got %0d expected %0d",
                     pattern_id, dut_wr_addr, dut_write_count);
            errors = errors + 1;
        end
        if (dut_wr_addr < 784)
            dut_mem[dut_wr_addr] = dut_wr_data[7:0];
        dut_write_count = dut_write_count + 1;
    end
end

task clear_results;
    begin
        ref_write_count = 0;
        dut_write_count = 0;
        ref_done_seen = 0;
        dut_done_seen = 0;
        dut_error_seen = 0;
        for (i = 0; i < 784; i = i + 1) begin
            ref_mem[i] = 8'hXX;
            dut_mem[i] = 8'hXX;
        end
    end
endtask

task reset_duts;
    begin
        rst_n = 1'b0;
        ref_start = 1'b0;
        ref_frame_start = 1'b0;
        ref_pixel_valid = 1'b0;
        ref_pixel_x = 12'd0;
        ref_pixel_y = 12'd0;
        ref_rgb565 = 16'hFFFF;
        dut_arm = 1'b0;
        dut_vsync = 1'b0;
        dut_href = 1'b0;
        dut_pixel_valid = 1'b0;
        dut_rgb565 = 16'hFFFF;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);
    end
endtask

task arm_both_before_frame;
    begin
        @(negedge clk);
        ref_start = 1'b1;
        dut_arm = 1'b1;
        @(negedge clk);
        ref_start = 1'b0;
        dut_arm = 1'b0;
        @(posedge clk);
    end
endtask

task send_full_frame;
    input integer test_id;
    input integer ref_uses_frame_start;
    reg [15:0] pix;
    begin
        @(negedge clk);
        dut_vsync = 1'b1;
        ref_frame_start = ref_uses_frame_start;
        ref_pixel_valid = 1'b0;
        dut_pixel_valid = 1'b0;
        dut_href = 1'b0;
        @(negedge clk);
        dut_vsync = 1'b0;
        ref_frame_start = 1'b0;

        for (y = 0; y < V_RES; y = y + 1) begin
            @(negedge clk);
            dut_href = 1'b1;
            ref_pixel_valid = 1'b0;
            dut_pixel_valid = 1'b0;
            @(negedge clk);
            for (x = 0; x < H_RES; x = x + 1) begin
                pix = pixel_for_pattern(test_id, x, y);
                ref_pixel_x = x[11:0];
                ref_pixel_y = y[11:0];
                ref_rgb565 = pix;
                dut_rgb565 = pix;
                ref_pixel_valid = 1'b1;
                dut_pixel_valid = 1'b1;
                @(negedge clk);
            end
            ref_pixel_valid = 1'b0;
            dut_pixel_valid = 1'b0;
            dut_href = 1'b0;
            @(negedge clk);
        end
    end
endtask

task send_cut_frame;
    integer cut_y;
    begin
        @(negedge clk);
        dut_vsync = 1'b1;
        @(negedge clk);
        dut_vsync = 1'b0;
        for (cut_y = 0; cut_y < 40; cut_y = cut_y + 1) begin
            @(negedge clk);
            dut_href = 1'b1;
            @(negedge clk);
            for (x = 0; x < H_RES; x = x + 1) begin
                dut_rgb565 = 16'hFFFF;
                dut_pixel_valid = 1'b1;
                @(negedge clk);
            end
            dut_pixel_valid = 1'b0;
            dut_href = 1'b0;
            @(negedge clk);
        end
        dut_vsync = 1'b1;
        @(negedge clk);
        dut_vsync = 1'b0;
    end
endtask

task compare_results;
    begin
        repeat (80) @(posedge clk);
        if (!ref_done_seen) begin
            $display("FAIL pattern %0d: reference done missing", pattern_id);
            errors = errors + 1;
        end
        if (!dut_done_seen) begin
            $display("FAIL pattern %0d: streaming done missing", pattern_id);
            errors = errors + 1;
        end
        if (dut_error_seen) begin
            $display("FAIL pattern %0d: streaming error asserted", pattern_id);
            errors = errors + 1;
        end
        if (ref_write_count != 784) begin
            $display("FAIL pattern %0d: reference wrote %0d expected 784",
                     pattern_id, ref_write_count);
            errors = errors + 1;
        end
        if (dut_write_count != 784) begin
            $display("FAIL pattern %0d: streaming wrote %0d expected 784",
                     pattern_id, dut_write_count);
            errors = errors + 1;
        end
        for (i = 0; i < 784; i = i + 1) begin
            if (ref_mem[i] !== dut_mem[i]) begin
                $display("FAIL pattern %0d: pixel %0d ref=%0d dut=%0d",
                         pattern_id, i, ref_mem[i], dut_mem[i]);
                errors = errors + 1;
            end
        end
    end
endtask

task run_pattern;
    input integer test_id;
    begin
        pattern_id = test_id;
        clear_results();
        reset_duts();
        arm_both_before_frame();
        send_full_frame(test_id, 1);
        compare_results();
    end
endtask

task run_mid_frame_arm_test;
    begin
        pattern_id = TEST_DIGIT1;
        clear_results();
        reset_duts();

        @(negedge clk);
        dut_vsync = 1'b1;
        @(negedge clk);
        dut_vsync = 1'b0;
        for (y = 0; y < 12; y = y + 1) begin
            @(negedge clk);
            dut_href = 1'b1;
            @(negedge clk);
            if (y == 4)
                dut_arm = 1'b1;
            for (x = 0; x < H_RES; x = x + 1) begin
                dut_rgb565 = 16'hFFFF;
                dut_pixel_valid = 1'b1;
                @(negedge clk);
                dut_arm = 1'b0;
            end
            dut_pixel_valid = 1'b0;
            dut_href = 1'b0;
            @(negedge clk);
        end

        @(negedge clk);
        ref_start = 1'b1;
        @(negedge clk);
        ref_start = 1'b0;
        send_full_frame(TEST_DIGIT1, 1);
        compare_results();
    end
endtask

task run_early_vsync_error_test;
    begin
        clear_results();
        reset_duts();
        @(negedge clk);
        dut_arm = 1'b1;
        @(negedge clk);
        dut_arm = 1'b0;
        send_cut_frame();
        repeat (20) @(posedge clk);
        early_error_seen = dut_error_seen;
        if (!early_error_seen) begin
            $display("FAIL early-frame test: expected capture_error");
            errors = errors + 1;
        end
        if (dut_done_seen) begin
            $display("FAIL early-frame test: done asserted on cut frame");
            errors = errors + 1;
        end
    end
endtask

initial begin
    errors = 0;
    pattern_id = -1;
    early_error_seen = 0;

    run_pattern(TEST_WHITE);
    run_pattern(TEST_BLACK);
    run_pattern(TEST_VSTROKE);
    run_pattern(TEST_HSTROKE);
    run_pattern(TEST_SQUARE);
    run_pattern(TEST_DIGIT0);
    run_pattern(TEST_DIGIT1);
    run_pattern(TEST_NOISY);
    run_mid_frame_arm_test();
    run_early_vsync_error_test();

    if (errors == 0)
        $display("TB PASS: streaming_mnist_capture matches mode-2 reference");
    else
        $display("TB FAIL: %0d error(s)", errors);
    $finish;
end

endmodule
