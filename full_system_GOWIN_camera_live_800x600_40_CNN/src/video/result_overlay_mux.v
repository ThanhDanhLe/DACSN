`timescale 1ns/1ps

module result_overlay_mux (
    input  wire [23:0] base_rgb,
    input  wire        overlay_on,
    input  wire [23:0] overlay_rgb,
    output wire [23:0] rgb
);

assign rgb = overlay_on ? overlay_rgb : base_rgb;

endmodule
