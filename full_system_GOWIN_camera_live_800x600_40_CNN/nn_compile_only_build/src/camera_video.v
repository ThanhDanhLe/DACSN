`timescale 1ns/1ps

module camera_video #(
    parameter SIMULATION = 0,
    parameter H_RES = 800,
    parameter V_RES = 600,
    parameter ROI_X0 = 176,
    parameter ROI_Y0 = 76,
    parameter ROI_SIZE = 448
)(
    input             I_clk,
    input             I_rst_n,
    output     [1:0]  O_led,
    inout             SDA,
    inout             SCL,
    input             VSYNC,
    input             HREF,
    input      [9:2]  PIXDATA,
    input             PIXCLK,
    output            XCLK,
    output     [0:0]  O_hpram_ck,
    output     [0:0]  O_hpram_ck_n,
    output     [0:0]  O_hpram_cs_n,
    output     [0:0]  O_hpram_reset_n,
    inout      [7:0]  IO_hpram_dq,
    inout      [0:0]  IO_hpram_rwds,
    output            O_tmds_clk_p,
    output            O_tmds_clk_n,
    output     [2:0]  O_tmds_data_p,
    output     [2:0]  O_tmds_data_n,

    input             show_processed,
    input      [15:0] processed_rgb565,
    input      [2:0]  hyperram_owner_request,

    input             img_hram_cmd,
    input             img_hram_cmd_en,
    input      [21:0] img_hram_addr,
    input      [31:0] img_hram_wr_data,
    input      [3:0]  img_hram_data_mask,
    input             img_mem_active,
    output     [31:0] img_hram_rd_data,
    output            img_hram_rd_data_valid,
    output            img_mem_grant,

    output            pix_clk,
    output            pix_rst_n,
    output            hyperram_clk,
    output            hyperram_rst_n,
    output            calib_done,
    output     [2:0]  hyperram_current_owner,
    output     [3:0]  hyperram_owner_state,
    output            vfb_halt_active,
    output     [11:0] hdmi_x,
    output     [11:0] hdmi_y,
    output            hdmi_de,
    output            hdmi_frame_start,
    output            video_pixel_valid,
    output     [11:0] video_pixel_x,
    output     [11:0] video_pixel_y,
    output     [15:0] video_rgb565
);

localparam [15:0] ROI_BORDER_COLOR = 16'hF800;
localparam [11:0] ROI_X0_12 = ROI_X0;
localparam [11:0] ROI_Y0_12 = ROI_Y0;
localparam [11:0] ROI_X1_12 = ROI_X0 + ROI_SIZE;
localparam [11:0] ROI_Y1_12 = ROI_Y0 + ROI_SIZE;
localparam [11:0] H_RES_12 = H_RES;
localparam [11:0] V_RES_12 = V_RES;

generate
if (SIMULATION != 0) begin : g_sim
    localparam H_TOTAL = H_RES + 16;
    localparam V_TOTAL = V_RES + 8;

    reg [11:0] sim_x;
    reg [11:0] sim_y;
    reg        sim_de;
    reg        sim_frame_start;
    reg [7:0]  calib_cnt;
    reg [15:0] sim_rgb;
    wire        sim_hram_cmd;
    wire        sim_hram_cmd_en;
    wire [21:0] sim_hram_addr;
    wire [31:0] sim_hram_wr_data;
    wire [3:0]  sim_hram_data_mask;
    reg         sim_hram_rd_valid;
    reg [31:0]  sim_hram_rd_data;
    reg [5:0]   sim_read_count;
    reg [5:0]   sim_read_beat;
    reg [3:0]   sim_read_latency;
    reg [21:0]  sim_read_base_addr;
    wire        sim_vfb_wr_halt;
    wire        sim_vfb_rd_halt;

    assign pix_clk = I_clk;
    assign pix_rst_n = I_rst_n;
    assign hyperram_clk = I_clk;
    assign hyperram_rst_n = I_rst_n;
    assign calib_done = calib_cnt[7];
    assign hdmi_x = sim_x;
    assign hdmi_y = sim_y;
    assign hdmi_de = sim_de;
    assign hdmi_frame_start = sim_frame_start;
    assign video_pixel_valid = sim_de;
    assign video_pixel_x = sim_x;
    assign video_pixel_y = sim_y;
    assign video_rgb565 = sim_rgb;
    assign XCLK = I_clk;
    assign O_led = {~calib_done, calib_done};
    assign O_hpram_ck = 1'b0;
    assign O_hpram_ck_n = 1'b0;
    assign O_hpram_cs_n = 1'b1;
    assign O_hpram_reset_n = I_rst_n;
    assign O_tmds_clk_p = 1'b0;
    assign O_tmds_clk_n = 1'b0;
    assign O_tmds_data_p = 3'b000;
    assign O_tmds_data_n = 3'b000;
    assign SDA = 1'bz;
    assign SCL = 1'bz;
    assign IO_hpram_dq = 8'bzzzz_zzzz;
    assign IO_hpram_rwds = 1'bz;
    assign vfb_halt_active = sim_vfb_wr_halt | sim_vfb_rd_halt;

    wire sim_in_roi = sim_de &&
                      (sim_x >= ROI_X0_12) && (sim_x < ROI_X1_12) &&
                      (sim_y >= ROI_Y0_12) && (sim_y < ROI_Y1_12);
    wire sim_stroke = sim_in_roi &&
                      (((sim_x >= (ROI_X0_12 + 12'd216)) && (sim_x < (ROI_X0_12 + 12'd232))) ||
                       ((sim_y >= (ROI_Y0_12 + 12'd216)) && (sim_y < (ROI_Y0_12 + 12'd232))));

    function [15:0] sim_pixel_from_addr;
        input [21:0] byte_addr;
        integer pixel_index;
        integer px;
        integer py;
        integer roi_x_i;
        integer roi_y_i;
        begin
            pixel_index = byte_addr >> 1;
            px = pixel_index % H_RES;
            py = (pixel_index / H_RES) % V_RES;
            roi_x_i = px - ROI_X0;
            roi_y_i = py - ROI_Y0;
            if ((px >= ROI_X0) && (px < (ROI_X0 + ROI_SIZE)) &&
                (py >= ROI_Y0) && (py < (ROI_Y0 + ROI_SIZE)) &&
                (((roi_x_i >= 216) && (roi_x_i < 232)) ||
                 ((roi_y_i >= 216) && (roi_y_i < 232)))) begin
                sim_pixel_from_addr = 16'h0000;
            end else begin
                sim_pixel_from_addr = 16'hFFFF;
            end
        end
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sim_x <= 12'd0;
            sim_y <= 12'd0;
            sim_de <= 1'b0;
            sim_frame_start <= 1'b0;
            calib_cnt <= 8'd0;
            sim_rgb <= 16'hFFFF;
            sim_hram_rd_valid <= 1'b0;
            sim_hram_rd_data <= 32'd0;
            sim_read_count <= 6'd0;
            sim_read_beat <= 6'd0;
            sim_read_latency <= 4'd0;
            sim_read_base_addr <= 22'd0;
        end else begin
            if (!calib_cnt[7])
                calib_cnt <= calib_cnt + 8'd1;

            sim_frame_start <= (sim_x == 12'd0) && (sim_y == 12'd0);
            sim_de <= (sim_x < H_RES_12) && (sim_y < V_RES_12);
            sim_rgb <= sim_stroke ? 16'h0000 : 16'hFFFF;

            if (sim_x == (H_TOTAL - 1)) begin
                sim_x <= 12'd0;
                if (sim_y == (V_TOTAL - 1))
                    sim_y <= 12'd0;
                else
                    sim_y <= sim_y + 12'd1;
            end else begin
                sim_x <= sim_x + 12'd1;
            end

            sim_hram_rd_valid <= 1'b0;
            if (sim_hram_cmd_en && !sim_hram_cmd) begin
                sim_read_latency <= 4'd4;
                sim_read_count <= 6'd32;
                sim_read_beat <= 6'd0;
                sim_read_base_addr <= sim_hram_addr;
            end else if (sim_read_latency != 4'd0) begin
                sim_read_latency <= sim_read_latency - 4'd1;
            end else if (sim_read_count != 6'd0) begin
                sim_hram_rd_valid <= 1'b1;
                sim_hram_rd_data <= {
                    sim_pixel_from_addr(sim_read_base_addr + {14'd0, sim_read_beat, 2'b10}),
                    sim_pixel_from_addr(sim_read_base_addr + {14'd0, sim_read_beat, 2'b00})
                };
                sim_read_beat <= sim_read_beat + 6'd1;
                sim_read_count <= sim_read_count - 6'd1;
            end
        end
    end

    hyperram_mode_mux_direct u_hyperram_mode_mux (
        .clk(I_clk),
        .rst_n(I_rst_n),
        .init_calib(calib_done),
        .owner_select(hyperram_owner_request),
        .vfb_cmd(1'b0),
        .vfb_cmd_en(1'b0),
        .vfb_addr(22'd0),
        .vfb_wr_data(32'd0),
        .vfb_data_mask(4'hF),
        .vfb_rd_data_valid(),
        .vfb_rd_data(),
        .vfb_wr_halt(sim_vfb_wr_halt),
        .vfb_rd_halt(sim_vfb_rd_halt),
        .img_cmd(img_hram_cmd),
        .img_cmd_en(img_hram_cmd_en),
        .img_addr(img_hram_addr),
        .img_wr_data(img_hram_wr_data),
        .img_data_mask(img_hram_data_mask),
        .img_mem_active(img_mem_active),
        .img_mem_grant(img_mem_grant),
        .img_rd_data_valid(img_hram_rd_data_valid),
        .img_rd_data(img_hram_rd_data),
        .hram_cmd(sim_hram_cmd),
        .hram_cmd_en(sim_hram_cmd_en),
        .hram_addr(sim_hram_addr),
        .hram_wr_data(sim_hram_wr_data),
        .hram_data_mask(sim_hram_data_mask),
        .hram_rd_data_valid(sim_hram_rd_valid),
        .hram_rd_data(sim_hram_rd_data),
        .current_owner(hyperram_current_owner),
        .mux_state(hyperram_owner_state),
        .protocol_error()
    );
end else begin : g_hw
    wire sys_resetn;

    wire        ch0_vfb_clk_in;
    wire        ch0_vfb_vs_in;
    wire        ch0_vfb_de_in;
    wire [15:0] ch0_vfb_data_in;

    wire        syn_off0_re;
    wire        syn_off0_vs;
    wire        syn_off0_hs;
    wire        out_de;
    wire        off0_syn_de;
    wire [15:0] off0_syn_data;

    wire        dma_clk;
    wire        memory_clk;
    wire        mem_pll_lock;
    wire        vfb_cmd;
    wire        vfb_cmd_en;
    wire [21:0] vfb_addr;
    wire [31:0] vfb_wr_data;
    wire [3:0]  vfb_data_mask;
    wire        vfb_rd_data_valid;
    wire [31:0] vfb_rd_data;
    wire        vfb_wr_halt;
    wire        vfb_rd_halt;
    wire        hram_cmd;
    wire        hram_cmd_en;
    wire [21:0] hram_addr;
    wire [31:0] hram_wr_data;
    wire [3:0]  hram_data_mask;
    wire        hram_rd_data_valid;
    wire [31:0] hram_rd_data;
    wire        init_calib;

    wire serial_clk;
    wire pll_lock;
    wire hdmi_rst_n;
    wire pix_clk_int;
    wire clk_12M;

    wire [15:0] cam_data_r;
    wire        cam_de_r;

    reg [1:0]  hs_dn;
    reg [1:0]  vs_dn;
    reg [1:0]  de_dn;
    reg [11:0] x_cnt;
    reg [11:0] y_cnt;
    reg        rgb_de_d;
    reg        rgb_vs_d;
    reg        frame_start_r;
    wire       video_pixel_valid_r;
    wire [11:0] video_pixel_x_r;
    wire [11:0] video_pixel_y_r;
    wire [15:0] video_rgb565_r;
    wire [40:0] video_stream_pipe;
    reg        rgb_de_tx;
    reg        rgb_hs_tx;
    reg        rgb_vs_tx;
    reg [23:0] rgb_data_tx;

    wire rgb_de = de_dn[1];
    wire rgb_hs = hs_dn[1];
    wire rgb_vs = vs_dn[1];

    assign pix_clk = pix_clk_int;
    assign pix_rst_n = hdmi_rst_n;
    assign hyperram_clk = dma_clk;
    assign hyperram_rst_n = sys_resetn;
    assign calib_done = init_calib;
    assign vfb_halt_active = vfb_wr_halt | vfb_rd_halt;
    assign hdmi_x = x_cnt;
    assign hdmi_y = y_cnt;
    assign hdmi_de = rgb_de;
    assign hdmi_frame_start = frame_start_r;
    assign video_pixel_valid = video_pixel_valid_r;
    assign video_pixel_x = video_pixel_x_r;
    assign video_pixel_y = video_pixel_y_r;
    assign video_rgb565 = video_rgb565_r;
    assign {video_pixel_valid_r, video_pixel_x_r, video_pixel_y_r, video_rgb565_r} = video_stream_pipe;
    assign O_led[0] = init_calib;
    assign O_led[1] = ~init_calib;
    assign XCLK = clk_12M;

    leaf_reg_bus_rst #(
        .WIDTH(41),
        .RESET_VALUE(41'd0)
    ) u_video_stream_pipe_reg (
        .clk(pix_clk_int),
        .rst_n(hdmi_rst_n),
        .d({rgb_de, x_cnt, y_cnt, off0_syn_data}),
        .q(video_stream_pipe)
    );

    reset_sync u_reset_sync (
        .clk(I_clk),
        .arst_n(I_rst_n & pll_lock),
        .srst_n(sys_resetn)
    );

    OV2640_Controller u_OV2640_Controller (
        .clk(clk_12M),
        .resend(1'b0),
        .config_finished(),
        .sioc(SCL),
        .siod(SDA),
        .reset(),
        .pwdn()
    );

    camera_byte_packer u_camera_byte_packer (
        .clk(PIXCLK),
        .rst_n(sys_resetn),
        .href(HREF),
        .pixdata(PIXDATA),
        .pixel_rgb565(cam_data_r),
        .pixel_valid(cam_de_r)
    );

    assign ch0_vfb_clk_in  = PIXCLK;
    assign ch0_vfb_vs_in   = VSYNC;
    assign ch0_vfb_de_in   = cam_de_r;
    assign ch0_vfb_data_in = cam_data_r;

    Video_Frame_Buffer_Top u_frame_buffer (
        .I_rst_n            (init_calib),
        .I_dma_clk          (dma_clk),
        .I_wr_halt          (vfb_wr_halt),
        .I_rd_halt          (vfb_rd_halt),
        .I_vin0_clk         (ch0_vfb_clk_in),
        .I_vin0_vs_n        (ch0_vfb_vs_in),
        .I_vin0_de          (ch0_vfb_de_in),
        .I_vin0_data        (ch0_vfb_data_in),
        .O_vin0_fifo_full   (),
        .I_vout0_clk        (pix_clk_int),
        .I_vout0_vs_n       (~syn_off0_vs),
        .I_vout0_de         (syn_off0_re),
        .O_vout0_den        (off0_syn_de),
        .O_vout0_data       (off0_syn_data),
        .O_vout0_fifo_empty (),
        .O_cmd              (vfb_cmd),
        .O_cmd_en           (vfb_cmd_en),
        .O_addr             (vfb_addr),
        .O_wr_data          (vfb_wr_data),
        .O_data_mask        (vfb_data_mask),
        .I_rd_data_valid    (vfb_rd_data_valid),
        .I_rd_data          (vfb_rd_data),
        .I_init_calib       (init_calib)
    );

    GW_PLLVR u_mem_pll (
        .clkout(memory_clk),
        .lock(mem_pll_lock),
        .clkin(I_clk)
    );

    HyperRAM_Memory_Interface_Top u_hyperram (
        .clk(I_clk),
        .memory_clk(memory_clk),
        .pll_lock(mem_pll_lock),
        .rst_n(sys_resetn),
        .O_hpram_ck(O_hpram_ck),
        .O_hpram_ck_n(O_hpram_ck_n),
        .IO_hpram_rwds(IO_hpram_rwds),
        .IO_hpram_dq(IO_hpram_dq),
        .O_hpram_reset_n(O_hpram_reset_n),
        .O_hpram_cs_n(O_hpram_cs_n),
        .wr_data(hram_wr_data),
        .rd_data(hram_rd_data),
        .rd_data_valid(hram_rd_data_valid),
        .addr(hram_addr),
        .cmd(hram_cmd),
        .cmd_en(hram_cmd_en),
        .clk_out(dma_clk),
        .data_mask(hram_data_mask),
        .init_calib(init_calib)
    );

    hyperram_mode_mux_direct u_hyperram_mode_mux (
        .clk(dma_clk),
        .rst_n(sys_resetn),
        .init_calib(init_calib),
        .owner_select(hyperram_owner_request),
        .vfb_cmd(vfb_cmd),
        .vfb_cmd_en(vfb_cmd_en),
        .vfb_addr(vfb_addr),
        .vfb_wr_data(vfb_wr_data),
        .vfb_data_mask(vfb_data_mask),
        .vfb_rd_data_valid(vfb_rd_data_valid),
        .vfb_rd_data(vfb_rd_data),
        .vfb_wr_halt(vfb_wr_halt),
        .vfb_rd_halt(vfb_rd_halt),
        .img_cmd(img_hram_cmd),
        .img_cmd_en(img_hram_cmd_en),
        .img_addr(img_hram_addr),
        .img_wr_data(img_hram_wr_data),
        .img_data_mask(img_hram_data_mask),
        .img_mem_active(img_mem_active),
        .img_mem_grant(img_mem_grant),
        .img_rd_data_valid(img_hram_rd_data_valid),
        .img_rd_data(img_hram_rd_data),
        .hram_cmd(hram_cmd),
        .hram_cmd_en(hram_cmd_en),
        .hram_addr(hram_addr),
        .hram_wr_data(hram_wr_data),
        .hram_data_mask(hram_data_mask),
        .hram_rd_data_valid(hram_rd_data_valid),
        .hram_rd_data(hram_rd_data),
        .current_owner(hyperram_current_owner),
        .mux_state(hyperram_owner_state),
        .protocol_error()
    );

    syn_gen u_syn_gen (
        .I_pxl_clk(pix_clk_int),
        .I_rst_n(hdmi_rst_n),
        .I_h_total(16'd1056),
        .I_h_sync(16'd128),
        .I_h_bporch(16'd88),
        .I_h_res(16'd800),
        .I_v_total(16'd628),
        .I_v_sync(16'd4),
        .I_v_bporch(16'd23),
        .I_v_res(16'd600),
        .I_rd_hres(16'd800),
        .I_rd_vres(16'd600),
        .I_hs_pol(1'b1),
        .I_vs_pol(1'b1),
        .O_rden(syn_off0_re),
        .O_de(out_de),
        .O_hs(syn_off0_hs),
        .O_vs(syn_off0_vs)
    );

    wire roi_border = rgb_de &&
                      (x_cnt >= ROI_X0_12) && (x_cnt < ROI_X1_12) &&
                      (y_cnt >= ROI_Y0_12) && (y_cnt < ROI_Y1_12) &&
                      ((x_cnt == ROI_X0_12) || (x_cnt == (ROI_X1_12 - 12'd1)) ||
                       (y_cnt == ROI_Y0_12) || (y_cnt == (ROI_Y1_12 - 12'd1)));
    wire [15:0] live_rgb565 = roi_border ? ROI_BORDER_COLOR : off0_syn_data;
    wire [15:0] hdmi_rgb565 = show_processed ? processed_rgb565 : live_rgb565;

    always @(posedge pix_clk_int or negedge hdmi_rst_n) begin
        if (!hdmi_rst_n) begin
            hs_dn <= 2'b11;
            vs_dn <= 2'b11;
            de_dn <= 2'b00;
            x_cnt <= 12'd0;
            y_cnt <= 12'd0;
            rgb_de_d <= 1'b0;
            rgb_vs_d <= 1'b0;
            frame_start_r <= 1'b0;
            rgb_de_tx <= 1'b0;
            rgb_hs_tx <= 1'b0;
            rgb_vs_tx <= 1'b0;
            rgb_data_tx <= 24'd0;
        end else begin
            hs_dn <= {hs_dn[0], syn_off0_hs};
            vs_dn <= {vs_dn[0], syn_off0_vs};
            de_dn <= {de_dn[0], out_de};

            rgb_de_d <= rgb_de;
            rgb_vs_d <= rgb_vs;
            frame_start_r <= rgb_vs && !rgb_vs_d;
            rgb_de_tx <= rgb_de;
            rgb_hs_tx <= rgb_hs;
            rgb_vs_tx <= rgb_vs;
            rgb_data_tx <= rgb_de ? {hdmi_rgb565[15:11], 3'd0,
                                     hdmi_rgb565[10:5], 2'd0,
                                     hdmi_rgb565[4:0], 3'd0} : 24'd0;

            if (rgb_vs && !rgb_vs_d) begin
                x_cnt <= 12'd0;
                y_cnt <= 12'd0;
            end else if (rgb_de && !rgb_de_d) begin
                x_cnt <= 12'd0;
            end else if (rgb_de) begin
                x_cnt <= x_cnt + 12'd1;
            end

            if (!rgb_de && rgb_de_d)
                y_cnt <= y_cnt + 12'd1;
        end
    end

    TMDS_PLLVR u_tmds_pll (
        .clkin(I_clk),
        .clkout(serial_clk),
        .clkoutd(clk_12M),
        .lock(pll_lock)
    );

    assign hdmi_rst_n = sys_resetn & pll_lock;

    CLKDIV #(
        .DIV_MODE("5")
    ) u_clkdiv (
        .RESETN(hdmi_rst_n),
        .HCLKIN(serial_clk),
        .CLKOUT(pix_clk_int),
        .CALIB(1'b1)
    );

    DVI_TX_Top u_dvi_tx (
        .I_rst_n(hdmi_rst_n),
        .I_serial_clk(serial_clk),
        .I_rgb_clk(pix_clk_int),
        .I_rgb_vs(rgb_vs_tx),
        .I_rgb_hs(rgb_hs_tx),
        .I_rgb_de(rgb_de_tx),
        .I_rgb_r(rgb_data_tx[23:16]),
        .I_rgb_g(rgb_data_tx[15:8]),
        .I_rgb_b(rgb_data_tx[7:0]),
        .O_tmds_clk_p(O_tmds_clk_p),
        .O_tmds_clk_n(O_tmds_clk_n),
        .O_tmds_data_p(O_tmds_data_p),
        .O_tmds_data_n(O_tmds_data_n)
    );
end
endgenerate

endmodule
