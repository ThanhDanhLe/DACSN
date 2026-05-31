`timescale 1ns/1ps

module reset_sync #(
    parameter integer STAGES = 4
)(
    input  wire clk,
    input  wire arst_n,
    output wire srst_n
);

reg [STAGES-1:0] sync_pipe;

always @(posedge clk or negedge arst_n) begin
    if (!arst_n)
        sync_pipe <= {STAGES{1'b0}};
    else
        sync_pipe <= {sync_pipe[STAGES-2:0], 1'b1};
end

assign srst_n = sync_pipe[STAGES-1];

endmodule
