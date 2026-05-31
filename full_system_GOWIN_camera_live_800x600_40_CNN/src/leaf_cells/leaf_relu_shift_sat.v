`timescale 1ns/1ps

module leaf_relu_shift_sat #(
    parameter ACC_WIDTH = 36,
    parameter SHIFT = 16
)(
    input  wire signed [ACC_WIDTH-1:0] value,
    output reg  signed [15:0]          out
);

reg signed [ACC_WIDTH-1:0] shifted;

always @* begin
    shifted = value >>> SHIFT;
    if (value <= $signed({ACC_WIDTH{1'b0}})) begin
        out = 16'sd0;
    end else begin
        if (shifted > $signed({{(ACC_WIDTH-16){1'b0}}, 16'sd32767}))
            out = 16'sd32767;
        else
            out = shifted[15:0];
    end
end

endmodule
