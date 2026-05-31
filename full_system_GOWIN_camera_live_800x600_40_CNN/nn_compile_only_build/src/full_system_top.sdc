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

# Do not add broad false paths yet.
