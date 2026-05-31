# 800x600@40 Main Branch Status

Date: 2026-05-24

## Decision

`full_system_GOWIN_camera_live_800x600_40` is now the main practical development branch.

Board test confirmed that the 800x600@40 live camera output is stable and visually good on the kit.

## Branch Roles

- `full_system_GOWIN_camera_live_800x600_40`: active development base.
- `full_system_GOWIN`: reference/archive only for NN, SPI streamer, preload convention, result display, and Python/bin verification scripts.
- `full_system_GOWIN_camera_live_no_vfb_exp`: paused because board preview was not useful enough for this integration path.
- Old 74.25 MHz camera-live branch: superseded by this 40 MHz branch.

## Preserved Function

- OV2640 RGB565 camera path.
- Gowin VFB/HyperRAM/HDMI live preview.
- 800x600 active video, 1056x628 total timing, 40 MHz pixel clock.
- Streaming MNIST capture from camera stream, not VFB readback.
- ROI448/BLOCK16, threshold `8'd100`, same polarity and 784 row-major output.
- Dual-clock MNIST RAM payload boundary.

## Current Rule

Do not integrate NN until the exact 784-pixel capture can be exported and checked against Python inference.

## Current Timing Note

The debug build still reports a VFB/HyperRAM generated-clock setup violation, but:

- required pix clock is 40.000 MHz and achieved pix Fmax is 65.428 MHz,
- required HyperRAM clkdiv is 79.500 MHz and achieved HyperRAM Fmax is 79.741 MHz,
- hold is now positive at +0.570 ns,
- board live preview is stable.

The remaining setup report is treated as a risk to document, not as evidence that streaming MNIST capture is corrupt.
