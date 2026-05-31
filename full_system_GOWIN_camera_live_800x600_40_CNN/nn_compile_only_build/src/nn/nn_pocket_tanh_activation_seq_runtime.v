`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// nn_pocket_tanh_activation_seq_runtime.v
//
// Same exact PocketNN activation as nn_pocket_tanh_activation_seq, but the
// divisor is provided at run time so one activation/divider can be shared across
// all three MLP layers.
// -----------------------------------------------------------------------------
module nn_pocket_tanh_activation_seq_runtime #(
    parameter integer ACC_WIDTH = 64,
    parameter integer OUT_WIDTH = 16
)(
    input  wire clk,
    input  wire rst_n,

    input  wire start,
    input  wire signed [ACC_WIDTH-1:0] acc,
    input  wire [31:0] divisor,

    output reg  busy,
    output reg  done,
    output reg  signed [OUT_WIDTH-1:0] act
);
localparam [1:0]
    S_IDLE  = 2'd0,
    S_DIV   = 2'd1,
    S_APPLY = 2'd2;

reg [1:0] state;
reg div_start;
wire div_busy;
wire div_done;
wire signed [31:0] div_q;
reg signed [31:0] x2;

wire x2_neg = x2[31];
wire [31:0] x2_abs = x2_neg ? (~x2 + 32'd1) : x2;
wire [31:0] q4_abs = {2'b00, x2_abs[31:2]};
wire signed [31:0] q4 = x2_neg ? -$signed(q4_abs) : $signed(q4_abs);

nn_signed_divider_seq #(
    .DIVIDEND_WIDTH(ACC_WIDTH),
    .DIVISOR_WIDTH(32),
    .QUOT_WIDTH(32)
) u_divider (
    .clk(clk),
    .rst_n(rst_n),
    .start(div_start),
    .dividend(acc),
    .divisor(divisor),
    .busy(div_busy),
    .done(div_done),
    .quotient(div_q)
);

reg signed [31:0] y_next;
always @(*) begin
    if (x2 < -32'sd127)
        y_next = -32'sd127;
    else if (x2 < -32'sd74)
        y_next = q4 - 32'sd88;
    else if (x2 < -32'sd31)
        y_next = x2 - 32'sd32;
    else if (x2 < 32'sd32)
        y_next = x2 <<< 1;
    else if (x2 < 32'sd75)
        y_next = x2 + 32'sd32;
    else if (x2 < 32'sd128)
        y_next = q4 + 32'sd88;
    else
        y_next = 32'sd127;
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;
        div_start <= 1'b0;
        busy <= 1'b0;
        done <= 1'b0;
        act <= {OUT_WIDTH{1'b0}};
        x2 <= 32'sd0;
    end else begin
        div_start <= 1'b0;
        done <= 1'b0;

        case (state)
            S_IDLE: begin
                busy <= 1'b0;
                if (start) begin
                    div_start <= 1'b1;
                    busy <= 1'b1;
                    state <= S_DIV;
                end
            end

            S_DIV: begin
                busy <= 1'b1;
                if (div_done) begin
                    x2 <= div_q;
                    state <= S_APPLY;
                end
            end

            S_APPLY: begin
                act <= y_next[OUT_WIDTH-1:0];
                done <= 1'b1;
                busy <= 1'b0;
                state <= S_IDLE;
            end

            default: begin
                busy <= 1'b0;
                state <= S_IDLE;
            end
        endcase
    end
end
endmodule
