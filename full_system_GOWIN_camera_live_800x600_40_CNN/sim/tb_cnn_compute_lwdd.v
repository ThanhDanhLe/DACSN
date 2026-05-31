`timescale 1ns/1ps

module tb_cnn_compute_lwdd;

reg clk = 1'b0;
reg rst_n = 1'b0;
always #5 clk = ~clk;

reg start;
wire busy;
wire done;
wire error;
wire output_valid;
wire [3:0] output_class;

reg input_wr_en;
reg [8:0] input_wr_addr;
reg [31:0] input_wr_data;

wire image_rd_en;
wire [9:0] image_rd_addr;
reg [15:0] image_rd_data;

wire param_req;
wire [31:0] param_word_offset;
wire [15:0] param_len_words;
reg param_ready;
reg param_done;
reg param_error;
reg [31:0] param_data;
reg param_data_valid;

wire [639:0] debug_logits_flat;
wire [5:0] debug_state;
wire [3:0] debug_op;
wire [4:0] debug_x;
wire [4:0] debug_y;
wire [4:0] debug_channel;
wire signed [63:0] debug_accumulator;

reg [31:0] param_words [0:2339];
reg [31:0] image_words [0:783];
reg [15:0] image_pixels [0:783];
reg [63:0] golden_logits [0:19];
reg [3:0] golden_classes [0:1];
reg param_streaming;
reg [31:0] param_stream_offset;
reg [15:0] param_stream_len;
reg [15:0] param_stream_count;
integer sample;
integer i;
integer timeout;
integer errors;

cnn_compute_lwdd dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .busy(busy),
    .done(done),
    .error(error),
    .output_valid(output_valid),
    .output_class(output_class),
    .input_wr_en(input_wr_en),
    .input_wr_addr(input_wr_addr),
    .input_wr_data(input_wr_data),
    .image_rd_en(image_rd_en),
    .image_rd_addr(image_rd_addr),
    .image_rd_data(image_rd_data),
    .param_req(param_req),
    .param_word_offset(param_word_offset),
    .param_len_words(param_len_words),
    .param_ready(param_ready),
    .param_done(param_done),
    .param_error(param_error),
    .param_data(param_data),
    .param_data_valid(param_data_valid),
    .debug_logits_flat(debug_logits_flat),
    .debug_state(debug_state),
    .debug_op(debug_op),
    .debug_x(debug_x),
    .debug_y(debug_y),
    .debug_channel(debug_channel),
    .debug_accumulator(debug_accumulator)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        image_rd_data <= 16'd0;
    end else if (image_rd_en) begin
        image_rd_data <= image_pixels[image_rd_addr];
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        param_ready <= 1'b1;
        param_done <= 1'b0;
        param_error <= 1'b0;
        param_data <= 32'd0;
        param_data_valid <= 1'b0;
        param_streaming <= 1'b0;
        param_stream_offset <= 32'd0;
        param_stream_len <= 16'd0;
        param_stream_count <= 16'd0;
    end else begin
        param_done <= 1'b0;
        param_data_valid <= 1'b0;
        param_ready <= !param_streaming;

        if (param_req && !param_streaming) begin
            if ((param_len_words == 16'd0) ||
                ((param_word_offset + param_len_words) > 32'd2340)) begin
                param_error <= 1'b1;
                param_done <= 1'b1;
            end else begin
                param_streaming <= 1'b1;
                param_stream_offset <= param_word_offset;
                param_stream_len <= param_len_words;
                param_stream_count <= 16'd0;
                param_ready <= 1'b0;
            end
        end else if (param_streaming) begin
            param_data <= param_words[param_stream_offset + param_stream_count];
            param_data_valid <= 1'b1;
            if ((param_stream_count + 16'd1) == param_stream_len) begin
                param_done <= 1'b1;
                param_streaming <= 1'b0;
                param_ready <= 1'b1;
            end else begin
                param_stream_count <= param_stream_count + 16'd1;
            end
        end
    end
end

function [63:0] debug_logit_word;
    input integer idx;
    begin
        case (idx)
            0: debug_logit_word = debug_logits_flat[63:0];
            1: debug_logit_word = debug_logits_flat[127:64];
            2: debug_logit_word = debug_logits_flat[191:128];
            3: debug_logit_word = debug_logits_flat[255:192];
            4: debug_logit_word = debug_logits_flat[319:256];
            5: debug_logit_word = debug_logits_flat[383:320];
            6: debug_logit_word = debug_logits_flat[447:384];
            7: debug_logit_word = debug_logits_flat[511:448];
            8: debug_logit_word = debug_logits_flat[575:512];
            default: debug_logit_word = debug_logits_flat[639:576];
        endcase
    end
endfunction

task fail;
    input [255:0] msg;
    begin
        $display("FAIL tb_cnn_compute_lwdd: %0s", msg);
        errors = errors + 1;
    end
endtask

task apply_idle_reset;
    begin
        rst_n <= 1'b0;
        start <= 1'b0;
        input_wr_en <= 1'b0;
        repeat (6) @(posedge clk);
        rst_n <= 1'b1;
        repeat (6) @(posedge clk);
    end
endtask

task preload_sample;
    input integer sample_idx;
    integer base;
    begin
        base = sample_idx * 392;
        for (i = 0; i < 392; i = i + 1) begin
            @(posedge clk);
            input_wr_en <= 1'b1;
            input_wr_addr <= i[8:0];
            input_wr_data <= image_words[base + i];
            image_pixels[{i[8:0], 1'b0}] <= {8'd0, image_words[base + i][7:0]};
            image_pixels[{i[8:0], 1'b1}] <= {8'd0, image_words[base + i][23:16]};
        end
        @(posedge clk);
        input_wr_en <= 1'b0;
        input_wr_addr <= 9'd0;
        input_wr_data <= 32'd0;
        repeat (4) @(posedge clk);
    end
endtask

task run_sample;
    input integer sample_idx;
    begin
        preload_sample(sample_idx);
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        timeout = 0;
        while (!output_valid && !error && (timeout < 120000000)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end

        if (timeout >= 120000000)
            fail("compute timeout");
        if (error)
            fail("compute error asserted");
        if (!done)
            fail("done did not pulse with output_valid");
        if (output_class !== golden_classes[sample_idx]) begin
            $display("sample=%0d got_class=%0d expected=%0d",
                     sample_idx, output_class, golden_classes[sample_idx]);
            fail("class mismatch");
        end

        for (i = 0; i < 10; i = i + 1) begin
            if (debug_logit_word(i) !== golden_logits[sample_idx * 10 + i]) begin
                $display("sample=%0d logit=%0d got=%0d expected=%0d raw_got=%016h raw_exp=%016h",
                         sample_idx, i,
                         $signed(debug_logit_word(i)),
                         $signed(golden_logits[sample_idx * 10 + i]),
                         debug_logit_word(i), golden_logits[sample_idx * 10 + i]);
                fail("logit mismatch");
            end
        end
        repeat (8) @(posedge clk);
    end
endtask

initial begin
    errors = 0;
    start = 1'b0;
    input_wr_en = 1'b0;
    input_wr_addr = 9'd0;
    input_wr_data = 32'd0;
    for (i = 0; i < 784; i = i + 1)
        image_pixels[i] = 16'd0;

    $readmemh("data/lwdd_params_words.mem", param_words);
    $readmemh("data/cnn_tb_image_words.mem", image_words);
    $readmemh("data/cnn_tb_logits.mem", golden_logits);
    $readmemh("data/cnn_tb_classes.mem", golden_classes);

    apply_idle_reset();
    apply_idle_reset();

    run_sample(0);
    run_sample(1);

    if (errors == 0)
        $display("PASS tb_cnn_compute_lwdd");
    else
        $display("FAIL tb_cnn_compute_lwdd errors=%0d", errors);
    $finish;
end

wire debug_unused = ^debug_state ^ ^debug_op ^ ^debug_x ^ ^debug_y ^
                    ^debug_channel ^ ^debug_accumulator ^ busy;

endmodule
