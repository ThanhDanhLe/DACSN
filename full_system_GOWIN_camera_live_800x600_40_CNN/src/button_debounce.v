`timescale 1ns/1ps

module button_debounce #(
    parameter ACTIVE_LOW = 1,
    parameter integer DEBOUNCE_TICKS = 540000,
    parameter integer CNT_WIDTH = 20
)(
    input  wire clk,
    input  wire rst_n,
    input  wire button_in,
    output reg  stable_pressed,
    output reg  pressed_pulse,
    output reg  released_pulse
);

localparam RESET_LEVEL = (ACTIVE_LOW != 0) ? 1'b1 : 1'b0;
localparam [CNT_WIDTH-1:0] DEBOUNCE_LAST =
    (DEBOUNCE_TICKS <= 1) ? {CNT_WIDTH{1'b0}} : (DEBOUNCE_TICKS - 1);

reg sync0;
reg sync1;
reg [CNT_WIDTH-1:0] cnt;

wire raw_pressed = (ACTIVE_LOW != 0) ? ~sync1 : sync1;
wire raw_changed = (raw_pressed != stable_pressed);
wire debounce_done;

generate
if ((DEBOUNCE_TICKS > 1) && (DEBOUNCE_TICKS == (1 << (CNT_WIDTH - 1)))) begin : g_msb_done
    assign debounce_done = cnt[CNT_WIDTH-1];
end else begin : g_compare_done
    assign debounce_done = (cnt >= DEBOUNCE_LAST);
end
endgenerate

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sync0 <= RESET_LEVEL;
        sync1 <= RESET_LEVEL;
        stable_pressed <= 1'b0;
        pressed_pulse <= 1'b0;
        released_pulse <= 1'b0;
        cnt <= {CNT_WIDTH{1'b0}};
    end else begin
        sync0 <= button_in;
        sync1 <= sync0;
        pressed_pulse <= 1'b0;
        released_pulse <= 1'b0;

        if (!raw_changed) begin
            cnt <= {CNT_WIDTH{1'b0}};
        end else if (debounce_done) begin
            stable_pressed <= raw_pressed;
            pressed_pulse <= raw_pressed;
            released_pulse <= ~raw_pressed;
            cnt <= {CNT_WIDTH{1'b0}};
        end else begin
            cnt <= cnt + {{(CNT_WIDTH-1){1'b0}}, 1'b1};
        end
    end
end

endmodule
