`timescale 1ns/1ps

module camera_live_top #(
    parameter SIMULATION = 0,
    parameter H_RES = 800,
    parameter V_RES = 600,
    parameter ROI_X0 = 176,
    parameter ROI_Y0 = 76,
    parameter ROI_SIZE = 448,
    parameter DEBUG_DUMP_ENABLE = 1
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

localparam [2:0] SEL_VFB = 3'd2;

wire pix_clk;
wire pix_rst_n;
wire calib_done;
wire [2:0] hyperram_current_owner;
wire i_rst_n_sync;
wire cam_pix_rst_n;
wire capture_arm_pix;
wire capture_done_pix;
wire capture_error_pix;
wire capture_done_i;
wire capture_error_i;
wire stream_pixel_valid;
wire [15:0] stream_rgb565;
wire stream_wr_en;
wire [9:0] stream_wr_addr;
wire [15:0] stream_wr_data;
wire [15:0] stream_rd_data;
wire       stream_rd_en;
wire [9:0] stream_rd_addr;
wire       debug_uart_tx;
wire       debug_dump_busy;
wire       debug_dump_done;
wire       nn_flash_cs_n;
wire       nn_flash_sclk;
wire       nn_flash_mosi;
wire       nn_busy;
wire       nn_done;
wire       nn_output_valid;
wire [3:0] nn_output_class;
wire       nn_error;
reg  [2:0] key_sync;
reg        key_pressed_d;
reg        capture_done_latched;
reg        capture_error_latched;

assign FLASH_CS_N = 1'b1;
assign FLASH_SCLK = debug_dump_busy ^ nn_flash_sclk ^ nn_busy ^ nn_done ^ nn_output_valid ^ nn_error;
assign FLASH_MOSI = debug_uart_tx ^ nn_flash_mosi ^ (^nn_output_class);

reset_sync u_top_i_reset_sync (
    .clk(I_clk),
    .arst_n(I_rst_n),
    .srst_n(i_rst_n_sync)
);

reset_sync u_cam_pix_reset_sync (
    .clk(PIXCLK),
    .arst_n(I_rst_n),
    .srst_n(cam_pix_rst_n)
);

always @(posedge I_clk or negedge i_rst_n_sync) begin
    if (!i_rst_n_sync) begin
        key_sync <= 3'b000;
        key_pressed_d <= 1'b0;
    end else begin
        key_sync <= {key_sync[1:0], ~KEY_STEP_N};
        key_pressed_d <= key_sync[2];
    end
end

wire capture_arm_i = key_sync[2] & ~key_pressed_d & ~debug_dump_busy;

cdc_pulse_sync u_capture_arm_sync (
    .src_clk(I_clk),
    .src_rst_n(i_rst_n_sync),
    .src_pulse(capture_arm_i),
    .dst_clk(PIXCLK),
    .dst_rst_n(cam_pix_rst_n),
    .dst_pulse(capture_arm_pix)
);

cdc_pulse_sync u_capture_done_sync (
    .src_clk(PIXCLK),
    .src_rst_n(cam_pix_rst_n),
    .src_pulse(capture_done_pix),
    .dst_clk(I_clk),
    .dst_rst_n(i_rst_n_sync),
    .dst_pulse(capture_done_i)
);

cdc_pulse_sync u_capture_error_sync (
    .src_clk(PIXCLK),
    .src_rst_n(cam_pix_rst_n),
    .src_pulse(capture_error_pix),
    .dst_clk(I_clk),
    .dst_rst_n(i_rst_n_sync),
    .dst_pulse(capture_error_i)
);

camera_byte_packer u_stream_camera_byte_packer (
    .clk(PIXCLK),
    .rst_n(cam_pix_rst_n),
    .href(HREF),
    .pixdata(PIXDATA),
    .pixel_rgb565(stream_rgb565),
    .pixel_valid(stream_pixel_valid)
);

streaming_mnist_capture #(
    .H_RES(H_RES),
    .V_RES(V_RES),
    .ROI_X0(ROI_X0),
    .ROI_Y0(ROI_Y0),
    .ROI_SIZE(ROI_SIZE),
    .BLOCK_SIZE(16),
    .MNIST_SIZE(28),
    .THRESHOLD(8'd100)
) u_streaming_mnist_capture (
    .clk(PIXCLK),
    .rst_n(cam_pix_rst_n),
    .capture_arm(capture_arm_pix),
    .vsync(VSYNC),
    .href(HREF),
    .pixel_valid(stream_pixel_valid),
    .rgb565(stream_rgb565),
    .mnist_wr_en(stream_wr_en),
    .mnist_wr_addr(stream_wr_addr),
    .mnist_wr_data(stream_wr_data),
    .capture_busy(),
    .capture_done(capture_done_pix),
    .capture_error(capture_error_pix),
    .waiting_for_frame(),
    .x_count(),
    .y_count(),
    .roi_pixel_count(),
    .mnist_write_count()
);

mnist_image_buffer_dualclk u_stream_mnist_buffer (
    .wr_clk(PIXCLK),
    .wr_rst_n(cam_pix_rst_n),
    .wr_en(stream_wr_en),
    .wr_addr(stream_wr_addr),
    .wr_data(stream_wr_data),
    .rd_clk(I_clk),
    .rd_rst_n(i_rst_n_sync),
    .rd0_en(stream_rd_en),
    .rd0_addr(stream_rd_addr),
    .rd0_data(stream_rd_data),
    .rd1_en(1'b0),
    .rd1_addr(10'd0),
    .rd1_data()
);

generate
if (DEBUG_DUMP_ENABLE) begin : g_capture_dump
    capture_dump_controller #(
        .CLK_HZ(27000000),
        .BAUD(115200),
        .PIXEL_COUNT(784)
    ) u_capture_dump_controller (
        .clk(I_clk),
        .rst_n(i_rst_n_sync),
        .start(capture_done_i),
        .ram_rd_en(stream_rd_en),
        .ram_rd_addr(stream_rd_addr),
        .ram_rd_data(stream_rd_data),
        .uart_tx_o(debug_uart_tx),
        .busy(debug_dump_busy),
        .done(debug_dump_done)
    );
end else begin : g_no_capture_dump
    assign stream_rd_en = 1'b0;
    assign stream_rd_addr = 10'd0;
    assign debug_uart_tx = 1'b1;
    assign debug_dump_busy = 1'b0;
    assign debug_dump_done = 1'b0;
end
endgenerate

always @(posedge I_clk or negedge i_rst_n_sync) begin
    if (!i_rst_n_sync) begin
        capture_done_latched <= 1'b0;
        capture_error_latched <= 1'b0;
    end else begin
        if (capture_done_i) begin
            capture_done_latched <= 1'b1;
            capture_error_latched <= 1'b0;
        end else if (capture_error_i) begin
            capture_error_latched <= 1'b1;
        end else if (capture_arm_i) begin
            capture_done_latched <= 1'b0;
            capture_error_latched <= 1'b0;
        end
    end
end

nn_system #(
    .ACT_ADDR_WIDTH(9),
    .SPI_DIV(1),
    .FLASH_PARAM_BASE(24'h200000)
) u_nn_compile_only (
    .clk(I_clk),
    .rst_n(i_rst_n_sync),
    .start(capture_done_latched),
    .memory_ready(1'b1),
    .image_rd_en(),
    .image_rd_addr(),
    .image_rd_data(16'd0),
    .image_preload_valid(1'b1),
    .image_preload_wr_en(1'b0),
    .image_preload_wr_addr(9'd0),
    .image_preload_wr_data(32'd0),
    .flash_cs_n(nn_flash_cs_n),
    .flash_sclk(nn_flash_sclk),
    .flash_mosi(nn_flash_mosi),
    .flash_miso(key_sync[0]),
    .busy(nn_busy),
    .done(nn_done),
    .output_valid(nn_output_valid),
    .output_class(nn_output_class),
    .error(nn_error)
);

wire nn_keep_unused = nn_busy ^ nn_done ^ nn_output_valid ^ nn_error ^ (^nn_output_class);

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
    .show_processed(1'b0),
    .processed_rgb565(16'h0000),
    .hyperram_owner_request(SEL_VFB),
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
    .vfb_halt_active(),
    .hdmi_x(),
    .hdmi_y(),
    .hdmi_de(),
    .hdmi_frame_start(),
    .video_pixel_valid(),
    .video_pixel_x(),
    .video_pixel_y(),
    .video_rgb565()
);

endmodule
