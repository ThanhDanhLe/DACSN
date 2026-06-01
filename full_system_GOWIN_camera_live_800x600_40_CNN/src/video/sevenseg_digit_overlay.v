`timescale 1ns/1ps

// Draws one seven-segment digit with only coordinate compares.
// Segment bit order is seg[6:0] = {A,B,C,D,E,F,G}; 1 means segment on.
module sevenseg_digit_overlay #(
    parameter X0 = 32,
    parameter Y0 = 32,
    parameter W  = 48,
    parameter H  = 84,
    parameter T  = 6,
    parameter FAST_POWER2 = 0
)(
    input  wire        active,
    input  wire [10:0] x,
    input  wire [10:0] y,
    input  wire [6:0]  seg,
    output wire        overlay_on,
    output wire [23:0] overlay_rgb
);

generate
if (FAST_POWER2 != 0) begin : g_fast_power2
    // Timing-light mode used by the HDMI path. It draws a 64x128 digit at
    // x=0..63, y=0..127 with 8-pixel vertical bars and 8/16-pixel horizontal
    // bars, using only high-bit window checks and small bin compares.
    wire in_box = active && (x[10:6] == 5'd0) && (y[10:7] == 4'd0);
    wire [2:0] x_bin = x[5:3];
    wire [3:0] y_bin = y[6:3];

    wire x_inner = (x_bin != 3'd0) && (x_bin != 3'd7);
    wire y_upper = (y_bin >= 4'd1) && (y_bin <= 4'd6);
    wire y_lower = (y_bin >= 4'd9) && (y_bin <= 4'd14);

    wire seg_a_on = x_inner && (y_bin == 4'd0);
    wire seg_b_on = (x_bin == 3'd7) && y_upper;
    wire seg_c_on = (x_bin == 3'd7) && y_lower;
    wire seg_d_on = x_inner && (y_bin == 4'd15);
    wire seg_e_on = (x_bin == 3'd0) && y_lower;
    wire seg_f_on = (x_bin == 3'd0) && y_upper;
    wire seg_g_on = x_inner && ((y_bin == 4'd7) || (y_bin == 4'd8));

    assign overlay_on = in_box &&
                        ((seg[6] && seg_a_on) ||
                         (seg[5] && seg_b_on) ||
                         (seg[4] && seg_c_on) ||
                         (seg[3] && seg_d_on) ||
                         (seg[2] && seg_e_on) ||
                         (seg[1] && seg_f_on) ||
                         (seg[0] && seg_g_on));
end else begin : g_generic
localparam [10:0] X_LEFT   = X0;
localparam [10:0] X_RIGHT  = X0 + W;
localparam [10:0] X_IN_L   = X0 + T;
localparam [10:0] X_IN_R   = X0 + W - T;
localparam [10:0] Y_TOP    = Y0;
localparam [10:0] Y_BOTTOM = Y0 + H;
localparam [10:0] Y_IN_T   = Y0 + T;
localparam [10:0] Y_IN_B   = Y0 + H - T;
localparam [10:0] Y_MID    = Y0 + (H / 2);
localparam [10:0] Y_MID_T  = Y0 + (H / 2) - (T / 2);
localparam [10:0] Y_MID_B  = Y0 + (H / 2) + ((T + 1) / 2);

wire in_x_inner = (x >= X_IN_L) && (x < X_IN_R);
wire in_y_upper = (y >= Y_IN_T) && (y < Y_MID);
wire in_y_lower = (y >= Y_MID) && (y < Y_IN_B);

wire seg_a_on = in_x_inner && (y >= Y_TOP)   && (y < Y_IN_T);
wire seg_b_on = (x >= X_IN_R) && (x < X_RIGHT) && in_y_upper;
wire seg_c_on = (x >= X_IN_R) && (x < X_RIGHT) && in_y_lower;
wire seg_d_on = in_x_inner && (y >= Y_IN_B)  && (y < Y_BOTTOM);
wire seg_e_on = (x >= X_LEFT) && (x < X_IN_L) && in_y_lower;
wire seg_f_on = (x >= X_LEFT) && (x < X_IN_L) && in_y_upper;
wire seg_g_on = in_x_inner && (y >= Y_MID_T) && (y < Y_MID_B);

assign overlay_on = active &&
                    ((seg[6] && seg_a_on) ||
                     (seg[5] && seg_b_on) ||
                     (seg[4] && seg_c_on) ||
                     (seg[3] && seg_d_on) ||
                     (seg[2] && seg_e_on) ||
                     (seg[1] && seg_f_on) ||
                     (seg[0] && seg_g_on));
end
endgenerate

assign overlay_rgb = 24'h00FF40;

endmodule
