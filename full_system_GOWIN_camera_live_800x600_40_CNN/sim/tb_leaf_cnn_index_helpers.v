`timescale 1ns/1ps

module tb_leaf_cnn_index_helpers;

reg [8:0] idx;
reg group;
reg [4:0] out_ch;
reg [1:0] ky;
reg [1:0] kx;
reg [4:0] cin;
reg [4:0] cout;
reg [4:0] dense_in_idx;
reg [3:0] dense_out_idx;
wire [11:0] c5_word_offset;
wire [11:0] conv6_word_offset;
wire [8:0] c5_cache_word;
wire [10:0] scalar_c5;
wire [10:0] scalar_c1;
wire [10:0] scalar_c2;
wire [10:0] scalar_dense;

integer errors;
integer idx_i;
integer group_i;
integer out_ch_i;
integer ky_i;
integer kx_i;
integer cin_i;
integer cout_i;
integer dense_in_i;
integer dense_out_i;
integer seed;

leaf_c5_word_offset u_c5_word_offset (
    .idx(idx),
    .group(group),
    .word_offset(c5_word_offset)
);

leaf_conv6_word_offset u_conv6_word_offset (
    .idx(idx),
    .out_ch(out_ch),
    .word_offset(conv6_word_offset)
);

leaf_c5_cache_word u_c5_cache_word (
    .ky(ky),
    .kx(kx),
    .cin(cin),
    .cout(cout),
    .cache_word(c5_cache_word)
);

leaf_scalar_c5 u_scalar_c5 (
    .ky(ky),
    .kx(kx),
    .cin(cin),
    .cout(cout),
    .scalar(scalar_c5)
);

leaf_scalar_c1 u_scalar_c1 (
    .ky(ky),
    .kx(kx),
    .cout(cout),
    .scalar(scalar_c1)
);

leaf_scalar_c2 u_scalar_c2 (
    .ky(ky),
    .kx(kx),
    .cin(cin),
    .cout(cout),
    .scalar(scalar_c2)
);

leaf_scalar_dense u_scalar_dense (
    .in_idx(dense_in_idx),
    .out_idx(dense_out_idx),
    .scalar(scalar_dense)
);

function [11:0] ref_c5_word_offset;
    input [8:0] f_idx;
    input f_group;
    reg [6:0] block_idx;
    begin
        block_idx = f_idx[8:2];
        ref_c5_word_offset = 12'd522 + {2'd0, block_idx, 3'b000} +
                             {9'd0, f_group, 2'b00} + {10'd0, f_idx[1:0]};
    end
endfunction

function [11:0] ref_conv6_word_offset;
    input [8:0] f_idx;
    input [4:0] f_out_ch;
    reg [11:0] scalar;
    begin
        scalar = {f_idx[7:0], 4'b0000} + {7'd0, f_out_ch};
        ref_conv6_word_offset = 12'd1098 + scalar[11:1];
    end
endfunction

function [8:0] ref_c5_cache_word;
    input [1:0] f_ky;
    input [1:0] f_kx;
    input [4:0] f_cin;
    input [4:0] f_cout;
    reg [3:0] kk;
    reg [6:0] block_idx;
    begin
        kk = {1'b0, f_ky} + {f_ky, 1'b0} + {2'b00, f_kx};
        block_idx = {kk, 3'b000} + f_cin[2:0];
        ref_c5_cache_word = {block_idx, 2'b00} + {7'd0, f_cout[2:1]};
    end
endfunction

function [10:0] ref_scalar_c2;
    input [1:0] f_ky;
    input [1:0] f_kx;
    input [4:0] f_cin;
    input [4:0] f_cout;
    reg [3:0] kk;
    begin
        kk = {1'b0, f_ky} + {f_ky, 1'b0} + {2'b00, f_kx};
        ref_scalar_c2 = {3'd0, kk, 4'b0000} + {4'd0, f_cin, 2'b00} + {6'd0, f_cout};
    end
endfunction

function [10:0] ref_scalar_c1;
    input [1:0] f_ky;
    input [1:0] f_kx;
    input [4:0] f_cout;
    reg [3:0] kk;
    begin
        kk = {1'b0, f_ky} + {f_ky, 1'b0} + {2'b00, f_kx};
        ref_scalar_c1 = {5'd0, kk, 2'b00} + {6'd0, f_cout};
    end
endfunction

function [10:0] ref_scalar_c5;
    input [1:0] f_ky;
    input [1:0] f_kx;
    input [4:0] f_cin;
    input [4:0] f_cout;
    reg [3:0] kk;
    begin
        kk = {1'b0, f_ky} + {f_ky, 1'b0} + {2'b00, f_kx};
        ref_scalar_c5 = {kk, 7'b0000000} + {2'd0, f_cin, 4'b0000} + {6'd0, f_cout};
    end
endfunction

function [10:0] ref_scalar_dense;
    input [4:0] f_in_idx;
    input [3:0] f_out_idx;
    begin
        ref_scalar_dense = {f_in_idx, 3'b000} + {f_in_idx, 1'b0} +
                           {7'd0, f_out_idx};
    end
endfunction

task check;
    input condition;
    input [8*64-1:0] msg;
    begin
        if (!condition) begin
            errors = errors + 1;
            $display("FAIL %0s", msg);
        end
    end
endtask

task check_c5;
    input [8:0] t_idx;
    input t_group;
    begin
        idx = t_idx;
        group = t_group;
        #1;
        check(c5_word_offset === ref_c5_word_offset(t_idx, t_group),
              "c5 word offset");
    end
endtask

task check_conv6;
    input [8:0] t_idx;
    input [4:0] t_out_ch;
    begin
        idx = t_idx;
        out_ch = t_out_ch;
        #1;
        check(conv6_word_offset === ref_conv6_word_offset(t_idx, t_out_ch),
              "conv6 word offset");
    end
endtask

task check_c5_cache_word;
    input [1:0] t_ky;
    input [1:0] t_kx;
    input [4:0] t_cin;
    input [4:0] t_cout;
    begin
        ky = t_ky;
        kx = t_kx;
        cin = t_cin;
        cout = t_cout;
        #1;
        check(c5_cache_word === ref_c5_cache_word(t_ky, t_kx, t_cin, t_cout),
              "c5 cache word");
    end
endtask

task check_scalar_c2;
    input [1:0] t_ky;
    input [1:0] t_kx;
    input [4:0] t_cin;
    input [4:0] t_cout;
    begin
        ky = t_ky;
        kx = t_kx;
        cin = t_cin;
        cout = t_cout;
        #1;
        check(scalar_c2 === ref_scalar_c2(t_ky, t_kx, t_cin, t_cout),
              "scalar c2");
    end
endtask

task check_scalar_c1;
    input [1:0] t_ky;
    input [1:0] t_kx;
    input [4:0] t_cout;
    begin
        ky = t_ky;
        kx = t_kx;
        cout = t_cout;
        #1;
        check(scalar_c1 === ref_scalar_c1(t_ky, t_kx, t_cout),
              "scalar c1");
    end
endtask

task check_scalar_c5;
    input [1:0] t_ky;
    input [1:0] t_kx;
    input [4:0] t_cin;
    input [4:0] t_cout;
    begin
        ky = t_ky;
        kx = t_kx;
        cin = t_cin;
        cout = t_cout;
        #1;
        check(scalar_c5 === ref_scalar_c5(t_ky, t_kx, t_cin, t_cout),
              "scalar c5");
    end
endtask

task check_scalar_dense;
    input [4:0] t_in_idx;
    input [3:0] t_out_idx;
    begin
        dense_in_idx = t_in_idx;
        dense_out_idx = t_out_idx;
        #1;
        check(scalar_dense === ref_scalar_dense(t_in_idx, t_out_idx),
              "scalar dense");
    end
endtask

initial begin
    errors = 0;
    seed = 32'h5eed1234;

    check_c5(9'd0, 1'b0);
    check_c5(9'd0, 1'b1);
    check_c5(9'd287, 1'b0);
    check_c5(9'd287, 1'b1);
    check_c5(9'd3, 1'b0);
    check_c5(9'd4, 1'b1);

    for (group_i = 0; group_i < 2; group_i = group_i + 1) begin
        for (idx_i = 0; idx_i < 288; idx_i = idx_i + 1) begin
            check_c5(idx_i[8:0], group_i[0]);
        end
    end

    check_conv6(9'd0, 5'd0);
    check_conv6(9'd0, 5'd15);
    check_conv6(9'd143, 5'd0);
    check_conv6(9'd143, 5'd15);
    check_conv6(9'd1, 5'd1);

    for (out_ch_i = 0; out_ch_i < 16; out_ch_i = out_ch_i + 1) begin
        for (idx_i = 0; idx_i < 144; idx_i = idx_i + 1) begin
            check_conv6(idx_i[8:0], out_ch_i[4:0]);
        end
    end

    for (idx_i = 0; idx_i < 64; idx_i = idx_i + 1) begin
        check_c5(($random(seed) % 288), ($random(seed) & 1));
        check_conv6(($random(seed) % 144), ($random(seed) & 5'h0f));
    end

    check_c5_cache_word(2'd0, 2'd0, 5'd0, 5'd0);
    check_c5_cache_word(2'd2, 2'd2, 5'd7, 5'd15);
    check_c5_cache_word(2'd0, 2'd1, 5'd0, 5'd2);
    check_c5_cache_word(2'd1, 2'd0, 5'd7, 5'd3);

    for (ky_i = 0; ky_i < 3; ky_i = ky_i + 1) begin
        for (kx_i = 0; kx_i < 3; kx_i = kx_i + 1) begin
            for (cin_i = 0; cin_i < 8; cin_i = cin_i + 1) begin
                for (cout_i = 0; cout_i < 16; cout_i = cout_i + 1) begin
                    check_c5_cache_word(ky_i[1:0], kx_i[1:0],
                                        cin_i[4:0], cout_i[4:0]);
                end
            end
        end
    end

    for (idx_i = 0; idx_i < 64; idx_i = idx_i + 1) begin
        check_c5_cache_word(($random(seed) & 2'h3), ($random(seed) & 2'h3),
                            ($random(seed) & 5'h1f), ($random(seed) & 5'h1f));
    end

    check_scalar_c5(2'd0, 2'd0, 5'd0, 5'd0);
    check_scalar_c5(2'd2, 2'd2, 5'd7, 5'd15);
    check_scalar_c5(2'd0, 2'd1, 5'd0, 5'd1);
    check_scalar_c5(2'd1, 2'd0, 5'd7, 5'd14);

    for (ky_i = 0; ky_i < 3; ky_i = ky_i + 1) begin
        for (kx_i = 0; kx_i < 3; kx_i = kx_i + 1) begin
            for (cin_i = 0; cin_i < 8; cin_i = cin_i + 1) begin
                for (cout_i = 0; cout_i < 16; cout_i = cout_i + 1) begin
                    check_scalar_c5(ky_i[1:0], kx_i[1:0],
                                    cin_i[4:0], cout_i[4:0]);
                end
            end
        end
    end

    for (idx_i = 0; idx_i < 64; idx_i = idx_i + 1) begin
        check_scalar_c5(($random(seed) & 2'h3), ($random(seed) & 2'h3),
                        ($random(seed) & 5'h1f), ($random(seed) & 5'h1f));
    end

    check_scalar_c1(2'd0, 2'd0, 5'd0);
    check_scalar_c1(2'd2, 2'd2, 5'd3);
    check_scalar_c1(2'd1, 2'd0, 5'd1);

    for (ky_i = 0; ky_i < 3; ky_i = ky_i + 1) begin
        for (kx_i = 0; kx_i < 3; kx_i = kx_i + 1) begin
            for (cout_i = 0; cout_i < 4; cout_i = cout_i + 1) begin
                check_scalar_c1(ky_i[1:0], kx_i[1:0], cout_i[4:0]);
            end
        end
    end

    for (idx_i = 0; idx_i < 64; idx_i = idx_i + 1) begin
        check_scalar_c1(($random(seed) & 2'h3), ($random(seed) & 2'h3),
                        ($random(seed) & 5'h1f));
    end

    check_scalar_c2(2'd0, 2'd0, 5'd0, 5'd0);
    check_scalar_c2(2'd2, 2'd2, 5'd3, 5'd3);
    check_scalar_c2(2'd1, 2'd0, 5'd1, 5'd2);

    for (ky_i = 0; ky_i < 3; ky_i = ky_i + 1) begin
        for (kx_i = 0; kx_i < 3; kx_i = kx_i + 1) begin
            for (cin_i = 0; cin_i < 4; cin_i = cin_i + 1) begin
                for (cout_i = 0; cout_i < 4; cout_i = cout_i + 1) begin
                    check_scalar_c2(ky_i[1:0], kx_i[1:0],
                                    cin_i[4:0], cout_i[4:0]);
                end
            end
        end
    end

    for (idx_i = 0; idx_i < 64; idx_i = idx_i + 1) begin
        check_scalar_c2(($random(seed) & 2'h3), ($random(seed) & 2'h3),
                        ($random(seed) & 5'h1f), ($random(seed) & 5'h1f));
    end

    check_scalar_dense(5'd0, 4'd0);
    check_scalar_dense(5'd15, 4'd9);
    check_scalar_dense(5'd1, 4'd1);

    for (dense_in_i = 0; dense_in_i < 16; dense_in_i = dense_in_i + 1) begin
        for (dense_out_i = 0; dense_out_i < 10; dense_out_i = dense_out_i + 1) begin
            check_scalar_dense(dense_in_i[4:0], dense_out_i[3:0]);
        end
    end

    for (idx_i = 0; idx_i < 64; idx_i = idx_i + 1) begin
        check_scalar_dense(($random(seed) & 5'h1f), ($random(seed) & 4'hf));
    end

    if (errors == 0)
        $display("PASS tb_leaf_cnn_index_helpers");
    else
        $display("FAIL tb_leaf_cnn_index_helpers errors=%0d", errors);
    $finish;
end

endmodule
