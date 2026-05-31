# Draft SDC for camera_live_top.
# Minimal constraints for P&R bring-up.
# Generated/internal PLL clock net names must be confirmed after synthesis.

create_clock -name I_clk -period 37.037 -waveform {0 18.518} [get_ports {I_clk}]
create_clock -name PIXCLK -period 41.667 [get_ports {PIXCLK}]

# In this stripped branch the top-level pix_clk observation wire is optimized
# away, so constrain the CLKDIV output that drives camera_video's pix_clk_int.
create_clock -name pix_clk -period 25.000 -waveform {0 12.500} [get_pins {u_camera_video/g_hw.u_clkdiv/CLKOUT}]

# Disabled because current netlist has no object named serial_clk.
# Need to inspect post-synthesis netlist/clock report for the real TMDS serial clock name.
# create_clock -name serial_clk -period 2.694 -waveform {0 1.347} [get_nets {serial_clk}]

# The MNIST preview uses u_mnist28_row_cache_bridge. The pix_clk side holds a
# row request while the I_clk side reads the MNIST dual-clock buffer, then
# returns one cached pixel through a toggle handshake. Keep timing explicit
# unless post-route reports show these deliberate CDC nets as violations.

# Async reset release from camera_video's I_clk reset synchronizer fans into
# generated HDMI/HyperRAM/pix domains. Treat it as reset distribution, not data.
set_false_path -from [get_pins {u_camera_video/g_hw.u_reset_sync/sync_pipe_3_s0/Q}]

# Targeted pulse-sync CDC first stages. Later sync stages remain timed.
set_false_path -from [get_pins {u_image_start_sync/src_toggle_s1/Q}] -to [get_pins {u_image_start_sync/dst_meta_s0/D}]
set_false_path -from [get_pins {u_image_done_sync/src_toggle_s1/Q}] -to [get_pins {u_image_done_sync/dst_meta_s0/D}]
set_false_path -from [get_pins {u_image_error_sync/src_toggle_s1/Q}] -to [get_pins {u_image_error_sync/dst_meta_s0/D}]
set_false_path -to [get_pins {show_mnist_pix_sync_0_s0/D}]

# MNIST preview bridge held-bus CDC. req_x/req_y are held stable while the
# req_toggle handshake is observed in I_clk.
set_false_path -from [get_pins {u_mnist28_row_cache_bridge/req_toggle_pix_s1/Q}] -to [get_pins {u_mnist28_row_cache_bridge/req_toggle_sync_i_0_s0/D}]
set_false_path -from [get_pins {u_mnist28_row_cache_bridge/req_x_pix_0_s1/Q}] -to [get_pins {u_mnist28_row_cache_bridge/i_req_x_0_s0/D}]
set_false_path -from [get_pins {u_mnist28_row_cache_bridge/req_x_pix_1_s1/Q}] -to [get_pins {u_mnist28_row_cache_bridge/i_req_x_1_s0/D}]
set_false_path -from [get_pins {u_mnist28_row_cache_bridge/req_x_pix_2_s1/Q}] -to [get_pins {u_mnist28_row_cache_bridge/i_req_x_2_s0/D}]
set_false_path -from [get_pins {u_mnist28_row_cache_bridge/req_x_pix_3_s1/Q}] -to [get_pins {u_mnist28_row_cache_bridge/i_req_x_3_s0/D}]
set_false_path -from [get_pins {u_mnist28_row_cache_bridge/req_x_pix_4_s1/Q}] -to [get_pins {u_mnist28_row_cache_bridge/i_req_x_4_s0/D}]
set_false_path -from [get_pins {u_mnist28_row_cache_bridge/req_y_pix_0_s1/Q}] -to [get_pins {u_mnist28_row_cache_bridge/i_req_y_0_s0/D}]
set_false_path -from [get_pins {u_mnist28_row_cache_bridge/req_y_pix_1_s1/Q}] -to [get_pins {u_mnist28_row_cache_bridge/i_req_y_1_s0/D}]
set_false_path -from [get_pins {u_mnist28_row_cache_bridge/req_y_pix_2_s1/Q}] -to [get_pins {u_mnist28_row_cache_bridge/i_req_y_2_s0/D}]
set_false_path -from [get_pins {u_mnist28_row_cache_bridge/req_y_pix_3_s1/Q}] -to [get_pins {u_mnist28_row_cache_bridge/i_req_y_3_s0/D}]
set_false_path -from [get_pins {u_mnist28_row_cache_bridge/req_y_pix_4_s1/Q}] -to [get_pins {u_mnist28_row_cache_bridge/i_req_y_4_s0/D}]
set_false_path -from [get_pins {u_mnist28_row_cache_bridge/done_toggle_i_s1/Q}] -to [get_pins {u_mnist28_row_cache_bridge/done_toggle_sync_pix_0_s0/D}]
set_false_path -from [get_pins {u_mnist28_row_cache_bridge/done_data_i_*_s1/Q}] -to [get_pins {u_mnist28_row_cache_bridge/cache0_data_pix_*_s0/D}]
set_false_path -from [get_pins {u_mnist28_row_cache_bridge/done_data_i_*_s1/Q}] -to [get_pins {u_mnist28_row_cache_bridge/cache1_data_pix_*_s0/D}]

# HyperRAM/pix status sampled into I_clk by explicit multi-flop synchronizers.
set_false_path -to [get_pins {u_camera_video/g_hw.u_hyperram_mode_mux/owner_meta_0_s0/D}]
set_false_path -to [get_pins {u_camera_video/g_hw.u_hyperram_mode_mux/owner_meta_1_s0/D}]
set_false_path -to [get_pins {vfb_halt_sync_i_0_s0/D}]
set_false_path -to [get_pins {owner_none_sync_i_0_s0/D}]

# Targeted display-result CDC exceptions:
# NN result/status are produced in I_clk and feed only first-stage
# two-flop synchronizers inside camera_video's pix_clk HDMI overlay.
# The second sync stage and HDMI datapath remain timed normally.
set_false_path -to [get_pins {u_camera_video/g_hw.result_valid_pix0_s0/D}]
set_false_path -to [get_pins {u_camera_video/g_hw.result_busy_pix0_s0/D}]
set_false_path -to [get_pins {u_camera_video/g_hw.result_error_pix0_s0/D}]
set_false_path -to [get_pins {u_camera_video/g_hw.result_class_pix0_0_s0/D}]
set_false_path -to [get_pins {u_camera_video/g_hw.result_class_pix0_1_s0/D}]
set_false_path -to [get_pins {u_camera_video/g_hw.result_class_pix0_2_s0/D}]
set_false_path -to [get_pins {u_camera_video/g_hw.result_class_pix0_3_s0/D}]
