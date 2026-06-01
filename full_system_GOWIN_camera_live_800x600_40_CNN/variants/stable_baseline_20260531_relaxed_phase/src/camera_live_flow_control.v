`timescale 1ns/1ps

module camera_live_flow_control #(
    parameter integer KEY_DEBOUNCE_TICKS = 540000,
    parameter integer KEY_CNT_WIDTH = 20
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       key_step_n,
    input  wire       calib_done,
    input  wire       freeze_done,
    input  wire       image_done,
    input  wire       image_error,
    input  wire       nn_busy,
    input  wire       nn_output_valid,
    input  wire [3:0] nn_output_class,
    input  wire       nn_error,

    output reg        image_start,
    output reg        nn_start,
    output wire       show_mnist,
    output wire       freeze_active,
    output wire       image_process_active,
    output wire       integration_busy,
    output wire [2:0] hyperram_owner_request,
    output reg        image_preload_valid,
    output reg        result_valid,
    output reg  [3:0] result_class,
    output reg        result_error,
    output reg  [3:0] state,

    output wire       dbg_key_pressed_pulse,
    output wire       dbg_key_wait_release,
    output wire [3:0] dbg_state,
    output wire [15:0] dbg_transition_count
);

localparam [2:0]
    SEL_NONE   = 3'd0,
    SEL_VFB    = 3'd2,
    SEL_VFB_RD = 3'd5;

localparam [3:0]
    S_WAIT_CALIB      = 4'd0,
    S_CAMERA_LIVE     = 4'd1,
    S_FREEZE_FRAME    = 4'd2,
    S_IMAGE_PROCESS   = 4'd3,
    S_SHOW_MNIST_28X28= 4'd4,
    S_CNN_COMPUTE     = 4'd5,
    S_SHOW_RESULT     = 4'd6,
    S_ERROR           = 4'd7;

wire key_stable_pressed;
wire key_pressed_pulse;
wire key_released_pulse;
reg  key_wait_release;

button_debounce #(
    .ACTIVE_LOW(1),
    .DEBOUNCE_TICKS(KEY_DEBOUNCE_TICKS),
    .CNT_WIDTH(KEY_CNT_WIDTH)
) u_step_button (
    .clk(clk),
    .rst_n(rst_n),
    .button_in(key_step_n),
    .stable_pressed(key_stable_pressed),
    .pressed_pulse(key_pressed_pulse),
    .released_pulse(key_released_pulse)
);

wire key_event = key_pressed_pulse && !key_wait_release && calib_done;
wire key_event_consumed =
    key_event &&
    ((state == S_CAMERA_LIVE) ||
     ((state == S_SHOW_MNIST_28X28) && image_preload_valid && !nn_busy) ||
     (state == S_SHOW_RESULT) ||
     (state == S_ERROR));

assign show_mnist = (state == S_SHOW_MNIST_28X28);
assign freeze_active = (state == S_FREEZE_FRAME);
assign image_process_active = (state == S_IMAGE_PROCESS);
assign integration_busy = nn_busy ||
                          (state == S_FREEZE_FRAME) ||
                          (state == S_IMAGE_PROCESS) ||
                          (state == S_CNN_COMPUTE);
assign hyperram_owner_request =
    (!calib_done)                 ? SEL_NONE :
    (state == S_CAMERA_LIVE)      ? SEL_VFB  :
    (state == S_IMAGE_PROCESS)    ? SEL_VFB_RD :
                                    SEL_NONE;

assign dbg_key_pressed_pulse = key_pressed_pulse;
assign dbg_key_wait_release = key_wait_release;
assign dbg_state = state;
assign dbg_transition_count = 16'd0;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        key_wait_release <= 1'b0;
    end else if (key_released_pulse || !key_stable_pressed) begin
        key_wait_release <= 1'b0;
    end else if (key_event_consumed) begin
        key_wait_release <= 1'b1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_WAIT_CALIB;
        image_start <= 1'b0;
        nn_start <= 1'b0;
        image_preload_valid <= 1'b0;
        result_valid <= 1'b0;
        result_class <= 4'hF;
        result_error <= 1'b0;
    end else begin
        image_start <= 1'b0;
        nn_start <= 1'b0;

        if (!calib_done) begin
            state <= S_WAIT_CALIB;
            image_preload_valid <= 1'b0;
            result_valid <= 1'b0;
            result_class <= 4'hF;
            result_error <= 1'b0;
        end else begin
            case (state)
                S_WAIT_CALIB: begin
                    image_preload_valid <= 1'b0;
                    result_valid <= 1'b0;
                    result_class <= 4'hF;
                    result_error <= 1'b0;
                    state <= S_CAMERA_LIVE;
                end

                S_CAMERA_LIVE: begin
                    image_preload_valid <= 1'b0;
                    result_valid <= 1'b0;
                    result_class <= 4'hF;
                    result_error <= 1'b0;
                    if (key_event)
                        state <= S_FREEZE_FRAME;
                end

                S_FREEZE_FRAME: begin
                    if (freeze_done) begin
                        image_start <= 1'b1;
                        state <= S_IMAGE_PROCESS;
                    end
                end

                S_IMAGE_PROCESS: begin
                    if (image_done) begin
                        image_preload_valid <= 1'b1;
                        result_valid <= 1'b0;
                        result_error <= 1'b0;
                        state <= S_SHOW_MNIST_28X28;
                    end else if (image_error) begin
                        image_preload_valid <= 1'b0;
                        result_valid <= 1'b0;
                        result_class <= 4'hF;
                        result_error <= 1'b1;
                        state <= S_SHOW_RESULT;
                    end
                end

                S_SHOW_MNIST_28X28: begin
                    if (!image_preload_valid) begin
                        result_error <= 1'b1;
                        state <= S_ERROR;
                    end else if (key_event && !nn_busy) begin
                        nn_start <= 1'b1;
                        state <= S_CNN_COMPUTE;
                    end
                end

                S_CNN_COMPUTE: begin
                    if (nn_output_valid) begin
                        result_valid <= 1'b1;
                        result_class <= nn_output_class;
                        result_error <= 1'b0;
                        state <= S_SHOW_RESULT;
                    end else if (nn_error) begin
                        result_valid <= 1'b0;
                        result_class <= 4'hF;
                        result_error <= 1'b1;
                        state <= S_SHOW_RESULT;
                    end
                end

                S_SHOW_RESULT: begin
                    if (key_event) begin
                        image_preload_valid <= 1'b0;
                        result_valid <= 1'b0;
                        result_class <= 4'hF;
                        result_error <= 1'b0;
                        state <= S_CAMERA_LIVE;
                    end
                end

                S_ERROR: begin
                    result_error <= 1'b1;
                    if (key_event) begin
                        image_preload_valid <= 1'b0;
                        result_valid <= 1'b0;
                        result_class <= 4'hF;
                        result_error <= 1'b0;
                        state <= S_CAMERA_LIVE;
                    end
                end

                default: begin
                    result_error <= 1'b1;
                    state <= S_ERROR;
                end
            endcase
        end
    end
end

endmodule
