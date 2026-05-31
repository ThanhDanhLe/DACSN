`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// image_processing_vfb_stream.v
//
// Downscale the registered raw VFB pixel stream into the local 28x28 MNIST
// buffer. Final preprocessing uses green-channel average, threshold=100, and
// black-stroke/white-background inversion:
//   mnist = (avg_gray < threshold) ? (255 - avg_gray) : 0
// -----------------------------------------------------------------------------
module image_processing_vfb_stream #(
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
    input  wire        start,

    input  wire        frame_start,
    input  wire        pixel_valid,
    input  wire [11:0] pixel_x,
    input  wire [11:0] pixel_y,
    input  wire [15:0] pixel_rgb565,

    output reg         mnist_wr_en,
    output reg  [9:0]  mnist_wr_addr,
    output reg  [15:0] mnist_wr_data,

    output reg         busy,
    output reg         done,
    output reg         error
);

localparam [3:0]
    S_IDLE       = 4'd0,
    S_WAIT_FRAME = 4'd1,
    S_RUN        = 4'd2,
    S_WRITE_ROW  = 4'd3,
    S_FLUSH_ROW  = 4'd5;

localparam [11:0] ROI_X0_12 = ROI_X0;
localparam [11:0] ROI_Y0_12 = ROI_Y0;
localparam [11:0] ROI_X1_12 = ROI_X0 + ROI_SIZE;
localparam [11:0] ROI_Y1_12 = ROI_Y0 + ROI_SIZE;

reg [12:0] col_sum [0:MNIST_SIZE-1];
reg [4:0]  wr_col;
reg [4:0]  wr_row;
reg [4:0]  stream_col;
reg [4:0]  stream_row;
reg [3:0]  stream_block_x;
reg [3:0]  stream_row_mod;
reg [8:0]  block_sum;
reg [3:0]  state;
reg        update_valid_s0;
reg [4:0]  update_col_s0;
reg [8:0]  update_add_s0;
reg        update_valid_s1;
reg [4:0]  update_col_s1;
reg [8:0]  update_add_s1;
reg [12:0] update_sum_s1;
integer i;

wire in_roi = pixel_valid &&
              (pixel_x >= ROI_X0_12) && (pixel_x < ROI_X1_12) &&
              (pixel_y >= ROI_Y0_12) && (pixel_y < ROI_Y1_12);
wire roi_row_end = pixel_valid &&
                   (pixel_x == ROI_X1_12) &&
                   (pixel_y >= ROI_Y0_12) && (pixel_y < ROI_Y1_12);

wire [9:0] wr_row_mul32 = {wr_row, 5'b00000};
wire [9:0] wr_row_mul4  = {3'b000, wr_row, 2'b00};
wire [9:0] wr_row_base;

leaf_subtractor #(.WIDTH(10)) u_wr_row_base_subtractor (
    .a(wr_row_mul32),
    .b(wr_row_mul4),
    .y(wr_row_base)
);

wire [5:0] pixel_g6 = pixel_rgb565[10:5];
wire [7:0] pixel_gray = {pixel_g6, pixel_g6[5:4]};
wire [7:0] avg_gray_raw = col_sum[wr_col][12:5];
wire [7:0] avg_gray = (avg_gray_raw == 8'd248) ? 8'd255 : avg_gray_raw;
wire [7:0] mnist_inverted;
leaf_subtractor #(.WIDTH(8)) u_mnist_invert_subtractor (
    .a(8'd255),
    .b(avg_gray),
    .y(mnist_inverted)
);
wire [7:0] mnist_u8 = (avg_gray < THRESHOLD) ? mnist_inverted : 8'd0;
wire [4:0] pixel_gray5 = pixel_gray[7:3];
wire [8:0] block_sum_with_pixel;
wire [12:0] update_sum_next;

leaf_adder #(.WIDTH(9)) u_block_sum_adder (
    .a(block_sum),
    .b({4'd0, pixel_gray5}),
    .y(block_sum_with_pixel)
);

leaf_adder #(.WIDTH(13)) u_update_sum_adder (
    .a(update_sum_s1),
    .b({4'd0, update_add_s1}),
    .y(update_sum_next)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mnist_wr_en <= 1'b0;
        mnist_wr_addr <= 10'd0;
        mnist_wr_data <= 16'd0;
        busy <= 1'b0;
        done <= 1'b0;
        error <= 1'b0;
        state <= S_IDLE;
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
        update_sum_s1 <= 13'd0;
        for (i = 0; i < MNIST_SIZE; i = i + 1)
            col_sum[i] <= 13'd0;
    end else begin
        mnist_wr_en <= 1'b0;
        done <= 1'b0;
        update_valid_s1 <= update_valid_s0;
        update_col_s1 <= update_col_s0;
        update_add_s1 <= update_add_s0;
        if (update_valid_s0)
            update_sum_s1 <= col_sum[update_col_s0];
        update_valid_s0 <= 1'b0;
        if (update_valid_s1)
            col_sum[update_col_s1] <= update_sum_next;

        case (state)
            S_IDLE: begin
                busy <= 1'b0;
                if (start) begin
                    busy <= 1'b1;
                    error <= 1'b0;
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
                    update_sum_s1 <= 13'd0;
                    for (i = 0; i < MNIST_SIZE; i = i + 1)
                        col_sum[i] <= 13'd0;
                    state <= S_WAIT_FRAME;
                end
            end

            S_WAIT_FRAME: begin
                if (frame_start)
                    state <= S_RUN;
            end

            S_RUN: begin
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

            S_FLUSH_ROW: begin
                if (!update_valid_s0 && !update_valid_s1)
                    state <= S_WRITE_ROW;
            end

            S_WRITE_ROW: begin
                mnist_wr_en <= 1'b1;
                mnist_wr_addr <= wr_row_base + {5'b00000, wr_col};
                mnist_wr_data <= {8'd0, mnist_u8};
                col_sum[wr_col] <= 13'd0;
                if (wr_col == (MNIST_SIZE - 1)) begin
                    wr_col <= 5'd0;
                    if (wr_row == (MNIST_SIZE - 1)) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        state <= S_RUN;
                    end
                end else begin
                    wr_col <= wr_col + 5'd1;
                end
            end

            default: begin
                busy <= 1'b0;
                error <= 1'b1;
                state <= S_IDLE;
            end
        endcase
    end
end

endmodule
