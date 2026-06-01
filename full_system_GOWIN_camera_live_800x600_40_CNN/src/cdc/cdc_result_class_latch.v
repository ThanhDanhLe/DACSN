`timescale 1ns/1ps

// CDC latch for the CNN class result.
//
// The source domain captures src_class on the rising edge of src_valid and
// toggles an event bit. The destination domain synchronizes that toggle, then
// samples the held class. This is safe for the current flow controller because
// result_valid/result_class are registered in I_clk and result_class is held
// stable while result_valid remains asserted in the result-display state.
module cdc_result_class_latch (
    input  wire       src_clk,
    input  wire       src_rst_n,
    input  wire       src_valid,
    input  wire [3:0] src_class,

    input  wire       dst_clk,
    input  wire       dst_rst_n,
    output reg  [3:0] displayed_class_pix,
    output wire       displayed_class_valid_pix
);

reg       src_valid_d;
reg [3:0] src_class_hold;
reg       src_event_toggle;

reg [2:0] dst_event_sync;
reg [1:0] dst_valid_sync;

wire src_valid_rise = src_valid && !src_valid_d;
wire dst_event_pulse = dst_event_sync[2] ^ dst_event_sync[1];

assign displayed_class_valid_pix = dst_valid_sync[1];

always @(posedge src_clk or negedge src_rst_n) begin
    if (!src_rst_n) begin
        src_valid_d <= 1'b0;
        src_class_hold <= 4'hF;
        src_event_toggle <= 1'b0;
    end else begin
        src_valid_d <= src_valid;
        if (src_valid_rise) begin
            src_class_hold <= src_class;
            src_event_toggle <= ~src_event_toggle;
        end
    end
end

always @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
        dst_event_sync <= 3'b000;
        dst_valid_sync <= 2'b00;
        displayed_class_pix <= 4'hF;
    end else begin
        dst_event_sync <= {dst_event_sync[1:0], src_event_toggle};
        dst_valid_sync <= {dst_valid_sync[0], src_valid};
        if (dst_event_pulse)
            displayed_class_pix <= src_class_hold;
    end
end

endmodule
