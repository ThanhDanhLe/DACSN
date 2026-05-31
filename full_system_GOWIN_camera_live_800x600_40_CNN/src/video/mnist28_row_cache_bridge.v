`timescale 1ns/1ps

module mnist28_row_cache_bridge #(
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
    output wire [9:0]  mnist_rd_addr_i,
    input  wire [15:0] mnist_rd_data_i,

    input  wire        renderer_rd_en,
    input  wire [4:0]  renderer_rd_x,
    input  wire [4:0]  renderer_rd_y,
    output reg  [15:0] renderer_rd_data
);

localparam [1:0]
    I_IDLE    = 2'd0,
    I_RD_REQ  = 2'd1,
    I_RD_WAIT = 2'd2,
    I_DONE    = 2'd3;

localparam [11:0] ROI_X0_12 = ROI_X0;
localparam [11:0] ROI_Y0_12 = ROI_Y0;
localparam [11:0] ROI_SIZE_12 = MNIST_SIZE << SCALE_LOG2;
localparam [11:0] ROI_Y1_12 = ROI_Y0 + ROI_SIZE_12;

reg        req_toggle_pix /* synthesis syn_keep=1 */;
reg        req_pending_pix;
reg [4:0]  req_x_pix /* synthesis syn_keep=1 */;
reg [4:0]  req_y_pix /* synthesis syn_keep=1 */;
reg        req_replace_slot_pix /* synthesis syn_keep=1 */;

reg        cache0_valid_pix;
reg [4:0]  cache0_x_pix;
reg [4:0]  cache0_y_pix;
reg [7:0]  cache0_data_pix;
reg        cache1_valid_pix;
reg [4:0]  cache1_x_pix;
reg [4:0]  cache1_y_pix;
reg [7:0]  cache1_data_pix;
reg [2:0]  done_toggle_sync_pix;
reg        done_toggle_seen_pix;

reg [1:0]  i_state;
reg [2:0]  req_toggle_sync_i;
reg        req_toggle_seen_i;
reg [4:0]  i_req_x;
reg [4:0]  i_req_y;
reg        done_toggle_i /* synthesis syn_keep=1 */;
reg [7:0]  done_data_i /* synthesis syn_keep=1 */;

wire req_event_i = req_toggle_sync_i[2] ^ req_toggle_seen_i;
wire done_event_pix = done_toggle_sync_pix[2] ^ done_toggle_seen_pix;

wire hit0_pix = cache0_valid_pix &&
                (cache0_x_pix == renderer_rd_x) &&
                (cache0_y_pix == renderer_rd_y);
wire hit1_pix = cache1_valid_pix &&
                (cache1_x_pix == renderer_rd_x) &&
                (cache1_y_pix == renderer_rd_y);
wire current_hit_pix = hit0_pix || hit1_pix;

wire [11:0] roi_dy = video_y - ROI_Y0_12;
wire [4:0]  line_prefetch_y = roi_dy[SCALE_LOG2 + 4:SCALE_LOG2];
wire        line_prefetch_valid = enable_pix && active_video &&
                                  (video_x == 12'd0) &&
                                  (video_y >= ROI_Y0_12) &&
                                  (video_y < ROI_Y1_12);
wire        line_hit_pix =
    (cache0_valid_pix && (cache0_x_pix == 5'd0) &&
     (cache0_y_pix == line_prefetch_y)) ||
    (cache1_valid_pix && (cache1_x_pix == 5'd0) &&
     (cache1_y_pix == line_prefetch_y));
wire        line_request_pix = line_prefetch_valid && !line_hit_pix;
wire        next_x_valid = renderer_rd_en && current_hit_pix &&
                           (renderer_rd_x != (MNIST_SIZE - 1));
wire        stream_target_valid_pix = enable_pix && active_video &&
                                      renderer_rd_en &&
                                      (!current_hit_pix || next_x_valid);
wire [4:0]  stream_target_x_pix = !current_hit_pix ? renderer_rd_x :
                                  next_x_valid     ? (renderer_rd_x + 5'd1) :
                                                     5'd0;
wire [4:0]  stream_target_y_pix = renderer_rd_y;
wire        stream_target_hit_pix =
    (cache0_valid_pix && (cache0_x_pix == stream_target_x_pix) &&
     (cache0_y_pix == stream_target_y_pix)) ||
    (cache1_valid_pix && (cache1_x_pix == stream_target_x_pix) &&
     (cache1_y_pix == stream_target_y_pix));
wire        line_request_new_pix = line_request_pix && !req_pending_pix;
wire        stream_request_new_pix = stream_target_valid_pix &&
                                     !stream_target_hit_pix &&
                                     !req_pending_pix &&
                                     !line_request_pix;

leaf_addr_28_mul_shiftadd u_i_addr_28 (
    .y(i_req_y),
    .x(i_req_x),
    .addr(mnist_rd_addr_i)
);

always @(posedge pix_clk or negedge pix_rst_n) begin
    if (!pix_rst_n) begin
        req_toggle_pix <= 1'b0;
        req_pending_pix <= 1'b0;
        req_x_pix <= 5'd0;
        req_y_pix <= 5'd0;
        req_replace_slot_pix <= 1'b0;
        cache0_valid_pix <= 1'b0;
        cache0_x_pix <= 5'd0;
        cache0_y_pix <= 5'd0;
        cache0_data_pix <= 8'd0;
        cache1_valid_pix <= 1'b0;
        cache1_x_pix <= 5'd0;
        cache1_y_pix <= 5'd0;
        cache1_data_pix <= 8'd0;
        done_toggle_sync_pix <= 3'b000;
        done_toggle_seen_pix <= 1'b0;
        renderer_rd_data <= 16'd0;
    end else begin
        done_toggle_sync_pix <= {done_toggle_sync_pix[1:0], done_toggle_i};

        if (!enable_pix) begin
            req_pending_pix <= 1'b0;
            cache0_valid_pix <= 1'b0;
            cache1_valid_pix <= 1'b0;
            done_toggle_seen_pix <= done_toggle_sync_pix[2];
            renderer_rd_data <= 16'd0;
        end else begin
            if (done_event_pix) begin
                done_toggle_seen_pix <= done_toggle_sync_pix[2];
                req_pending_pix <= 1'b0;
                if (req_replace_slot_pix) begin
                    cache1_valid_pix <= 1'b1;
                    cache1_x_pix <= req_x_pix;
                    cache1_y_pix <= req_y_pix;
                    cache1_data_pix <= done_data_i;
                end else begin
                    cache0_valid_pix <= 1'b1;
                    cache0_x_pix <= req_x_pix;
                    cache0_y_pix <= req_y_pix;
                    cache0_data_pix <= done_data_i;
                end
            end

            if (line_request_new_pix) begin
                req_x_pix <= 5'd0;
                req_y_pix <= line_prefetch_y;
                req_replace_slot_pix <= 1'b0;
                req_pending_pix <= 1'b1;
                req_toggle_pix <= ~req_toggle_pix;
            end else if (stream_request_new_pix) begin
                req_x_pix <= stream_target_x_pix;
                req_y_pix <= stream_target_y_pix;
                req_replace_slot_pix <= hit0_pix;
                req_pending_pix <= 1'b1;
                req_toggle_pix <= ~req_toggle_pix;
            end

            if (renderer_rd_en && hit0_pix)
                renderer_rd_data <= {8'd0, cache0_data_pix};
            else if (renderer_rd_en && hit1_pix)
                renderer_rd_data <= {8'd0, cache1_data_pix};
            else
                renderer_rd_data <= 16'd0;
        end
    end
end

always @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        i_state <= I_IDLE;
        req_toggle_sync_i <= 3'b000;
        req_toggle_seen_i <= 1'b0;
        i_req_x <= 5'd0;
        i_req_y <= 5'd0;
        done_toggle_i <= 1'b0;
        done_data_i <= 8'd0;
        mnist_rd_en_i <= 1'b0;
    end else begin
        req_toggle_sync_i <= {req_toggle_sync_i[1:0], req_toggle_pix};
        mnist_rd_en_i <= 1'b0;

        if (!enable_i) begin
            i_state <= I_IDLE;
            req_toggle_seen_i <= req_toggle_sync_i[2];
        end else begin
            case (i_state)
                I_IDLE: begin
                    if (req_event_i) begin
                        req_toggle_seen_i <= req_toggle_sync_i[2];
                        i_req_x <= req_x_pix;
                        i_req_y <= req_y_pix;
                        i_state <= I_RD_REQ;
                    end
                end

                I_RD_REQ: begin
                    mnist_rd_en_i <= 1'b1;
                    i_state <= I_RD_WAIT;
                end

                I_RD_WAIT: begin
                    i_state <= I_DONE;
                end

                I_DONE: begin
                    done_data_i <= mnist_rd_data_i[7:0];
                    done_toggle_i <= ~done_toggle_i;
                    i_state <= I_IDLE;
                end

                default: begin
                    i_state <= I_IDLE;
                end
            endcase
        end
    end
end

wire scale_unused = ^SCALE_LOG2;

endmodule
