`timescale 1ns/1ps

module mnist_roi_renderer #(
    parameter ROI_X0 = 176,
    parameter ROI_Y0 = 76,
    parameter SCALE_LOG2 = 4,
    parameter MNIST_SIZE = 28
)(
    input  wire        i_clk,
    input  wire        i_rst_n,
    input  wire        pix_clk,
    input  wire        pix_rst_n,

    input  wire        enable_i,
    input  wire        enable_pix,
    input  wire [11:0] video_x,
    input  wire [11:0] video_y,
    input  wire        active_video,

    output reg         mnist_rd_en_i,
    output reg  [9:0]  mnist_rd_addr_i,
    input  wire [15:0] mnist_rd_data_i,

    output reg  [15:0] rgb565,
    output reg         out_valid,
    output wire        roi_active_debug
);

localparam [1:0]
    I_IDLE  = 2'd0,
    I_REQ   = 2'd1,
    I_WAIT  = 2'd2,
    I_STORE = 2'd3;

localparam [11:0] ROI_X0_12 = ROI_X0;
localparam [11:0] ROI_Y0_12 = ROI_Y0;
localparam [11:0] ROI_SIZE_12 = MNIST_SIZE << SCALE_LOG2;
localparam [11:0] ROI_X1_12 = ROI_X0 + ROI_SIZE_12;
localparam [11:0] ROI_Y1_12 = ROI_Y0 + ROI_SIZE_12;

reg        req_toggle_pix;
reg        req_pending_pix;
reg [4:0]  req_row_pix;
reg        row_valid_pix;
reg [4:0]  cached_row_pix;
reg [2:0]  done_toggle_sync_pix;
reg        done_toggle_seen_pix;
reg [7:0]  row_cache_pix [0:MNIST_SIZE-1];

reg [1:0]  i_state;
reg [2:0]  req_toggle_sync_i;
reg        req_toggle_seen_i;
reg [4:0]  i_row;
reg [4:0]  i_col;
reg        done_toggle_i;
reg [4:0]  done_row_i;
reg [7:0]  row_cache_i [0:MNIST_SIZE-1];

wire req_event_i = req_toggle_sync_i[2] ^ req_toggle_seen_i;
wire done_event_pix = done_toggle_sync_pix[2] ^ done_toggle_seen_pix;

wire pix_x_in_roi = (video_x >= ROI_X0_12) && (video_x < ROI_X1_12);
wire pix_y_in_roi = (video_y >= ROI_Y0_12) && (video_y < ROI_Y1_12);
wire in_roi_now = enable_pix && active_video && pix_x_in_roi && pix_y_in_roi;
wire [11:0] pix_dx = video_x - ROI_X0_12;
wire [11:0] pix_dy = video_y - ROI_Y0_12;
wire [4:0]  mnist_x_now = pix_dx[SCALE_LOG2 + 4:SCALE_LOG2];
wire [4:0]  mnist_y_now = pix_dy[SCALE_LOG2 + 4:SCALE_LOG2];
wire        row_ready_now = row_valid_pix && (cached_row_pix == mnist_y_now);
wire [7:0]  gray_now = (in_roi_now && row_ready_now) ?
                       row_cache_pix[mnist_x_now] : 8'd0;

wire line_start_pix = enable_pix && active_video && (video_x == 12'd0);
wire row_block_start_pix = pix_y_in_roi && (pix_dy[SCALE_LOG2-1:0] == {SCALE_LOG2{1'b0}});
wire request_row_pix = line_start_pix && row_block_start_pix &&
                       !req_pending_pix &&
                       (!row_valid_pix || (cached_row_pix != mnist_y_now));

wire [9:0] i_row_mul32 = {i_row, 5'b00000};
wire [9:0] i_row_mul4  = {3'b000, i_row, 2'b00};
wire [9:0] i_row_base  = i_row_mul32 - i_row_mul4;
wire [9:0] i_col_ext   = {5'b00000, i_col};

integer pix_idx;
integer i_idx;

assign roi_active_debug = in_roi_now;

always @(posedge pix_clk or negedge pix_rst_n) begin
    if (!pix_rst_n) begin
        req_toggle_pix <= 1'b0;
        req_pending_pix <= 1'b0;
        req_row_pix <= 5'd0;
        row_valid_pix <= 1'b0;
        cached_row_pix <= 5'd0;
        done_toggle_sync_pix <= 3'b000;
        done_toggle_seen_pix <= 1'b0;
        rgb565 <= 16'd0;
        out_valid <= 1'b0;
        for (pix_idx = 0; pix_idx < MNIST_SIZE; pix_idx = pix_idx + 1)
            row_cache_pix[pix_idx] <= 8'd0;
    end else begin
        done_toggle_sync_pix <= {done_toggle_sync_pix[1:0], done_toggle_i};

        if (!enable_pix) begin
            req_pending_pix <= 1'b0;
            row_valid_pix <= 1'b0;
            done_toggle_seen_pix <= done_toggle_sync_pix[2];
        end else begin
            if (done_event_pix) begin
                done_toggle_seen_pix <= done_toggle_sync_pix[2];
                req_pending_pix <= 1'b0;
                row_valid_pix <= 1'b1;
                cached_row_pix <= done_row_i;
                for (pix_idx = 0; pix_idx < MNIST_SIZE; pix_idx = pix_idx + 1)
                    row_cache_pix[pix_idx] <= row_cache_i[pix_idx];
            end

            if (request_row_pix) begin
                req_row_pix <= mnist_y_now;
                req_pending_pix <= 1'b1;
                req_toggle_pix <= ~req_toggle_pix;
            end
        end

        out_valid <= in_roi_now && row_ready_now;
        rgb565 <= {gray_now[7:3], gray_now[7:2], gray_now[7:3]};
    end
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        i_state <= I_IDLE;
        req_toggle_sync_i <= 3'b000;
        req_toggle_seen_i <= 1'b0;
        i_row <= 5'd0;
        i_col <= 5'd0;
        done_toggle_i <= 1'b0;
        done_row_i <= 5'd0;
        mnist_rd_en_i <= 1'b0;
        mnist_rd_addr_i <= 10'd0;
        for (i_idx = 0; i_idx < MNIST_SIZE; i_idx = i_idx + 1)
            row_cache_i[i_idx] <= 8'd0;
    end else begin
        req_toggle_sync_i <= {req_toggle_sync_i[1:0], req_toggle_pix};
        mnist_rd_en_i <= 1'b0;

        if (!enable_i) begin
            i_state <= I_IDLE;
            req_toggle_seen_i <= req_toggle_sync_i[2];
            i_col <= 5'd0;
        end else begin
            case (i_state)
                I_IDLE: begin
                    if (req_event_i) begin
                        req_toggle_seen_i <= req_toggle_sync_i[2];
                        i_row <= req_row_pix;
                        i_col <= 5'd0;
                        i_state <= I_REQ;
                    end
                end

                I_REQ: begin
                    mnist_rd_en_i <= 1'b1;
                    mnist_rd_addr_i <= i_row_base + i_col_ext;
                    i_state <= I_WAIT;
                end

                I_WAIT: begin
                    i_state <= I_STORE;
                end

                I_STORE: begin
                    row_cache_i[i_col] <= mnist_rd_data_i[7:0];
                    if (i_col == (MNIST_SIZE - 1)) begin
                        done_row_i <= i_row;
                        done_toggle_i <= ~done_toggle_i;
                        i_state <= I_IDLE;
                    end else begin
                        i_col <= i_col + 5'd1;
                        i_state <= I_REQ;
                    end
                end

                default: begin
                    i_state <= I_IDLE;
                end
            endcase
        end
    end
end

endmodule
