`timescale 1ns/1ps

module tb_streaming_mnist_capture_stub;

reg clk = 1'b0;
reg rst_n = 1'b0;
reg arm = 1'b0;
reg vsync = 1'b0;
reg href = 1'b0;
reg pixel_valid = 1'b0;
reg [15:0] rgb565 = 16'hFFFF;

wire capture_arm_sync;
wire capture_active;
wire frame_seen;
wire [11:0] x_count;
wire [11:0] y_count;
wire [18:0] roi_pixel_count;

always #5 clk = ~clk;

streaming_mnist_capture_stub #(
    .H_RES(8),
    .V_RES(6),
    .ROI_X0(2),
    .ROI_Y0(1),
    .ROI_SIZE(3)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .arm(arm),
    .vsync(vsync),
    .href(href),
    .pixel_valid(pixel_valid),
    .rgb565(rgb565),
    .capture_arm_sync(capture_arm_sync),
    .capture_active(capture_active),
    .frame_seen(frame_seen),
    .x_count(x_count),
    .y_count(y_count),
    .roi_pixel_count(roi_pixel_count)
);

task send_frame;
    integer y;
    integer x;
    begin
        @(posedge clk);
        vsync <= 1'b1;
        @(posedge clk);
        vsync <= 1'b0;
        for (y = 0; y < 6; y = y + 1) begin
            @(posedge clk);
            href <= 1'b1;
            for (x = 0; x < 8; x = x + 1) begin
                pixel_valid <= 1'b1;
                rgb565 <= x + (y << 4);
                @(posedge clk);
            end
            pixel_valid <= 1'b0;
            href <= 1'b0;
            @(posedge clk);
        end
    end
endtask

initial begin
    repeat (3) @(posedge clk);
    rst_n <= 1'b1;

    @(negedge clk);
    arm <= 1'b1;
    @(negedge clk);
    arm <= 1'b0;
    @(posedge clk);

    if (!capture_arm_sync) begin
        $display("FAIL: arm was not latched while waiting for frame");
        $finish;
    end

    send_frame();
    repeat (2) @(posedge clk);

    if (roi_pixel_count !== 19'd9) begin
        $display("FAIL: expected 9 ROI pixels, got %0d", roi_pixel_count);
        $finish;
    end

    if (capture_active) begin
        $display("FAIL: capture_active did not drop after final line");
        $finish;
    end

    $display("TB PASS: streaming_mnist_capture_stub frame/ROI counters passed");
    $finish;
end

endmodule
