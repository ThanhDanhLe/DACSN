# Seven-Segment Overlay and Wrapper Refactor Report

Date: 2026-06-01

## Purpose

This phase restores a board-visible CNN result display on HDMI. The prior expensive result display had been removed to recover resources, so this pass adds a lightweight one-digit seven-segment-style overlay while preserving the working camera, MNIST preview, CNN, simulation, and Gowin build behavior.

The phase also keeps only low-risk source-level wrapper boundaries that help the datapath explanation without forcing physical hierarchy.

## Final Overlay Datapath

Final source datapath:

`result_class_latched/result_valid_latched` in `I_clk`
-> `cdc_result_class_latch`
-> `displayed_class_pix/displayed_class_valid_pix` in `pix_clk`
-> `digit_to_7seg`
-> `sevenseg_digit_overlay`
-> direct fixed-green RGB565 mux in `camera_video`
-> HDMI RGB register/TMDS.

The overlay is integrated in `src/camera_video.v` in the hardware HDMI branch, just before `rgb_data_tx` is registered. It has priority over live/ROI pixels only when the result class is valid. It is gated off during MNIST preview (`show_processed`) and during error display.

To recover timing margin, the final board path uses `sevenseg_digit_overlay` with `FAST_POWER2=1`: one green 64x128 digit at the top-left active-video origin. The generic coordinate-compare implementation remains in the module and is covered by simulation, but the hardware instance uses the fast bit-slice geometry.

## Segment Convention

`digit_to_7seg` and `sevenseg_digit_overlay` use:

`seg[6:0] = {A,B,C,D,E,F,G}`

Digits `0` through `9` are supported. Invalid values `10` through `15` blank the digit.

## CDC Method

`src/cdc/cdc_result_class_latch.v` captures `result_class` on the rising edge of source-domain `result_valid`, toggles a source event bit, synchronizes that event into `pix_clk`, and latches the held class when the destination detects the toggle.

The valid level is separately synchronized into `pix_clk` and exported as `displayed_class_valid_pix`.

Safety assumption: `camera_live_flow_control` registers and holds `result_class` stable while `result_valid` remains asserted in `S_SHOW_RESULT`. The destination samples the held class only after the synchronized event arrives, so the multi-bit bus is not randomly sampled while changing. The corresponding SDC entries were updated and are active in the final timing report.

## Wrappers Kept

New display/result wrappers:

- `src/video/digit_to_7seg.v`
- `src/video/sevenseg_digit_overlay.v`
- `src/video/result_overlay_mux.v` is present for documentation/reuse, but the final hardware path uses a direct RGB565 mux to save logic and timing.
- `src/cdc/cdc_result_class_latch.v`

New/kept MNIST preprocessing wrappers:

- `src/leaf_cells/leaf_rgb565_green_to_gray.v`
- `src/leaf_cells/leaf_mnist_threshold_invert.v`
- `src/leaf_cells/leaf_mnist_addr_28x28.v`

Existing CNN leaf helpers remain kept, including address/select/sign/activation helpers and `leaf_scalar_dense`.

## Behavioral Logic Left In Place

The following blocks remain behavioral because earlier extraction attempts either regressed timing/resource use or were too risky for this saturated device:

- `cnn_compute_lwdd` main compute FSM, loop tasks, `scalar_c3`, and `scalar_c4`
- `cnn_spi_flash_reader` one-process registered-Mealy implementation
- `camera_live_flow_control` one-process flow FSM
- `streaming_mnist_capture` sequential capture/error tasks
- `mnist28_row_cache_bridge` CDC-sensitive row-cache control
- Vendor/generated IP including VFB, DVI, and HyperRAM blocks

## Testbench Results

Final command:

`vsim -c -do sim/cnn_modelsim.do`

Final PASS results:

| Testbench | Result |
| --- | --- |
| `tb_leaf_cnn_helpers` | PASS |
| `tb_leaf_cnn_index_helpers` | PASS |
| `tb_leaf_mnist_helpers` | PASS |
| `tb_digit_to_7seg` | PASS |
| `tb_sevenseg_digit_overlay` | PASS |
| `tb_cdc_result_class_latch` | PASS |
| `tb_camera_live_state_flow` | PASS |
| `tb_streaming_mnist_capture_equivalence` | PASS, finish time `25517765 ns` |
| `tb_mnist28_upscale_renderer` | PASS |
| `tb_cnn_param_streamer` | PASS |
| `tb_cnn_compute_lwdd` | PASS, finish time `679620755 ns` |
| `tb_cnn_system` | PASS, finish time `685410215 ns` |
| `tb_cnn_reduced_top_integration` | PASS, finish time `342700715 ns` |

## Gowin Build Results

Final command:

`C:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe run_final_build.tcl`

Final status:

- Synthesis: PASS
- Placement: PASS
- Routing: PASS
- Bitstream: generated
- Bitstream path: `impl/pnr/full_system_GOWIN_camera_live_800x600_40_CNN.fs`
- `PR0003`: absent
- `TA2003`: absent
- Logic latches: 0
- I/O latches: 0
- BSRAM: `10/10`
- DSP: `0.5/8`

Synthesis flattened the overlay hierarchy (`NL0002` on `sevenseg_digit_overlay`), which is accepted because no `keep_hierarchy`/`dont_touch` attributes were requested. The source-level wrapper boundary remains for documentation and testing.

## Resource Comparison

| Build point | Logic | LUT | ALU | Register | CLS | Latches | BSRAM | DSP | Decision |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Baseline before overlay | 4511/4608 | 3749 | 762 | 2802/3612 | 2302/2304 | 0 | 10/10 | 0.5/8 | Reference |
| Initial generic 24-bit overlay | 4552/4608 | 3788 | 764 | 2808/3612 | 2304/2304 | 0 | 10/10 | 0.5/8 | Simplified for timing |
| Fast overlay with 24-bit mux | 4556/4608 | 3792 | 764 | 2808/3612 | 2302/2304 | 0 | 10/10 | 0.5/8 | Simplified further |
| Final fast overlay + direct RGB565 mux | 4548/4608 | 3784 | 764 | 2807/3612 | 2304/2304 | 0 | 10/10 | 0.5/8 | Accepted |

## Timing Comparison

| Build point | `I_clk` | `PIXCLK` | `pix_clk` | TMDS CLKOUTD | HyperRAM clkdiv | `pix_clk` TNS | HyperRAM TNS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Baseline before overlay | 38.754 MHz | 81.391 MHz | 35.924 MHz | 53.780 MHz | 65.863 MHz | -30.247 ns | -23.839 ns |
| Initial generic 24-bit overlay | 40.012 MHz | 79.969 MHz | 30.551 MHz | 68.903 MHz | 65.466 MHz | -79.394 ns | not accepted |
| Fast overlay with 24-bit mux | 38.293 MHz | 80.531 MHz | 33.875 MHz | 52.046 MHz | 61.706 MHz | -91.373 ns | not accepted |
| Final fast overlay + direct RGB565 mux | 36.316 MHz | 83.936 MHz | 37.745 MHz | 62.086 MHz | 70.406 MHz | -8.769 ns | -11.918 ns |

The final accepted build improves `pix_clk` and HyperRAM TNS versus the documented baseline while keeping `I_clk` above the 27 MHz target.

## Board Smoke Test

Board smoke test is pending because no physical Tang Nano 4K board is available to Codex in this environment.

Required board steps:

1. Program `impl/pnr/full_system_GOWIN_camera_live_800x600_40_CNN.fs`.
2. Reset the board.
3. Confirm live OV2640 HDMI image.
4. Press the step key once and confirm ROI processing/MNIST preview.
5. Press the step key again and confirm CNN compute completes.
6. Confirm the top-left green seven-segment digit shows the predicted class `0` through `9`.
7. Repeat with several handwritten digits and capture report photos for live camera, MNIST preview, and result overlay.

## Diagram List For Thesis/Report

1. Top-level camera-to-CNN-to-HDMI datapath
2. Camera live display and HyperRAM/VFB path
3. ROI-to-MNIST preprocessing datapath
4. RGB565 green-channel grayscale wrapper
5. 448x448 ROI to 28x28 block mapping
6. Threshold/inversion datapath
7. SPI Flash parameter read and packing datapath
8. CNN compute datapath
9. Dense-layer scalar/index helper datapath
10. `output_class` result CDC path
11. Seven-segment overlay datapath
12. HDMI display composition mux
13. Top-level user FSM: live -> process -> preview -> CNN -> result
14. CDC boundaries among PCLK, I_clk, pix_clk, and HyperRAM generated clocks
15. Simulation/PnR/board-test acceptance flow

## Honest Risk Note

The device remains saturated: final CLS is `2304/2304` and BSRAM is `10/10`. The accepted overlay is intentionally minimal: one fixed green digit, top-left only, no text, no font ROM, no decorative border, and no multi-digit output. Remaining behavioral CNN/FSM blocks are left in place because previous wrapper/FSM extraction attempts were functionally correct but too timing-sensitive for this board.
