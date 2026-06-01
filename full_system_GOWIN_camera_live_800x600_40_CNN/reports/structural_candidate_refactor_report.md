# Structural Candidate Refactor Report

Date: 2026-05-31/2026-06-01 local run

This report supersedes the strict rollback notes for the relaxed structural/gate-level/FSM-wrapper phase. The final `structural_candidate` is the current source tree. The stable backup is `variants/stable_baseline_20260531_relaxed_phase`.

## 2026-06-01 Overlay Phase Update

The current source tree has moved beyond the structural candidate captured below. See `reports/sevenseg_overlay_and_wrapper_refactor_report.md` for the accepted HDMI seven-segment result overlay, the result-class CDC latch, the re-tested MNIST threshold/address wrappers, and the latest final resource/timing numbers. In that later phase, `leaf_mnist_threshold_invert` and `leaf_mnist_addr_28x28` are accepted as part of the final overlay build.

## Final Decision

Accepted and kept:

- `leaf_scalar_dense` in `src/leaf_cells/leaf_scalar_dense.v`, instantiated by `cnn_compute_lwdd`.
- `leaf_rgb565_green_to_gray` in `src/leaf_cells/leaf_rgb565_green_to_gray.v`, instantiated by `streaming_mnist_capture`.

Rejected/rolled back:

- `leaf_scalar_c3`: HyperRAM TNS regressed to `-71.832 ns` in the combined candidate.
- `leaf_scalar_c4`: `pix_clk` TNS regressed to `-66.549 ns`, beyond the 2x baseline threshold.
- `cnn_spi_flash_reader` registered-Mealy three-block rewrite: functionally passed, but combined PnR regressed generated-clock/video TNS beyond the relaxed limit.
- `leaf_mnist_addr_28x28` and `leaf_mnist_threshold_invert`: functionally passed, but the wrapper set pushed CLS/TNS too close or beyond acceptance.
- `camera_live_flow_control` rewrite remains rejected from the prior attempt because it doubled/worsened generated-clock TNS; no lower-fanout rewrite was kept in this phase.

## Resource Table

| Candidate point | Logic | LUT | ALU | Register | CLS | Latch | BSRAM | DSP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Stable baseline | 4511/4608 | 3749 | 762 | 2802/3612 | 2302/2304 | 0 | 10/10 | 0.5/8 |
| After `leaf_scalar_dense` | 4511/4608 | 3749 | 762 | 2802/3612 | 2301/2304 | 0 | 10/10 | 0.5/8 |
| Final: dense + RGB wrapper | 4511/4608 | 3749 | 762 | 2802/3612 | 2301/2304 | 0 | 10/10 | 0.5/8 |

## Timing Table

| Candidate point | `I_clk` | `PIXCLK` | `pix_clk` | HyperRAM clkdiv | `pix_clk` TNS | HyperRAM TNS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Stable baseline | 38.754 MHz | 81.391 MHz | 35.924 MHz | 65.863 MHz | -30.247 ns | -23.839 ns |
| After `leaf_scalar_dense` | 31.570 MHz | 83.031 MHz | 36.079 MHz | 67.131 MHz | -18.439 ns | -37.425 ns |
| Final: dense + RGB wrapper | 31.570 MHz | 83.031 MHz | 36.079 MHz | 67.131 MHz | -18.439 ns | -37.425 ns |

Final acceptance rationale: `I_clk` remains above 30 MHz and the actual 27 MHz constraint, `PIXCLK` remains above 24 MHz, latches remain 0, BSRAM remains 10/10, DSP is unchanged, and final generated-clock TNS does not exceed the 2x rollback threshold.

## Rejected Attempt Evidence

| Attempt | Functional result | PnR result | Reason for rollback |
| --- | --- | --- | --- |
| `leaf_scalar_c3` | Helper bench PASS | Build PASS, `I_clk 37.144 MHz`, `pix_clk` TNS `-39.549 ns`, HyperRAM TNS `-71.832 ns` | HyperRAM TNS > 2x baseline without board smoke proof |
| `leaf_scalar_c4` | Helper bench PASS | Build PASS, `I_clk 33.584 MHz`, `pix_clk` TNS `-66.549 ns`, HyperRAM TNS `-43.240 ns` | `pix_clk` TNS > 2x baseline |
| SPI reader three-block registered-Mealy | `tb_cnn_param_streamer` PASS | Build PASS, combined final/provisional TNS as bad as `pix_clk -70.326 ns`, HyperRAM `-68.351 ns` | Functionally correct but not timing-acceptable in the combined source |
| RGB + threshold + addr wrappers | Streaming equivalence PASS | Build PASS, logic `4543/4608`, CLS `2303/2304`, `pix_clk -70.326 ns`, HyperRAM `-68.351 ns` | Generated-clock TNS too large |
| RGB + threshold wrappers | Streaming equivalence PASS | Build PASS, logic `4543/4608`, CLS `2304/2304`, HyperRAM `-70.853 ns` | CLS full and HyperRAM TNS too large |

## FSM Classification

- `cnn_spi_flash_reader` attempted style: registered Mealy, with registered `data_valid`, `done`, and SPI pins. Rolled back due combined timing.
- `camera_live_flow_control` attempted style from previous pass: Moore state outputs plus registered-Mealy start pulses. Rolled back due generated-clock TNS.
- Final source keeps the original FSM implementations for both modules.

## Wrapper/Leaf-Cell Summary

Kept final leaf/wrapper modules:

- `leaf_scalar_dense`: dense scalar address datapath boundary for `S_DENSE_MAC`.
- `leaf_rgb565_green_to_gray`: streaming MNIST capture green-channel grayscale datapath boundary.

Remaining behavioral blocks:

- `scalar_c3`, `scalar_c4`, `start_contiguous_load`, `next_3x3_loop`, and `next_sub_3x3_loop` remain behavioral because extracted forms either failed timing acceptance or would move sequential FSM ownership.
- `streaming_mnist_capture` keeps threshold/invert and 28x28 address logic local after wrapper attempts exceeded timing/resource limits.
- HyperRAM/VFB/vendor IP and CDC-sensitive row cache logic were not rewritten.

## Datapath Drawing Guide

For the report diagrams, label these structural boundaries:

- CNN compute: `leaf_scalar_dense`, plus existing kept helpers `leaf_addr_img28`, `leaf_addr_14c4`, `leaf_addr_7c8`, `leaf_addr_7c16`, `leaf_c5_word_offset`, `leaf_conv6_word_offset`, `leaf_c5_cache_word`, `leaf_scalar_c1`, `leaf_scalar_c2`, `leaf_scalar_c5`, `leaf_select_i16`, `leaf_sext32_to_acc`, `leaf_input_u8_to_i16`, and `leaf_relu_shift_sat`.
- MNIST capture: `leaf_rgb565_green_to_gray`, ROI/block accumulator, `col_sum`, threshold/invert, and MNIST buffer writeout.
- SPI/parameter path: keep `cnn_spi_flash_reader` as original one-process registered Mealy, feeding `cnn_param_streamer`.
- Flow control: keep `camera_live_flow_control` original; draw display/owner state outputs and start pulses.

## Verification

Final `vsim -c -do sim\cnn_modelsim.do` PASS list:

- `tb_leaf_cnn_helpers`
- `tb_leaf_cnn_index_helpers`
- `tb_leaf_mnist_helpers`
- `tb_camera_live_state_flow`
- `tb_mnist28_upscale_renderer`
- `tb_cnn_param_streamer`
- `tb_cnn_compute_lwdd`
- `tb_cnn_system`
- `tb_cnn_reduced_top_integration`

Standalone final streaming equivalence:

- `tb_streaming_mnist_capture_equivalence`: PASS, finish time `25517765 ns`.

Final Gowin build:

- Command: `C:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe run_final_build.tcl`
- Result: PASS
- `PR0003`: absent
- `TA2003`: absent
- Logic/I/O latches: 0
- Bitstream: `impl/pnr/full_system_GOWIN_camera_live_800x600_40_CNN.fs`

## Board Smoke

Board smoke test was not run in this environment. Status: PnR accepted, board test pending.
