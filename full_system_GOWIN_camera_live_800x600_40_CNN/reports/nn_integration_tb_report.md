# NN Integration Testbench Report

Date: 2026-05-24

Branch:

`full_system_GOWIN_camera_live_800x600_40_nn_integrated`

## Scope

This branch integrates the verified `nn_uart_standalone` NN/SPI/preload path into the board-stable 800x600@40 camera-live branch.

The accepted camera capture math was not changed:

- OV2640 RGB565 camera format
- ROI `448x448`
- `BLOCK_SIZE = 16`
- threshold `8'd100`
- polarity and 784 row-major output
- `FLASH_PARAM_BASE = 24'h200000`
- SPI parameter offset `0x200000`

## Tests Run

| Testbench | Result | Transcript |
|---|---|---|
| `tb_streaming_mnist_preload_pack.v` | PASS | `sim/preload_pack_integrated_transcript.log` |
| `tb_streaming_capture_to_nn_preload_smoke.v` | PASS | `sim/ram_to_preload_smoke_transcript.log` |
| `tb_streaming_mnist_capture_equivalence.v` | PASS | `sim/equivalence_integrated_transcript.log` |

## What Was Verified

- `streaming_mnist_capture` still matches the existing mode-2 reference output exactly.
- The dual-clock MNIST RAM can feed the preload packer read side.
- Preload packing follows the verified convention:
  - even pixel -> `preload_data[15:0]`
  - odd pixel -> `preload_data[31:16]`
  - `preload_addr = pixel_addr[9:1]`
- Exactly 392 preload words are generated for 784 input pixels.
- First, last, one-hot, increasing, and pseudo-random preload cases pass.

## Not Yet Board-Verified

The integrated FPGA result has not yet been compared against a captured 784-pixel dump on board. The required board-side confirmation is:

1. Dump or otherwise verify the 784 pixels from the camera capture.
2. Run Python inference on that exact dump.
3. Compare Python class against the FPGA HDMI seven-seg class.

If Python and FPGA match on the same dump, any wrong real-world digit result should be treated as model/input-domain behavior, not an NN hardware fault.

