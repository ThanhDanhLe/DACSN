`timescale 1ns/1ps

module tb_camera_live_state_flow;

localparam [3:0]
    S_WAIT_CALIB       = 4'd0,
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
reg nn_busy;
reg nn_output_valid;
reg [3:0] nn_output_class;
reg nn_error;

wire image_start;
wire nn_start;
wire show_mnist;
wire freeze_active;
wire image_process_active;
wire integration_busy;
wire [2:0] hyperram_owner_request;
wire image_preload_valid;
wire result_valid;
wire [3:0] result_class;
wire result_error;
wire [3:0] state;
wire dbg_key_pressed_pulse;
wire dbg_key_wait_release;
wire [3:0] dbg_state;
wire [15:0] dbg_transition_count;

integer errors;
integer i;
integer nn_start_seen;

camera_live_flow_control #(
    .KEY_DEBOUNCE_TICKS(4),
    .KEY_CNT_WIDTH(4)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .key_step_n(key_step_n),
    .calib_done(calib_done),
    .freeze_done(freeze_done),
    .image_done(image_done),
    .image_error(image_error),
    .nn_busy(nn_busy),
    .nn_output_valid(nn_output_valid),
    .nn_output_class(nn_output_class),
    .nn_error(nn_error),
    .image_start(image_start),
    .nn_start(nn_start),
    .show_mnist(show_mnist),
    .freeze_active(freeze_active),
    .image_process_active(image_process_active),
    .integration_busy(integration_busy),
    .hyperram_owner_request(hyperram_owner_request),
    .image_preload_valid(image_preload_valid),
    .result_valid(result_valid),
    .result_class(result_class),
    .result_error(result_error),
    .state(state),
    .dbg_key_pressed_pulse(dbg_key_pressed_pulse),
    .dbg_key_wait_release(dbg_key_wait_release),
    .dbg_state(dbg_state),
    .dbg_transition_count(dbg_transition_count)
);

always @(posedge clk) begin
    if (nn_start)
        nn_start_seen = nn_start_seen + 1;
end

task fail;
    input [255:0] msg;
    begin
        $fwrite(out_file, "FAIL tb_camera_live_state_flow: %0s\n", msg);
        $display("FAIL tb_camera_live_state_flow: %0s", msg);
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

task stable_press_hold;
    begin
        @(negedge clk);
        key_step_n = 1'b0;
        wait_cycles(12);
    end
endtask

task stable_release;
    begin
        @(negedge clk);
        key_step_n = 1'b1;
        wait_cycles(12);
    end
endtask

task bounce_without_press;
    begin
        for (i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            key_step_n = 1'b0;
            @(negedge clk);
            key_step_n = 1'b1;
        end
        wait_cycles(8);
    end
endtask

task pulse_freeze_done;
    begin
        @(negedge clk);
        freeze_done = 1'b1;
        @(posedge clk);
        #1;
        if (!image_start)
            fail("image_start was not a one-cycle pulse from freeze_done");
        @(negedge clk);
        freeze_done = 1'b0;
        @(posedge clk);
        #1;
        if (image_start)
            fail("image_start repeated after freeze_done");
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

integer out_file;

initial begin
    errors = 0;
    nn_start_seen = 0;
    key_step_n = 1'b1;
    calib_done = 1'b0;
    freeze_done = 1'b0;
    image_done = 1'b0;
    image_error = 1'b0;
    nn_busy = 1'b0;
    nn_output_valid = 1'b0;
    nn_output_class = 4'd0;
    nn_error = 1'b0;
    
    out_file = $fopen("tb_state_flow_result.txt", "w");
    if (!out_file) begin
        $display("ERROR: Cannot open output file");
        $finish;
    end

    wait_cycles(4);
    rst_n = 1'b1;
    wait_cycles(4);
    if (state !== S_WAIT_CALIB)
        fail("reset did not enter S_WAIT_CALIB");

    calib_done = 1'b1;
    wait_cycles(4);
    if (state !== S_CAMERA_LIVE)
        fail("calibration did not enter S_CAMERA_LIVE");

    bounce_without_press();
    if (state !== S_CAMERA_LIVE)
        fail("short key bounce changed state");

    stable_press_hold();
    if (state !== S_FREEZE_FRAME)
        fail("first stable key did not enter S_FREEZE_FRAME");

    wait_cycles(1000);
    if (state !== S_FREEZE_FRAME)
        fail("long held key advanced more than one state before freeze_done");

    pulse_freeze_done();
    if (state !== S_IMAGE_PROCESS)
        fail("freeze_done did not enter S_IMAGE_PROCESS");

    pulse_image_done();
    if (state !== S_SHOW_MNIST_28X28)
        fail("image_done did not enter S_SHOW_MNIST_28X28");
    if (!show_mnist || !image_preload_valid)
        fail("preview state did not latch ready/show_mnist");

    wait_cycles(1000);
    if (state !== S_SHOW_MNIST_28X28)
        fail("held first key advanced preview to CNN");
    if (nn_start_seen != 0)
        fail("CNN started before key release and new key press");

    stable_release();
    if (dbg_key_wait_release)
        fail("key wait-release did not clear after release");

    stable_press_hold();
    if (state !== S_CNN_COMPUTE)
        fail("second key did not enter S_CNN_COMPUTE");
    if (nn_start_seen != 1)
        fail("second key did not create exactly one nn_start pulse");
    stable_release();

    @(negedge clk);
    nn_output_class = 4'd7;
    nn_output_valid = 1'b1;
    @(posedge clk);
    @(negedge clk);
    nn_output_valid = 1'b0;
    @(posedge clk);
    if (state !== S_SHOW_RESULT)
        fail("CNN output_valid did not enter S_SHOW_RESULT");
    if (!result_valid || (result_class !== 4'd7))
        fail("result class was not latched");

    stable_press_hold();
    if (state !== S_CAMERA_LIVE)
        fail("result key did not return to S_CAMERA_LIVE");
    wait_cycles(1000);
    if (state !== S_CAMERA_LIVE)
        fail("long held result key advanced more than one state");

    if (errors == 0) begin
        $fwrite(out_file, "PASS tb_camera_live_state_flow\n");
        $display("PASS tb_camera_live_state_flow");
    end else begin
        $fwrite(out_file, "FAIL tb_camera_live_state_flow errors=%0d\n", errors);
        $display("FAIL tb_camera_live_state_flow errors=%0d", errors);
    end
    $fclose(out_file);
    $finish;
end

wire unused = freeze_active ^ image_process_active ^ integration_busy ^
              ^hyperram_owner_request ^ dbg_key_pressed_pulse ^
              ^dbg_state ^ ^dbg_transition_count ^ result_error;

endmodule
