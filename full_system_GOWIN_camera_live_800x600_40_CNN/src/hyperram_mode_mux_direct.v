`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// hyperram_mode_mux_direct.v
//
// Small mode-level mux for the DIRECT_SPI_PARAM_STREAM profile. HyperRAM is only
// shared by the video frame buffer and the stable-frame ROI reader. NN
// parameters are streamed from SPI Flash, so there is no NN/loader/EMPU
// HyperRAM owner in this profile.
//
// Owners use the same numeric values as the full mux for top-level compatibility:
//   SEL_NONE   = 0
//   SEL_VFB    = 2
//   SEL_IMG_RD = 3
//   SEL_VFB_RD = 5  (VFB reads enabled, VFB writes halted)
// -----------------------------------------------------------------------------
module hyperram_mode_mux_direct #(
    parameter integer BURST_BEATS = 32,
    parameter integer DRAIN_CYCLES = 128,
    parameter integer OWNER_SYNC_STABLE_CYCLES = 2
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        init_calib,
    input  wire [2:0]  owner_select,

    input  wire        vfb_cmd,
    input  wire        vfb_cmd_en,
    input  wire [21:0] vfb_addr,
    input  wire [31:0] vfb_wr_data,
    input  wire [3:0]  vfb_data_mask,
    output reg         vfb_rd_data_valid,
    output reg  [31:0] vfb_rd_data,
    output reg         vfb_wr_halt,
    output reg         vfb_rd_halt,

    input  wire        img_cmd,
    input  wire        img_cmd_en,
    input  wire [21:0] img_addr,
    input  wire [31:0] img_wr_data,
    input  wire [3:0]  img_data_mask,
    input  wire        img_mem_active,
    output reg         img_mem_grant,
    output reg         img_rd_data_valid,
    output reg  [31:0] img_rd_data,

    output reg         hram_cmd,
    output reg         hram_cmd_en,
    output reg  [21:0] hram_addr,
    output reg  [31:0] hram_wr_data,
    output reg  [3:0]  hram_data_mask,
    input  wire        hram_rd_data_valid,
    input  wire [31:0] hram_rd_data,

    output reg  [2:0]  current_owner,
    output reg  [3:0]  mux_state,
    output reg         protocol_error
);

localparam [2:0]
    SEL_NONE   = 3'd0,
    SEL_VFB    = 3'd2,
    SEL_IMG_RD = 3'd3,
    SEL_VFB_RD = 3'd5;

localparam [3:0]
    M_WAIT_CALIB = 4'd0,
    M_NONE       = 4'd1,
    M_VFB        = 4'd2,
    M_IMG_RD     = 4'd3,
    M_DRAIN      = 4'd4;

localparam READ_CMD  = 1'b0;
localparam WRITE_CMD = 1'b1;
localparam [5:0] BURST_BEATS_6 = BURST_BEATS;
localparam [7:0] DRAIN_CYCLES_8 = DRAIN_CYCLES;

reg [2:0] owner_meta;
reg [2:0] owner_sync;
reg [2:0] owner_stable;
reg [3:0] owner_stable_count;
reg [2:0] drain_owner;
reg [2:0] drain_target;
reg [7:0] drain_count;
reg [2:0] write_owner;
reg [5:0] write_count;

wire [2:0] requested_owner =
    ((owner_stable == SEL_VFB) || (owner_stable == SEL_VFB_RD)) ? SEL_VFB :
    (owner_stable == SEL_IMG_RD) ? SEL_IMG_RD :
    SEL_NONE;

wire vfb_read_only_requested = (owner_stable == SEL_VFB_RD);
wire vfb_cmd_allowed = !(vfb_read_only_requested && (vfb_cmd == WRITE_CMD));
wire write_pending = (write_count != 6'd0);
wire drain_done = (drain_count == 8'd0) && !write_pending;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        owner_meta <= SEL_NONE;
        owner_sync <= SEL_NONE;
        owner_stable <= SEL_NONE;
        owner_stable_count <= 4'd0;
    end else begin
        owner_meta <= init_calib ? owner_select : SEL_NONE;
        owner_sync <= owner_meta;
        if (owner_sync == owner_stable) begin
            owner_stable_count <= 4'd0;
        end else if (owner_stable_count >= (OWNER_SYNC_STABLE_CYCLES - 1)) begin
            owner_stable <= owner_sync;
            owner_stable_count <= 4'd0;
        end else begin
            owner_stable_count <= owner_stable_count + 4'd1;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        vfb_rd_data_valid <= 1'b0;
        vfb_rd_data <= 32'd0;
        vfb_wr_halt <= 1'b1;
        vfb_rd_halt <= 1'b1;
        img_mem_grant <= 1'b0;
        img_rd_data_valid <= 1'b0;
        img_rd_data <= 32'd0;
        hram_cmd <= READ_CMD;
        hram_cmd_en <= 1'b0;
        hram_addr <= 22'd0;
        hram_wr_data <= 32'd0;
        hram_data_mask <= 4'hF;
        current_owner <= SEL_NONE;
        mux_state <= M_WAIT_CALIB;
        protocol_error <= 1'b0;
        drain_owner <= SEL_NONE;
        drain_target <= SEL_NONE;
        drain_count <= 8'd0;
        write_owner <= SEL_NONE;
        write_count <= 6'd0;
    end else begin
        vfb_rd_data_valid <= 1'b0;
        img_rd_data_valid <= 1'b0;
        hram_cmd_en <= 1'b0;

        if (write_count != 6'd0)
            write_count <= write_count - 6'd1;

        if (write_owner == SEL_VFB) begin
            hram_wr_data <= vfb_wr_data;
            hram_data_mask <= vfb_data_mask;
        end else if (write_owner == SEL_IMG_RD) begin
            hram_wr_data <= img_wr_data;
            hram_data_mask <= img_data_mask;
        end else begin
            hram_wr_data <= 32'd0;
            hram_data_mask <= 4'hF;
        end

        if (hram_rd_data_valid) begin
            if ((mux_state == M_VFB) || ((mux_state == M_DRAIN) && (drain_owner == SEL_VFB))) begin
                vfb_rd_data_valid <= 1'b1;
                vfb_rd_data <= hram_rd_data;
            end else if ((mux_state == M_IMG_RD) || ((mux_state == M_DRAIN) && (drain_owner == SEL_IMG_RD))) begin
                img_rd_data_valid <= 1'b1;
                img_rd_data <= hram_rd_data;
            end else begin
                protocol_error <= 1'b1;
            end
        end

        vfb_wr_halt <= (mux_state != M_VFB) || vfb_read_only_requested;
        vfb_rd_halt <= (mux_state != M_VFB);
        img_mem_grant <= (mux_state == M_IMG_RD);

        case (mux_state)
            M_WAIT_CALIB: begin
                current_owner <= SEL_NONE;
                vfb_wr_halt <= 1'b1;
                vfb_rd_halt <= 1'b1;
                if (init_calib)
                    mux_state <= M_NONE;
            end

            M_NONE: begin
                current_owner <= SEL_NONE;
                if (!init_calib) begin
                    mux_state <= M_WAIT_CALIB;
                end else if (requested_owner == SEL_VFB) begin
                    mux_state <= M_VFB;
                end else if (requested_owner == SEL_IMG_RD) begin
                    mux_state <= M_IMG_RD;
                end
            end

            M_VFB: begin
                current_owner <= SEL_VFB;
                if (!init_calib || (requested_owner != SEL_VFB)) begin
                    drain_owner <= SEL_VFB;
                    drain_target <= init_calib ? requested_owner : SEL_NONE;
                    drain_count <= DRAIN_CYCLES_8;
                    mux_state <= M_DRAIN;
                end else begin
                    hram_cmd <= vfb_cmd;
                    hram_cmd_en <= vfb_cmd_en && vfb_cmd_allowed;
                    hram_addr <= vfb_addr;
                    if (!vfb_read_only_requested && vfb_cmd_en && (vfb_cmd == WRITE_CMD)) begin
                        write_owner <= SEL_VFB;
                        write_count <= BURST_BEATS_6;
                    end
                    if (write_owner == SEL_NONE) begin
                        hram_wr_data <= vfb_wr_data;
                        hram_data_mask <= vfb_data_mask;
                    end
                end
            end

            M_IMG_RD: begin
                current_owner <= SEL_IMG_RD;
                if (!init_calib || (requested_owner != SEL_IMG_RD)) begin
                    drain_owner <= SEL_IMG_RD;
                    drain_target <= init_calib ? requested_owner : SEL_NONE;
                    drain_count <= DRAIN_CYCLES_8;
                    mux_state <= M_DRAIN;
                end else begin
                    hram_cmd <= img_cmd;
                    hram_cmd_en <= img_cmd_en;
                    hram_addr <= img_addr;
                    hram_wr_data <= img_wr_data;
                    hram_data_mask <= img_data_mask;
                    if (img_cmd_en && (img_cmd == WRITE_CMD)) begin
                        write_owner <= SEL_IMG_RD;
                        write_count <= BURST_BEATS_6;
                    end
                end
            end

            M_DRAIN: begin
                current_owner <= drain_owner;
                if (drain_count != 8'd0)
                    drain_count <= drain_count - 8'd1;

                if (drain_done) begin
                    write_owner <= SEL_NONE;
                    current_owner <= drain_target;
                    if (!init_calib)
                        mux_state <= M_WAIT_CALIB;
                    else if (drain_target == SEL_VFB)
                        mux_state <= M_VFB;
                    else if (drain_target == SEL_IMG_RD)
                        mux_state <= M_IMG_RD;
                    else
                        mux_state <= M_NONE;
                end
            end

            default: begin
                mux_state <= M_WAIT_CALIB;
                current_owner <= SEL_NONE;
                protocol_error <= 1'b1;
            end
        endcase
    end
end

wire img_mem_active_unused = img_mem_active;

endmodule
