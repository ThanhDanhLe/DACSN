# Branch Status: 800x600@40 NN Integrated

Date: 2026-05-24

This folder is now the isolated NN-integration branch:

`full_system_GOWIN_camera_live_800x600_40_nn_integrated`

It was cloned from the board-stable `full_system_GOWIN_camera_live_800x600_40` branch and imports the verified NN/SPI/preload path from `full_system_GOWIN_nn_uart_standalone`.

## Current Status

- Live camera preview remains VFB/HyperRAM/HDMI at 800x600@40.
- Streaming MNIST capture remains the NN input source.
- VFB readback is not used as NN input.
- Dual-clock MNIST RAM payload boundary remains.
- Preload packer is wired to `nn_system`.
- SPI flash parameter streaming is wired through `nn_spi_param_streamer`.
- HDMI seven-seg result overlay is wired.
- UART/capture dump debug is optional and disabled by default.

## Constraints Preserved

- `FLASH_PARAM_BASE = 24'h200000`
- SPI params at offset `0x200000`
- `direct_stream_params.bin` unchanged
- ROI448/BLOCK16 unchanged
- threshold `8'd100` unchanged
- OV2640 RGB565 unchanged
- NN architecture unchanged

## Build Status

The branch builds and generates:

`impl/pnr/full_system_GOWIN_camera_live_800x600_40_nn_integrated.fs`

It is not timing-clean. Pixel clocks pass at the 800x600@40 requirement, but HyperRAM/VFB generated-clock paths still fail in the report.

## Board Status

Board test is pending for this integrated branch.

The predecessor 800x600@40 live camera branch was board-tested and visually stable. The predecessor `nn_uart_standalone` branch was board-tested and matched Python NN prediction. This integration must now prove that the camera-captured 784 pixels, preload sequence, SPI params, and HDMI result all agree on board.

