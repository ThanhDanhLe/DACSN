`timescale 1ns/1ps

module streaming_mnist_capture_stub #(
    parameter H_RES = 800,
    parameter V_RES = 600,
    parameter ROI_X0 = 176,
    parameter ROI_Y0 = 76,
    parameter ROI_SIZE = 448
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        arm,
    input  wire        vsync,
    input  wire        href,
    input  wire        pixel_valid,
    input  wire [15:0] rgb565,
    output reg         capture_arm_sync,
    output reg         capture_active,
    output reg         frame_seen,
    output reg  [11:0] x_count,
    output reg  [11:0] y_count,
    output reg  [18:0] roi_pixel_count
);

localparam [11:0] ROI_X1 = ROI_X0 + ROI_SIZE;
localparam [11:0] ROI_Y1 = ROI_Y0 + ROI_SIZE;

reg arm_d;
reg vsync_d;
reg href_d;
reg frame_waiting;
reg href_seen_in_frame;

wire arm_rise = arm & ~arm_d;
wire vsync_rise = vsync & ~vsync_d;
wire href_rise = href & ~href_d;
wire href_fall = ~href & href_d;
wire in_roi = capture_active && pixel_valid &&
              (x_count >= ROI_X0) && (x_count < ROI_X1) &&
              (y_count >= ROI_Y0) && (y_count < ROI_Y1);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        arm_d <= 1'b0;
        vsync_d <= 1'b0;
        href_d <= 1'b0;
        frame_waiting <= 1'b0;
        href_seen_in_frame <= 1'b0;
        capture_arm_sync <= 1'b0;
        capture_active <= 1'b0;
        frame_seen <= 1'b0;
        x_count <= 12'd0;
        y_count <= 12'd0;
        roi_pixel_count <= 19'd0;
    end else begin
        arm_d <= arm;
        vsync_d <= vsync;
        href_d <= href;
        frame_seen <= 1'b0;

        if (arm_rise) begin
            frame_waiting <= 1'b1;
            capture_arm_sync <= 1'b1;
        end

        if (vsync_rise) begin
            frame_seen <= 1'b1;
            x_count <= 12'd0;
            y_count <= 12'd0;
            href_seen_in_frame <= 1'b0;
            if (frame_waiting) begin
                capture_active <= 1'b1;
                frame_waiting <= 1'b0;
                capture_arm_sync <= 1'b0;
                roi_pixel_count <= 19'd0;
            end
        end

        if (capture_active) begin
            if (href_rise) begin
                x_count <= 12'd0;
                if (href_seen_in_frame)
                    y_count <= y_count + 12'd1;
                else
                    href_seen_in_frame <= 1'b1;
            end else if (pixel_valid && href) begin
                x_count <= x_count + 12'd1;
            end

            if (in_roi)
                roi_pixel_count <= roi_pixel_count + 19'd1;

            if (href_fall && (y_count == (V_RES - 1)))
                capture_active <= 1'b0;
        end
    end
end

endmodule
