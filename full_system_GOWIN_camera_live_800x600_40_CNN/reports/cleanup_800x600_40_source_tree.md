# 800x600@40 Source Tree

Date: 2026-05-24

## Active Purpose

Standalone promoted copy of the diagnostic `mode_800x600_40_build` branch.

## Active RTL Groups

- Camera/config: `OV2640_Controller.v`, `OV2640_Registers.v`, `I2C_Interface.v`
- Camera stream: `camera_byte_packer.v`, `streaming_mnist_capture.v`
- CDC/storage: `cdc_pulse_sync.v`, `mnist_image_buffer_dualclk.v`, `reset_sync.v`
- Live display/VFB: `camera_video.v`, `video_frame_buffer.v`, `hyperram_memory_interface.v`, `hyperram_mode_mux_direct.v`, `syn_gen.v`, `dvi_tx.v`
- PLL/IP wrappers: `GW_PLLVR.v`, `TMDS_PLLVR.v`
- Leaf cells: `leaf_dff_rst.v`, `leaf_reg_bus_en_rst.v`, `leaf_reg_bus_rst.v`

## Simulation

- `sim/tb_streaming_mnist_capture_equivalence.v`
- `sim/reference/` contains the copied mode-2 reference RTL used only for the equivalence TB.

## Archived

`archive_unused_sources_20260524_1113/`

- `src/streaming_mnist_capture_stub.v`
- `sim/tb_streaming_mnist_capture_stub.v`

These are not part of the active build.
