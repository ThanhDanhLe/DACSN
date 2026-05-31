`timescale 1ns/1ps

module cdc_pulse_sync (
    input  wire src_clk,
    input  wire src_rst_n,
    input  wire src_pulse,
    input  wire dst_clk,
    input  wire dst_rst_n,
    output reg  dst_pulse
);

reg src_toggle;
reg dst_meta;
reg dst_sync;
reg dst_sync_d;

always @(posedge src_clk or negedge src_rst_n) begin
    if (!src_rst_n)
        src_toggle <= 1'b0;
    else if (src_pulse)
        src_toggle <= ~src_toggle;
end

always @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
        dst_meta <= 1'b0;
        dst_sync <= 1'b0;
        dst_sync_d <= 1'b0;
        dst_pulse <= 1'b0;
    end else begin
        dst_meta <= src_toggle;
        dst_sync <= dst_meta;
        dst_sync_d <= dst_sync;
        dst_pulse <= dst_sync ^ dst_sync_d;
    end
end

endmodule
