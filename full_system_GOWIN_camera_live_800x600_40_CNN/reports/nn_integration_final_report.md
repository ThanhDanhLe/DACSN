# NN Integration Final Report

Date: 2026-05-24

## Branch

`full_system_GOWIN_camera_live_800x600_40_nn_integrated`

This branch was created independently from:

- `full_system_GOWIN`
- `full_system_GOWIN_camera_live_800x600_40`
- `full_system_GOWIN_nn_uart_standalone`

No source in those reference branches was modified.

## Integrated Architecture

```text
OV2640 RGB565 live camera
  -> VFB/HyperRAM/HDMI live preview at 800x600@40
  -> streaming_mnist_capture
       -> dual-clock MNIST RAM
       -> streaming_mnist_preload_packer
       -> nn_system
            -> nn_spi_param_streamer
            -> nn_compute_mlp16_pocket
       -> lightweight HDMI seven-seg result overlay
```

## Preserved Constants and Formats

- `FLASH_PARAM_BASE = 24'h200000`
- SPI flash parameter offset `0x200000`
- `direct_stream_params.bin` format unchanged
- OV2640 RGB565 unchanged
- ROI `448x448`
- `BLOCK_SIZE = 16`
- threshold `8'd100`
- output polarity unchanged
- 784 row-major MNIST output unchanged
- preload packing follows verified standalone convention

## Files Changed or Added

Primary integration files:

- `camera_live_top.v`
- `camera_video.v`
- `streaming_mnist_preload_packer.v`
- `mnist_image_buffer_dualclk.v`
- `src/nn/*.v`
- `src/leaf_cells/leaf_adder.v`
- `src/leaf_cells/leaf_multiplier.v`
- `src/leaf_cells/leaf_reg_bus_load_rst.v`
- `src/leaf_cells/leaf_sevenseg_decode.v`
- `src/full_system_top.sdc`
- `sim/tb_streaming_capture_to_nn_preload_smoke.v`

## Verification

All integration-stage simulation checks passed:

- preload packing TB: PASS
- dual-clock RAM to preload smoke TB: PASS
- streaming capture equivalence TB: PASS

The known-good `nn_uart_standalone` board result is used as the NN arithmetic/SPI/preload reference.

## P&R Result

Bitstream generated:

`impl/pnr/full_system_GOWIN_camera_live_800x600_40_nn_integrated.fs`

Resources:

- Logic `4397/4608`
- LUT `3706`
- ALU `691`
- Reg `2666/3612`
- CLS `2281/2304`
- BSRAM `10/10`
- DSP `2/8`

Timing:

- `I_clk`: `39.191 MHz` achieved vs `27.000 MHz` required
- `PIXCLK`: `60.109 MHz` achieved vs `24.000 MHz` required
- `pix_clk`: `55.784 MHz` achieved vs `40.000 MHz` required
- HyperRAM clkdiv: `69.765 MHz` achieved vs `79.500 MHz` required
- worst setup slack: `-8.070 ns`
- worst hold slack: `-0.916 ns`

## Decision

The branch is ready for board smoke test, but it is not timing-clean.

The most important practical win over old direction 1 is that the live pixel clock requirement is now only `40 MHz`, while NN input comes from the streaming capture path rather than VFB readback. The remaining timing report risk is still VFB/HyperRAM boundary logic.

## Next Board Test

1. Program `final/out/direct_stream_params.bin` to SPI flash offset `0x200000`.
2. Program `impl/pnr/full_system_GOWIN_camera_live_800x600_40_nn_integrated.fs`.
3. Confirm live HDMI quality matches the board-stable 800x600@40 branch.
4. Capture digits and compare integrated FPGA results with Python prediction from the exact 784-pixel capture dump when debug is enabled.

If Python and FPGA agree, wrong predictions should be treated as model/input-domain mismatch rather than hardware NN failure.

