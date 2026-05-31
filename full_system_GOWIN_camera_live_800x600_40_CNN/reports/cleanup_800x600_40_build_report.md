# 800x600@40 Build Report

Date: 2026-05-24

## Simulation

ModelSim:

`TB PASS: streaming_mnist_capture matches mode-2 reference`

Transcript:

`sim/equivalence_transcript.log`

## P&R Result

Bitstream generated:

`impl/pnr/full_system_GOWIN_camera_live_800x600_40.fs`

| Metric | Value |
|---|---:|
| Logic | 2908 / 4608 |
| LUT | 2546 |
| ALU | 362 |
| Reg | 1798 / 3612 |
| CLS | 1840 / 2304 |
| BSRAM | 7 / 10 |
| DSP | 0 / 8 |
| required pix_clk | 40.000 MHz |
| achieved pix Fmax | 61.161 MHz |
| required HyperRAM clkdiv | 79.500 MHz |
| achieved HyperRAM Fmax | 83.557 MHz |
| worst setup slack | -7.100 ns |
| worst hold slack | -0.035 ns |

## Top Paths

Top setup remains VFB/display to HyperRAM:

`u_camera_video/g_hw.u_syn_gen/O_vs_s0 -> u_camera_video/g_hw.u_frame_buffer/.../dma_vs_n_d0_s0`

Top hold remains HyperRAM vendor calibration:

`u_camera_video/g_hw.u_hyperram/u_hpram_top/u_hpram_init/read_calibration[0].calib[0] -> .../u_ides4`

Full path dump:

`impl/pnr/full_system_GOWIN_camera_live_800x600_40.timing_paths`

## Decision

Keep as a clean standalone board-test candidate, but not timing-closed.
