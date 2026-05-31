`timescale 1ns/1ps

module tb_cnn_reduced_top_integration;

localparam [3:0]
    S_CAMERA_LIVE      = 4'd1,
    S_FREEZE_FRAME     = 4'd2,
    S_IMAGE_PROCESS    = 4'd3,
    S_SHOW_MNIST_28X28 = 4'd4,
    S_CNN_COMPUTE      = 4'd5,
    S_SHOW_RESULT      = 4'd6;

reg clk = 1'b0;
reg rst_n = 1'b0;
always #5 clk = ~clk;

reg key_step_n;
reg calib_done;
reg freeze_done;
reg image_done;
reg image_error;
wire image_start;
wire nn_start;
wire show_mnist;
wire freeze_active;
wire image_process_active;
wire integration_busy;
wire [2:0] hyperram_owner_request;
wire image_preload_valid;
wire result_valid_latched;
wire [3:0] result_class_latched;
wire result_error_latched;
wire [3:0] flow_state;

wire flash_cs_n;
wire flash_sclk;
wire flash_mosi;
wire flash_miso;
wire flash_command_error;
wire cnn_busy;
wire cnn_done;
wire cnn_output_valid;
wire [3:0] cnn_output_class;
wire cnn_error;
wire image_rd_en;
wire [9:0] image_rd_addr;
reg [15:0] image_rd_data;

reg [15:0] mnist_ram [0:783];
reg [31:0] image_words [0:783];
reg [3:0] golden_classes [0:1];
integer i;
integer timeout;
integer errors;
integer nn_start_seen;
integer image_start_seen;

camera_live_flow_control #(
    .KEY_DEBOUNCE_TICKS(3),
    .KEY_CNT_WIDTH(4)
) u_flow (
    .clk(clk),
    .rst_n(rst_n),
    .key_step_n(key_step_n),
    .calib_done(calib_done),
    .freeze_done(freeze_done),
    .image_done(image_done),
    .image_error(image_error),
    .nn_busy(cnn_busy),
    .nn_output_valid(cnn_output_valid),
    .nn_output_class(cnn_output_class),
    .nn_error(cnn_error),
    .image_start(image_start),
    .nn_start(nn_start),
    .show_mnist(show_mnist),
    .freeze_active(freeze_active),
    .image_process_active(image_process_active),
    .integration_busy(integration_busy),
    .hyperram_owner_request(hyperram_owner_request),
    .image_preload_valid(image_preload_valid),
    .result_valid(result_valid_latched),
    .result_class(result_class_latched),
    .result_error(result_error_latched),
    .state(flow_state),
    .dbg_key_pressed_pulse(),
    .dbg_key_wait_release(),
    .dbg_state(),
    .dbg_transition_count()
);

cnn_system #(
    .ACT_ADDR_WIDTH(9),
    .SPI_DIV(1),
    .FLASH_PARAM_BASE(24'h200000)
) u_cnn_system (
    .clk(clk),
    .rst_n(rst_n),
    .start(nn_start),
    .memory_ready(1'b1),
    .image_rd_en(image_rd_en),
    .image_rd_addr(image_rd_addr),
    .image_rd_data(image_rd_data),
    .image_preload_valid(image_preload_valid),
    .image_preload_wr_en(1'b0),
    .image_preload_wr_addr(9'd0),
    .image_preload_wr_data(32'd0),
    .flash_cs_n(flash_cs_n),
    .flash_sclk(flash_sclk),
    .flash_mosi(flash_mosi),
    .flash_miso(flash_miso),
    .busy(cnn_busy),
    .done(cnn_done),
    .output_valid(cnn_output_valid),
    .output_class(cnn_output_class),
    .error(cnn_error)
);

cnn_spi_flash_param_model u_flash (
    .flash_cs_n(flash_cs_n),
    .flash_sclk(flash_sclk),
    .flash_mosi(flash_mosi),
    .flash_miso(flash_miso),
    .command_error(flash_command_error)
);

always @(posedge clk) begin
    if (image_rd_en)
        image_rd_data <= mnist_ram[image_rd_addr];
    if (nn_start)
        nn_start_seen = nn_start_seen + 1;
    if (image_start)
        image_start_seen = image_start_seen + 1;
end

task fail;
    input [255:0] msg;
    begin
        $display("FAIL tb_cnn_reduced_top_integration: %0s", msg);
        errors = errors + 1;
    end
endtask

task wait_cycles;
    input integer count;
    begin
        for (i = 0; i < count; i = i + 1)
            @(posedge clk);
    end
endtask

task press_and_release_key;
    begin
        @(negedge clk);
        key_step_n = 1'b0;
        wait_cycles(10);
        @(negedge clk);
        key_step_n = 1'b1;
        wait_cycles(10);
    end
endtask

task pulse_freeze_done;
    begin
        @(negedge clk);
        freeze_done = 1'b1;
        @(posedge clk);
        @(negedge clk);
        freeze_done = 1'b0;
        @(posedge clk);
    end
endtask

task pulse_image_done;
    begin
        @(negedge clk);
        image_done = 1'b1;
        @(posedge clk);
        @(negedge clk);
        image_done = 1'b0;
        @(posedge clk);
    end
endtask

initial begin
    errors = 0;
    nn_start_seen = 0;
    image_start_seen = 0;
    key_step_n = 1'b1;
    calib_done = 1'b1;
    freeze_done = 1'b0;
    image_done = 1'b0;
    image_error = 1'b0;
    image_rd_data = 16'd0;
    $readmemh("data/cnn_tb_image_words.mem", image_words);
    $readmemh("data/cnn_tb_classes.mem", golden_classes);

    for (i = 0; i < 392; i = i + 1) begin
        mnist_ram[(2 * i) + 0] = {8'd0, image_words[i][7:0]};
        mnist_ram[(2 * i) + 1] = {8'd0, image_words[i][23:16]};
    end

    repeat (8) @(posedge clk);
    rst_n <= 1'b1;
    repeat (8) @(posedge clk);

    if (flow_state !== S_CAMERA_LIVE)
        fail("FSM did not enter S_CAMERA_LIVE after reset/calib");

    press_and_release_key();
    if (flow_state !== S_FREEZE_FRAME)
        fail("first key did not enter S_FREEZE_FRAME");

    pulse_freeze_done();
    if (flow_state !== S_IMAGE_PROCESS)
        fail("freeze_done did not enter S_IMAGE_PROCESS");
    if (image_start_seen != 1)
        fail("image_start pulse missing");

    pulse_image_done();
    repeat (8) @(posedge clk);
    if (flow_state !== S_SHOW_MNIST_28X28)
        fail("image_done did not enter S_SHOW_MNIST_28X28");
    if (!show_mnist || !image_preload_valid)
        fail("preview did not latch image_preload_valid");
    if (cnn_busy || (nn_start_seen != 0))
        fail("CNN started before preview key press");

    repeat (32) @(posedge clk);
    if (flow_state !== S_SHOW_MNIST_28X28)
        fail("preview state advanced without a new key");

    press_and_release_key();
    if (flow_state !== S_CNN_COMPUTE)
        fail("second key did not enter S_CNN_COMPUTE");
    if (nn_start_seen != 1)
        fail("second key did not create exactly one CNN start");

    timeout = 0;
    while (!result_valid_latched && !result_error_latched && (timeout < 160000000)) begin
        @(posedge clk);
        timeout = timeout + 1;
    end

    if (timeout >= 160000000)
        fail("integration timeout");
    if (result_error_latched || cnn_error)
        fail("CNN error latched");
    if (flow_state !== S_SHOW_RESULT)
        fail("FSM did not enter S_SHOW_RESULT");
    if (result_class_latched !== golden_classes[0]) begin
        $display("got_class=%0d expected=%0d", result_class_latched, golden_classes[0]);
        fail("result class latch mismatch");
    end
    if (flash_command_error)
        fail("flash model saw a non-fast-read command");

    if (errors == 0)
        $display("PASS tb_cnn_reduced_top_integration");
    else
        $display("FAIL tb_cnn_reduced_top_integration errors=%0d", errors);
    $finish;
end

wire unused = ^image_rd_addr ^ cnn_done ^ freeze_active ^
              image_process_active ^ integration_busy ^
              ^hyperram_owner_request;

endmodule
