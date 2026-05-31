`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// nn_signed_divider_seq.v
//
// Sequential signed divider with truncation toward zero.
// Positive divisor only. The datapath uses unsigned restoring division on the
// absolute dividend, then restores the sign on the quotient.
// -----------------------------------------------------------------------------
module nn_signed_divider_seq #(
    parameter integer DIVIDEND_WIDTH = 64,
    parameter integer DIVISOR_WIDTH  = 32,
    parameter integer QUOT_WIDTH     = 32
)(
    input  wire clk,
    input  wire rst_n,

    input  wire start,
    input  wire signed [DIVIDEND_WIDTH-1:0] dividend,
    input  wire [DIVISOR_WIDTH-1:0] divisor,

    output reg  busy,
    output reg  done,
    output reg  signed [QUOT_WIDTH-1:0] quotient
);

localparam integer ITER_WIDTH = 8;

reg dividend_neg;
reg [DIVIDEND_WIDTH-1:0] dividend_shift;
reg [DIVIDEND_WIDTH-1:0] quotient_abs;
reg [DIVIDEND_WIDTH:0] remainder;
reg [DIVISOR_WIDTH-1:0] divisor_hold;
reg [ITER_WIDTH-1:0] iter_count;

wire [DIVIDEND_WIDTH-1:0] dividend_abs =
    dividend[DIVIDEND_WIDTH-1] ? (~dividend[DIVIDEND_WIDTH-1:0] + {{(DIVIDEND_WIDTH-1){1'b0}}, 1'b1}) :
                                 dividend[DIVIDEND_WIDTH-1:0];

wire [DIVIDEND_WIDTH:0] divisor_ext =
    {{(DIVIDEND_WIDTH + 1 - DIVISOR_WIDTH){1'b0}}, divisor_hold};

wire [DIVIDEND_WIDTH:0] rem_shift =
    {remainder[DIVIDEND_WIDTH-1:0], dividend_shift[DIVIDEND_WIDTH-1]};

wire ge_divisor = (divisor_hold != {DIVISOR_WIDTH{1'b0}}) && (rem_shift >= divisor_ext);
wire [DIVIDEND_WIDTH:0] rem_next = ge_divisor ? (rem_shift - divisor_ext) : rem_shift;
wire [DIVIDEND_WIDTH-1:0] quotient_shift_next =
    {quotient_abs[DIVIDEND_WIDTH-2:0], ge_divisor};
wire [QUOT_WIDTH-1:0] quotient_abs_trunc = quotient_shift_next[QUOT_WIDTH-1:0];
wire [QUOT_WIDTH-1:0] quotient_signed_bits =
    dividend_neg ? (~quotient_abs_trunc + {{(QUOT_WIDTH-1){1'b0}}, 1'b1}) :
                   quotient_abs_trunc;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy <= 1'b0;
        done <= 1'b0;
        quotient <= {QUOT_WIDTH{1'b0}};
        dividend_neg <= 1'b0;
        dividend_shift <= {DIVIDEND_WIDTH{1'b0}};
        quotient_abs <= {DIVIDEND_WIDTH{1'b0}};
        remainder <= {(DIVIDEND_WIDTH+1){1'b0}};
        divisor_hold <= {DIVISOR_WIDTH{1'b0}};
        iter_count <= {ITER_WIDTH{1'b0}};
    end else begin
        done <= 1'b0;

        if (start && !busy) begin
            busy <= 1'b1;
            dividend_neg <= dividend[DIVIDEND_WIDTH-1];
            dividend_shift <= dividend_abs;
            quotient_abs <= {DIVIDEND_WIDTH{1'b0}};
            remainder <= {(DIVIDEND_WIDTH+1){1'b0}};
            divisor_hold <= divisor;
            iter_count <= {ITER_WIDTH{1'b0}};
        end else if (busy) begin
            remainder <= rem_next;
            dividend_shift <= {dividend_shift[DIVIDEND_WIDTH-2:0], 1'b0};
            quotient_abs <= quotient_shift_next;

            if (iter_count == DIVIDEND_WIDTH - 1) begin
                busy <= 1'b0;
                done <= 1'b1;
                quotient <= quotient_signed_bits;
            end else begin
                iter_count <= iter_count + {{(ITER_WIDTH-1){1'b0}}, 1'b1};
            end
        end
    end
end

endmodule
