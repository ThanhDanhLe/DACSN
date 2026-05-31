`timescale 1ns/1ps

module streaming_mnist_preload_packer #(
    parameter integer PIXEL_COUNT = 784
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output wire        ram_rd_en,
    output wire [9:0]  ram_rd_addr,
    input  wire [15:0] ram_rd_data,
    output reg         preload_wr_en,
    output reg  [8:0]  preload_wr_addr,
    output reg  [31:0] preload_wr_data,
    output reg         busy,
    output reg         done
);

localparam [1:0]
    S_IDLE    = 2'd0,
    S_READ    = 2'd1,
    S_CAPTURE = 2'd2,
    S_DONE    = 2'd3;

reg [1:0] state;
reg [9:0] next_addr;
reg [9:0] issued_addr;
reg [15:0] low_pixel;

assign ram_rd_en = (state == S_READ);
assign ram_rd_addr = next_addr;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;
        next_addr <= 10'd0;
        issued_addr <= 10'd0;
        low_pixel <= 16'd0;
        preload_wr_en <= 1'b0;
        preload_wr_addr <= 9'd0;
        preload_wr_data <= 32'd0;
        busy <= 1'b0;
        done <= 1'b0;
    end else begin
        preload_wr_en <= 1'b0;
        done <= 1'b0;

        case (state)
            S_IDLE: begin
                busy <= 1'b0;
                if (start) begin
                    next_addr <= 10'd0;
                    issued_addr <= 10'd0;
                    low_pixel <= 16'd0;
                    busy <= 1'b1;
                    state <= S_READ;
                end
            end

            S_READ: begin
                issued_addr <= next_addr;
                state <= S_CAPTURE;
            end

            S_CAPTURE: begin
                if (issued_addr[0] == 1'b0) begin
                    low_pixel <= ram_rd_data;
                end else begin
                    preload_wr_en <= 1'b1;
                    preload_wr_addr <= issued_addr[9:1];
                    preload_wr_data <= {ram_rd_data, low_pixel};
                end

                if (issued_addr == PIXEL_COUNT - 1) begin
                    state <= S_DONE;
                end else begin
                    next_addr <= issued_addr + 1'b1;
                    state <= S_READ;
                end
            end

            S_DONE: begin
                busy <= 1'b0;
                done <= 1'b1;
                state <= S_IDLE;
            end

            default: begin
                state <= S_IDLE;
                busy <= 1'b0;
            end
        endcase
    end
end

endmodule
