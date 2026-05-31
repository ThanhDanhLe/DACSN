`timescale 1ns/1ps

module leaf_sext32_to_acc #(
    parameter ACC_WIDTH = 36
)(
    input  wire [31:0]                 value,
    output wire signed [ACC_WIDTH-1:0] out
);

assign out = {{(ACC_WIDTH-32){value[31]}}, value};

endmodule
