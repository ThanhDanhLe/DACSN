`timescale 1ns/1ps

module camera_live_top #(
    parameter SIMULATION = 0,
    parameter H_RES = 800,
    parameter V_RES = 600,
    parameter ROI_X0 = 176,
    parameter ROI_Y0 = 76,
    parameter ROI_SIZE = 448,
    parameter DEBUG_DUMP_ENABLE = 0,
    parameter UART_TEST_MODE = 0
)(
    input             I_clk,
    input             I_rst_n,
    input             KEY_STEP_N,

    inout             SDA,
    inout             SCL,
    input             VSYNC,
    input             HREF,
    input      [9:2]  PIXDATA,
    input             PIXCLK,
    output            XCLK,

    output            FLASH_CS_N,
    output            FLASH_SCLK,
    output            FLASH_MOSI,
    input             FLASH_MISO,

    output     [0:0]  O_hpram_ck,
    output     [0:0]  O_hpram_ck_n,
    output     [0:0]  O_hpram_cs_n,
    output     [0:0]  O_hpram_reset_n,
    inout      [7:0]  IO_hpram_dq,
    inout      [0:0]  IO_hpram_rwds,

    output            O_tmds_clk_p,
    output            O_tmds_clk_n,
    output     [2:0]  O_tmds_data_p,
    output     [2:0]  O_tmds_data_n
);

localparam [2:0] SEL_NONE = 3'd0;
localparam [3:0] S_FREEZE_FRAME = 4'd2;
localparam integer KEY_DEBOUNCE_TICKS = (SIMULATION != 0) ? 4 : 524288;
localparam integer KEY_CNT_WIDTH = 20;
localparam [7:0] FREEZE_SETTLE_TICKS = (SIMULATION != 0) ? 8'd8 : 8'd64;

wire pix_clk;
wire pix_rst_n;
wire calib_done;
wire calib_done_i;
wire [2:0] hyperram_current_owner;
wire [2:0] hyperram_owner_request;
wire vfb_halt_active;
wire i_rst_n_sync;
wire image_start_i;
wire image_start_pix;
wire image_done_pix;
wire image_error_pix;
wire image_done_i;
wire image_error_i;
wire proc_wr_en;
wire [9:0] proc_wr_addr;
wire [15:0] proc_wr_data;
wire stream_rd_en;
wire [9:0] stream_rd_addr;
wire [15:0] stream_rd_data;
wire nn_image_rd_en;
wire [9:0] nn_image_rd_addr;
wire [15:0] nn_image_rd_data;
wire nn_busy;
wire nn_done;
wire nn_output_valid;
wire [3:0] nn_output_class;
wire nn_error;
wire nn_start;
wire image_preload_valid;
wire result_valid_latched;
wire [3:0] result_class_latched;
wire result_error_latched;
wire integration_busy_i;
wire freeze_active_i;
wire image_process_active_i;
wire show_mnist_i;
reg  [1:0] show_mnist_pix_sync;
wire show_mnist_pix;
wire [11:0] hdmi_x;
wire [11:0] hdmi_y;
wire hdmi_de;
wire hdmi_frame_start;
wire video_pixel_valid;
wire [11:0] video_pixel_x;
wire [11:0] video_pixel_y;
wire [15:0] video_rgb565;
wire mnist_display_rd_en_i;
wire [9:0] mnist_display_rd_addr_i;
wire mnist28_rd_en_pix;
wire [9:0] mnist28_rd_addr_pix;
wire [4:0] mnist28_rd_x_pix;
wire [4:0] mnist28_rd_y_pix;
wire [15:0] mnist28_rd_data_pix;
wire [7:0] mnist28_r;
wire [7:0] mnist28_g;
wire [7:0] mnist28_b;
wire [15:0] mnist28_rgb565;
wire [3:0] flow_state;

reg [2:0] calib_sync_i;
reg [2:0] vfb_halt_sync_i;
reg [2:0] owner_none_sync_i;
reg [7:0] freeze_count;

assign show_mnist_pix = show_mnist_pix_sync[1];
assign mnist28_rgb565 = {mnist28_r[7:3], mnist28_g[7:2], mnist28_b[7:3]};
assign calib_done_i = calib_sync_i[2];

// Preview read path must cross from HDMI pix_clk to the CNN/image I_clk domain
// through an explicit request/ack bridge.  Do not connect mnist28_rd_addr_pix
// directly into the I_clk RAM read port: that creates a multi-bit CDC path and
// produces vertical stripes / speckled pixels on hardware.
assign stream_rd_en   = mnist_display_rd_en_i;
assign stream_rd_addr = mnist_display_rd_addr_i;

wire freeze_ready_i = vfb_halt_sync_i[2] && owner_none_sync_i[2];
wire freeze_done_i = (flow_state == S_FREEZE_FRAME) &&
                     (freeze_count >= FREEZE_SETTLE_TICKS);

reset_sync u_top_i_reset_sync (
    .clk(I_clk),
    .arst_n(I_rst_n),
    .srst_n(i_rst_n_sync)
);

always @(posedge I_clk or negedge i_rst_n_sync) begin
    if (!i_rst_n_sync) begin
        calib_sync_i <= 3'b000;
        vfb_halt_sync_i <= 3'b000;
        owner_none_sync_i <= 3'b000;
        freeze_count <= 8'd0;
    end else begin
        calib_sync_i <= {calib_sync_i[1:0], calib_done};
        vfb_halt_sync_i <= {vfb_halt_sync_i[1:0], vfb_halt_active};
        owner_none_sync_i <= {owner_none_sync_i[1:0],
                              (hyperram_current_owner == SEL_NONE)};

        if (!freeze_active_i || !freeze_ready_i) begin
            freeze_count <= 8'd0;
        end else if (freeze_count != 8'hFF) begin
            freeze_count <= freeze_count + 8'd1;
        end
    end
end

camera_live_flow_control #(
    .KEY_DEBOUNCE_TICKS(KEY_DEBOUNCE_TICKS),
    .KEY_CNT_WIDTH(KEY_CNT_WIDTH)
) u_flow_control (
    .clk(I_clk),
    .rst_n(i_rst_n_sync),
    .key_step_n(KEY_STEP_N),
    .calib_done(calib_done_i),
    .freeze_done(freeze_done_i),
    .image_done(image_done_i),
    .image_error(image_error_i),
    .nn_busy(nn_busy),
    .nn_output_valid(nn_output_valid),
    .nn_output_class(nn_output_class),
    .nn_error(nn_error),
    .image_start(image_start_i),
    .nn_start(nn_start),
    .show_mnist(show_mnist_i),
    .freeze_active(freeze_active_i),
    .image_process_active(image_process_active_i),
    .integration_busy(integration_busy_i),
    .hyperram_owner_request(hyperram_owner_request),
    .image_preload_valid(image_preload_valid),
    .result_valid(result_valid_latched),
    .result_class(result_class_latched),
    .result_error(result_error_latched),
    .state(flow_state),
    .dbg_key_pressed_pulse(),
    .dbg_key_wait_release(),
    .dbg_state(),
    .dbg_transition_count()
);

cdc_pulse_sync u_image_start_sync (
    .src_clk(I_clk),
    .src_rst_n(i_rst_n_sync),
    .src_pulse(image_start_i),
    .dst_clk(pix_clk),
    .dst_rst_n(pix_rst_n),
    .dst_pulse(image_start_pix)
);

cdc_pulse_sync u_image_done_sync (
    .src_clk(pix_clk),
    .src_rst_n(pix_rst_n),
    .src_pulse(image_done_pix),
    .dst_clk(I_clk),
    .dst_rst_n(i_rst_n_sync),
    .dst_pulse(image_done_i)
);

cdc_pulse_sync u_image_error_sync (
    .src_clk(pix_clk),
    .src_rst_n(pix_rst_n),
    .src_pulse(image_error_pix),
    .dst_clk(I_clk),
    .dst_rst_n(i_rst_n_sync),
    .dst_pulse(image_error_i)
);

always @(posedge pix_clk or negedge pix_rst_n) begin
    if (!pix_rst_n)
        show_mnist_pix_sync <= 2'b00;
    else
        show_mnist_pix_sync <= {show_mnist_pix_sync[0], show_mnist_i};
end

streaming_mnist_capture #(
    .H_RES(H_RES),
    .V_RES(V_RES),
    .ROI_X0(ROI_X0),
    .ROI_Y0(ROI_Y0),
    .ROI_SIZE(ROI_SIZE),
    .BLOCK_SIZE(16),
    .MNIST_SIZE(28),
    .THRESHOLD(8'd100)
) u_vfb_mnist_capture (
    .clk(pix_clk),
    .rst_n(pix_rst_n),
    .capture_arm(image_start_pix),
    .vsync(hdmi_frame_start),
    .href(video_pixel_valid),
    .pixel_valid(video_pixel_valid),
    .rgb565(video_rgb565),
    .mnist_wr_en(proc_wr_en),
    .mnist_wr_addr(proc_wr_addr),
    .mnist_wr_data(proc_wr_data),
    .capture_busy(),
    .capture_done(image_done_pix),
    .capture_error(image_error_pix),
    .waiting_for_frame(),
    .x_count(),
    .y_count(),
    .roi_pixel_count(),
    .mnist_write_count()
);

mnist_image_buffer_dualclk u_mnist_cnn_buffer (
    .wr_clk(pix_clk),
    .wr_rst_n(pix_rst_n),
    .wr_en(proc_wr_en),
    .wr_addr(proc_wr_addr),
    .wr_data(proc_wr_data),
    .rd_clk(I_clk),
    .rd_rst_n(i_rst_n_sync),
    .rd0_en(stream_rd_en),
    .rd0_addr(stream_rd_addr),
    .rd0_data(stream_rd_data),
    .rd1_en(nn_image_rd_en),
    .rd1_addr(nn_image_rd_addr),
    .rd1_data(nn_image_rd_data)
);

mnist28_row_cache_bridge #(
    .ROI_X0(ROI_X0),
    .ROI_Y0(ROI_Y0),
    .SCALE_LOG2(4),
    .MNIST_SIZE(28)
) u_mnist28_row_cache_bridge (
    .i_clk(I_clk),
    .i_rst_n(i_rst_n_sync),
    .pix_clk(pix_clk),
    .pix_rst_n(pix_rst_n),
    .enable_i(show_mnist_i && !nn_busy),
    .enable_pix(show_mnist_pix),
    .video_x(hdmi_x),
    .video_y(hdmi_y),
    .active_video(hdmi_de),
    .mnist_rd_en_i(mnist_display_rd_en_i),
    .mnist_rd_addr_i(mnist_display_rd_addr_i),
    .mnist_rd_data_i(stream_rd_data),
    .renderer_rd_en(mnist28_rd_en_pix),
    .renderer_rd_x(mnist28_rd_x_pix),
    .renderer_rd_y(mnist28_rd_y_pix),
    .renderer_rd_data(mnist28_rd_data_pix)
);

mnist28_upscale_renderer #(
    .H_RES(H_RES),
    .V_RES(V_RES),
    .ROI_X0(ROI_X0),
    .ROI_Y0(ROI_Y0),
    .SCALE_LOG2(4),
    .MNIST_SIZE(28),
    .LOOKAHEAD(0),
    .OUTPUT_ADDR(0)
) u_mnist28_upscale_renderer (
    .pix_clk(pix_clk),
    .rst_n(pix_rst_n),
    .enable(show_mnist_pix),
    .video_x(hdmi_x),
    .video_y(hdmi_y),
    .active_video(hdmi_de),
    .mnist_rd_en(mnist28_rd_en_pix),
    .mnist_rd_addr(mnist28_rd_addr_pix),
    .mnist_rd_x(mnist28_rd_x_pix),
    .mnist_rd_y(mnist28_rd_y_pix),
    .mnist_rd_data(mnist28_rd_data_pix),
    .out_r(mnist28_r),
    .out_g(mnist28_g),
    .out_b(mnist28_b),
    .out_valid()
);

cnn_system #(
    .ACT_ADDR_WIDTH(9),
    .SPI_DIV(1),
    .FLASH_PARAM_BASE(24'h200000)
) u_cnn_system (
    .clk(I_clk),
    .rst_n(i_rst_n_sync),
    .start(nn_start),
    .memory_ready(1'b1),
    .image_rd_en(nn_image_rd_en),
    .image_rd_addr(nn_image_rd_addr),
    .image_rd_data(nn_image_rd_data),
    .image_preload_valid(image_preload_valid),
    .image_preload_wr_en(1'b0),
    .image_preload_wr_addr(9'd0),
    .image_preload_wr_data(32'd0),
    .flash_cs_n(FLASH_CS_N),
    .flash_sclk(FLASH_SCLK),
    .flash_mosi(FLASH_MOSI),
    .flash_miso(FLASH_MISO),
    .busy(nn_busy),
    .done(nn_done),
    .output_valid(nn_output_valid),
    .output_class(nn_output_class),
    .error(nn_error)
);

camera_video #(
    .SIMULATION(SIMULATION),
    .H_RES(H_RES),
    .V_RES(V_RES),
    .ROI_X0(ROI_X0),
    .ROI_Y0(ROI_Y0),
    .ROI_SIZE(ROI_SIZE)
) u_camera_video (
    .I_clk(I_clk),
    .I_rst_n(I_rst_n),
    .O_led(),
    .SDA(SDA),
    .SCL(SCL),
    .VSYNC(VSYNC),
    .HREF(HREF),
    .PIXDATA(PIXDATA),
    .PIXCLK(PIXCLK),
    .XCLK(XCLK),
    .O_hpram_ck(O_hpram_ck),
    .O_hpram_ck_n(O_hpram_ck_n),
    .O_hpram_cs_n(O_hpram_cs_n),
    .O_hpram_reset_n(O_hpram_reset_n),
    .IO_hpram_dq(IO_hpram_dq),
    .IO_hpram_rwds(IO_hpram_rwds),
    .O_tmds_clk_p(O_tmds_clk_p),
    .O_tmds_clk_n(O_tmds_clk_n),
    .O_tmds_data_p(O_tmds_data_p),
    .O_tmds_data_n(O_tmds_data_n),
    .show_processed(show_mnist_pix),
    .processed_rgb565(mnist28_rgb565),
    .result_valid(result_valid_latched),
    .result_class(result_class_latched),
    .result_busy(integration_busy_i),
    .result_error(result_error_latched),
    .hyperram_owner_request(hyperram_owner_request),
    .img_hram_cmd(1'b0),
    .img_hram_cmd_en(1'b0),
    .img_hram_addr(22'd0),
    .img_hram_wr_data(32'd0),
    .img_hram_data_mask(4'hF),
    .img_mem_active(1'b0),
    .img_hram_rd_data(),
    .img_hram_rd_data_valid(),
    .img_mem_grant(),
    .pix_clk(pix_clk),
    .pix_rst_n(pix_rst_n),
    .hyperram_clk(),
    .hyperram_rst_n(),
    .calib_done(calib_done),
    .hyperram_current_owner(hyperram_current_owner),
    .hyperram_owner_state(),
    .vfb_halt_active(vfb_halt_active),
    .hdmi_x(hdmi_x),
    .hdmi_y(hdmi_y),
    .hdmi_de(hdmi_de),
    .hdmi_frame_start(hdmi_frame_start),
    .video_pixel_valid(video_pixel_valid),
    .video_pixel_x(video_pixel_x),
    .video_pixel_y(video_pixel_y),
    .video_rgb565(video_rgb565)
);


endmodule
