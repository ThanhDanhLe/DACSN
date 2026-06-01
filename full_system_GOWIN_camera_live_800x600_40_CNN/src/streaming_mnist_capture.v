`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// streaming_mnist_capture.v
//
// PIXCLK-domain streaming version of the accepted mode-2 MNIST preprocessing:
//   green-channel grayscale
//   16x16 block average into 28x28
//   threshold 100
//   mnist = (avg_gray < threshold) ? (255 - avg_gray) : 0
//
// This module is intentionally self-contained and writes a sequential 784-pixel
// MNIST frame. Multi-bit payload CDC is expected to use a dual-clock RAM or FIFO
// outside this block; only arm/done/error controls should cross by synchronizer.
// -----------------------------------------------------------------------------
module streaming_mnist_capture #(
    parameter H_RES = 800,
    parameter V_RES = 600,
    parameter ROI_X0 = 176,
    parameter ROI_Y0 = 76,
    parameter ROI_SIZE = 448,
    parameter BLOCK_SIZE = 16,
    parameter MNIST_SIZE = 28,
    parameter [7:0] THRESHOLD = 8'd100
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        capture_arm,
    input  wire        vsync,
    input  wire        href,
    input  wire        pixel_valid,
    input  wire [15:0] rgb565,

    output reg         mnist_wr_en,
    output reg  [9:0]  mnist_wr_addr,
    output reg  [15:0] mnist_wr_data,

    output reg         capture_busy,
    output reg         capture_done,
    output reg         capture_error,
    output reg         waiting_for_frame,
    output reg  [11:0] x_count,
    output reg  [11:0] y_count,
    output wire [18:0] roi_pixel_count,
    output wire [9:0]  mnist_write_count
);

localparam [2:0]
    S_IDLE      = 3'd0,
    S_RUN       = 3'd1,
    S_FLUSH_ROW = 3'd2,
    S_WRITE_ROW = 3'd3,
    S_CLEAR     = 3'd4;

localparam [11:0] ROI_X0_12 = ROI_X0;
localparam [11:0] ROI_Y0_12 = ROI_Y0;
localparam [11:0] ROI_X1_12 = ROI_X0 + ROI_SIZE;
localparam [11:0] ROI_Y1_12 = ROI_Y0 + ROI_SIZE;
reg [2:0]  state;
reg        vsync_d;
reg        href_d;
reg        href_seen_in_frame;
reg [12:0] col_sum [0:MNIST_SIZE-1] /* synthesis syn_ramstyle = "distributed_ram" */;
reg [4:0]  clear_idx;
reg [4:0]  wr_col;
reg [4:0]  wr_row;
reg [4:0]  stream_col;
reg [4:0]  stream_row;
reg [3:0]  stream_block_x;
reg [3:0]  stream_row_mod;
reg [8:0]  block_sum;
reg        update_valid_s0;
reg [4:0]  update_col_s0;
reg [8:0]  update_add_s0;
reg        update_valid_s1;
reg [4:0]  update_col_s1;
reg [8:0]  update_add_s1;

wire vsync_rise = vsync & ~vsync_d;
wire href_rise = href & ~href_d;

wire in_roi = (state == S_RUN) && href && pixel_valid &&
              (x_count >= ROI_X0_12) && (x_count < ROI_X1_12) &&
              (y_count >= ROI_Y0_12) && (y_count < ROI_Y1_12);

wire roi_row_end = (state == S_RUN) && href && pixel_valid &&
                   (x_count == ROI_X1_12) &&
                   (y_count >= ROI_Y0_12) && (y_count < ROI_Y1_12);

wire [7:0] pixel_gray;
wire [4:0] pixel_gray5 = pixel_gray[7:3];
wire [8:0] block_sum_with_pixel = block_sum + {4'd0, pixel_gray5};
wire [12:0] update_sum_next = col_sum[update_col_s1] + {4'd0, update_add_s1};

wire [7:0] avg_gray_raw = col_sum[wr_col][12:5];
wire [7:0] avg_gray = (avg_gray_raw == 8'd248) ? 8'd255 : avg_gray_raw;
wire [7:0] mnist_u8;
wire [9:0] mnist_wr_addr_next;

leaf_rgb565_green_to_gray u_leaf_rgb565_green_to_gray (
    .rgb565(rgb565),
    .gray(pixel_gray)
);

leaf_mnist_threshold_invert u_leaf_mnist_threshold_invert (
    .gray(avg_gray),
    .threshold(THRESHOLD),
    .mnist_pixel(mnist_u8)
);

leaf_mnist_addr_28x28 u_leaf_mnist_addr_28x28 (
    .y(wr_row),
    .x(wr_col),
    .addr(mnist_wr_addr_next)
);

// These diagnostic outputs are left in the interface for bench compatibility.
// The production design does not consume them, so avoid carrying two wide
// redundant counters in the saturated device.
assign roi_pixel_count = 19'd0;
assign mnist_write_count = mnist_wr_addr_next;

task start_capture;
    begin
        capture_busy <= 1'b1;
        waiting_for_frame <= 1'b0;
        state <= S_CLEAR;
        clear_idx <= 5'd0;
        wr_col <= 5'd0;
        wr_row <= 5'd0;
        stream_col <= 5'd0;
        stream_row <= 5'd0;
        stream_block_x <= 4'd0;
        stream_row_mod <= 4'd0;
        block_sum <= 9'd0;
        update_valid_s0 <= 1'b0;
        update_valid_s1 <= 1'b0;
        update_col_s0 <= 5'd0;
        update_col_s1 <= 5'd0;
        update_add_s0 <= 9'd0;
        update_add_s1 <= 9'd0;
    end
endtask

task fail_capture;
    begin
        capture_busy <= 1'b0;
        waiting_for_frame <= 1'b0;
        capture_error <= 1'b1;
        state <= S_IDLE;
        update_valid_s0 <= 1'b0;
        update_valid_s1 <= 1'b0;
    end
endtask

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mnist_wr_en <= 1'b0;
        mnist_wr_addr <= 10'd0;
        mnist_wr_data <= 16'd0;
        capture_busy <= 1'b0;
        capture_done <= 1'b0;
        capture_error <= 1'b0;
        waiting_for_frame <= 1'b0;
        x_count <= 12'd0;
        y_count <= 12'd0;
        clear_idx <= 5'd0;
        state <= S_IDLE;
        vsync_d <= 1'b0;
        href_d <= 1'b0;
        href_seen_in_frame <= 1'b0;
        wr_col <= 5'd0;
        wr_row <= 5'd0;
        stream_col <= 5'd0;
        stream_row <= 5'd0;
        stream_block_x <= 4'd0;
        stream_row_mod <= 4'd0;
        block_sum <= 9'd0;
        update_valid_s0 <= 1'b0;
        update_col_s0 <= 5'd0;
        update_add_s0 <= 9'd0;
        update_valid_s1 <= 1'b0;
        update_col_s1 <= 5'd0;
        update_add_s1 <= 9'd0;
    end else begin
        mnist_wr_en <= 1'b0;
        capture_done <= 1'b0;
        capture_error <= 1'b0;
        vsync_d <= vsync;
        href_d <= href;

        if (capture_arm && !capture_busy)
            waiting_for_frame <= 1'b1;

        if (vsync_rise) begin
            x_count <= 12'd0;
            y_count <= 12'd0;
            href_seen_in_frame <= 1'b0;
        end else if (href_rise) begin
            x_count <= 12'd0;
            if (href_seen_in_frame)
                y_count <= y_count + 12'd1;
            else
                href_seen_in_frame <= 1'b1;
        end else if (href && pixel_valid) begin
            x_count <= x_count + 12'd1;
        end

        update_valid_s1 <= update_valid_s0;
        update_col_s1 <= update_col_s0;
        update_add_s1 <= update_add_s0;
        update_valid_s0 <= 1'b0;
        if (update_valid_s1)
            col_sum[update_col_s1] <= update_sum_next;

        case (state)
            S_IDLE: begin
                capture_busy <= 1'b0;
                if (vsync_rise && (waiting_for_frame || capture_arm))
                    start_capture();
            end

            S_CLEAR: begin
                if (vsync_rise) begin
                    fail_capture();
                end else begin
                    col_sum[clear_idx] <= 13'd0;
                    if (clear_idx == (MNIST_SIZE - 1)) begin
                        clear_idx <= 5'd0;
                        state <= S_RUN;
                    end else begin
                        clear_idx <= clear_idx + 5'd1;
                    end
                end
            end

            S_RUN: begin
                if (vsync_rise) begin
                    fail_capture();
                end else begin
                    if (in_roi) begin
                        if (stream_block_x == (BLOCK_SIZE - 1)) begin
                            update_valid_s0 <= 1'b1;
                            update_col_s0 <= stream_col;
                            update_add_s0 <= block_sum_with_pixel;
                            block_sum <= 9'd0;
                            stream_block_x <= 4'd0;
                            if (stream_col != (MNIST_SIZE - 1))
                                stream_col <= stream_col + 5'd1;
                        end else begin
                            block_sum <= block_sum_with_pixel;
                            stream_block_x <= stream_block_x + 4'd1;
                        end
                    end

                    if (roi_row_end) begin
                        stream_col <= 5'd0;
                        stream_block_x <= 4'd0;
                        if (stream_row_mod == (BLOCK_SIZE - 1)) begin
                            wr_col <= 5'd0;
                            wr_row <= stream_row;
                            stream_row <= stream_row + 5'd1;
                            stream_row_mod <= 4'd0;
                            state <= S_FLUSH_ROW;
                        end else begin
                            stream_row_mod <= stream_row_mod + 4'd1;
                        end
                    end
                end
            end

            S_FLUSH_ROW: begin
                if (vsync_rise) begin
                    fail_capture();
                end else if (!update_valid_s0 && !update_valid_s1) begin
                    state <= S_WRITE_ROW;
                end
            end

            S_WRITE_ROW: begin
                if (vsync_rise) begin
                    fail_capture();
                end else begin
                    mnist_wr_en <= 1'b1;
                    mnist_wr_addr <= mnist_wr_addr_next;
                    mnist_wr_data <= {8'd0, mnist_u8};
                    col_sum[wr_col] <= 13'd0;
                    if (wr_col == (MNIST_SIZE - 1)) begin
                        wr_col <= 5'd0;
                        if (wr_row == (MNIST_SIZE - 1)) begin
                            capture_busy <= 1'b0;
                            state <= S_IDLE;
                            capture_done <= 1'b1;
                        end else begin
                            state <= S_RUN;
                        end
                    end else begin
                        wr_col <= wr_col + 5'd1;
                    end
                end
            end

            default: begin
                fail_capture();
            end
        endcase
    end
end

endmodule
