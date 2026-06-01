# FSM and Wrapper Refactor Report

Date: 2026-05-31

Project: Hardware Design of an OV2640 Camera-Based Handwritten Digit Recognition System on the Sipeed Tang Nano 4K FPGA Using a Post-Training Quantized CNN.

## Scope

This pass audited RTL FSMs and behavioral helpers after the Phase 1-3 leaf-cell refactor. Two low-risk FSM rewrites were attempted in controlled isolation:

- `cnn_spi_flash_reader`: registered-Mealy three-block rewrite attempted, then rolled back due timing regression.
- `camera_live_flow_control`: Moore/registered-Mealy three-block rewrite attempted, then rolled back due timing regression.

No FSM rewrite was kept in source because the final device margin is too tight. The project source was returned to the last build-passing RTL shape, with the existing Phase 1-3 leaf-cell conversions kept.

## FSM Rewrite Summary

| Module | Clock | Original style | New style | Moore outputs | Mealy outputs | Registered pulses | Rewritten? | Verification | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `camera_live_flow_control` | `I_clk`/`clk` | One-process high-level FSM plus registered key consume latch; Moore-style assigns for display/owner outputs | Attempted Moore states plus registered-Mealy pulses | `show_mnist`, `freeze_active`, `image_process_active`, `integration_busy`, `hyperram_owner_request` | Key-event transition conditions | `image_start`, `nn_start` | Attempted then rolled back | `tb_camera_live_state_flow` PASS; `tb_cnn_reduced_top_integration` PASS; Gowin PASS but timing regressed | Keep original |
| `button_debounce` | `I_clk`/`clk` | Counter/filter sequential block, not a named state FSM | Keep original; registered Mealy-like counter filter | N/A | Raw-vs-stable debounce decision | `pressed_pulse`, `released_pulse` | No | Covered by flow-control TB | Keep original |
| `cnn_system` | `I_clk`/`clk` | One-process registered control FSM | Proposed registered-Mealy three-block | `busy`, terminal status held by regs | `start_rise`, preload/memory/compute conditions | `compute_start`, `done`, `output_valid` | No | Full CNN suite PASS on original | Defer; moderate risk |
| `cnn_param_streamer` | `I_clk`/`clk` | One-process registered streaming FSM | Proposed registered-Mealy three-block | `param_ready`/`param_busy` style status | Range checks, byte-valid packing | `param_data_valid`, `param_done`, `param_error` | No | `tb_cnn_param_streamer` PASS | Keep original for now |
| `cnn_spi_flash_reader` | `I_clk`/`clk` | One-process registered Mealy algorithmic FSM | Attempted registered-Mealy three-block | `busy` held by state/progress | `div_tick`, `half_phase`, bit/byte counters, `spi_miso` | `data_valid`, `done`; SPI pins registered | Attempted then rolled back | `tb_cnn_param_streamer` PASS; full CNN suite PASS; Gowin PASS but timing regressed | Keep original |
| `cnn_compute_lwdd` | `I_clk`/`clk` | Large algorithmic registered Mealy/hybrid FSM with tasks and datapath controls | Document only | Some status/debug outputs | Parameter, RAM, MAC, cache, loop conditions | `done`, `output_valid`, RAM enables, param requests | No | Full CNN suite PASS | Do not rewrite without more margin |
| `streaming_mnist_capture` | `I_clk`/`clk` | One-process registered Mealy/Moore hybrid with sequential tasks | Proposed registered-Mealy/Moore hybrid | `capture_busy`, waiting/frame status style outputs | ROI/vsync/href/pixel conditions | `mnist_wr_en`, `capture_done`, `capture_error` | No | `tb_streaming_mnist_capture_equivalence` PASS | Keep original for now |
| `streaming_mnist_preload_packer` | `I_clk`/`clk` | Small one-process read/pack FSM | Proposed registered-Mealy three-block | `busy`, read state | RAM capture counter conditions | `done`, packed valid behavior | No | Covered indirectly; dedicated TB available | Low priority |
| `mnist28_row_cache_bridge` | `I_clk` and `pix_clk` interaction | Small request/row-cache bridge, CDC-sensitive | Document only unless CDC proof added | Row/valid status | Renderer request/response conditions | Cache fill handshakes | No | Renderer TB PASS | Do not touch in this phase |
| `mnist28_upscale_renderer` | `pix_clk`/render logic | Counter/address mapping control, no major named FSM | Keep original | RGB/de/address outputs | Coordinate in-ROI conditions | None critical | No | Renderer TB PASS | Keep original |
| `capture_dump_controller` | `I_clk`/`clk` | One-process UART dump FSM | Proposed Moore/registered-Mealy three-block | Dump busy/state status | UART ready, RAM capture conditions | UART send/write pulses | No | Dedicated TB exists, not part of final CNN path | Out of CNN critical path |
| `uart_tx` | `I_clk`/`clk` | One-process UART bit FSM | Proposed registered-Mealy three-block | `tx_ready` state decode | Baud counter/bit index | `tx` registered | No | Not enabled in final project | Keep original |
| `hyperram_mode_mux_direct` | `I_clk`/vendor interface clocks | Arbitration/counter control around vendor IP | Document only | Owner/request routing | HyperRAM ready/drain/write conditions | Request pulses | No | Final Gowin build PASS | Do not touch |
| `camera_video` | Mixed camera/video/vendor clocks | Mostly datapath/vendor IP integration; counter/control logic | Document only | Display/status routing | Camera/HyperRAM/video timing conditions | Vendor IP handshakes | No | Final Gowin build PASS | Do not touch |
| `OV2640_Controller` / `I2C_Interface` | camera config/I2C clocking | Protocol timing FSM/counter logic | Document only | I2C line/control states | Divider/ack/byte conditions | I2C strobes | No | Final Gowin build PASS | Do not touch |
| `video_frame_buffer`, `dvi_tx`, `hyperram_memory_interface` | Vendor/IP generated clocks | Vendor-generated IP | Keep vendor style | Vendor-defined | Vendor-defined | Vendor-defined | No | Final Gowin build PASS | Do not touch |

## Attempt Details and Rollbacks

| FSM | Attempt | Simulation result | PnR/resource result | Timing result | Decision |
| --- | --- | --- | --- | --- | --- |
| `cnn_spi_flash_reader` | Split into `next_state`, next datapath/control values, and registered output block; kept `data_valid`, `done`, SPI pins registered | `tb_cnn_param_streamer` PASS; full CNN suite PASS, including `tb_cnn_compute_lwdd`, `tb_cnn_system`, `tb_cnn_reduced_top_integration` | Gowin PASS; logic `4511/4608`, CLS `2301/2304`, BSRAM `10/10`, DSP `0.5/8` | Regressed: `I_clk 38.754 -> 32.147 MHz`; HyperRAM Fmax `65.863 -> 62.994 MHz`; HyperRAM TNS `-23.839 -> -25.079 ns` | Rolled back |
| `camera_live_flow_control` | Split high-level flow into combinational `next_state`/output-next logic and registered state/output block; kept key consume latch registered | `tb_camera_live_state_flow` PASS; `tb_cnn_reduced_top_integration` PASS | Gowin PASS; logic `4511/4608`, CLS `2301/2304`, BSRAM `10/10`, DSP `0.5/8` | Regressed: `I_clk 38.754 -> 36.315 MHz`; `pix_clk` TNS `-30.247 -> -60.175 ns`; HyperRAM Fmax `65.863 -> 60.190 MHz`; HyperRAM TNS `-23.839 -> -75.417 ns` | Rolled back |

## Wrapper/Leaf-Cell Summary

| File | Behavioral helper/task | Wrapper/leaf-cell | Action | Resource delta | Timing delta | Verification | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `src/cnn/cnn_compute_lwdd.v` | `addr_img28` | `leaf_addr_img28` | Previously converted | Included in final neutral build | Accepted in Phase 1 | `tb_leaf_cnn_helpers` PASS | Kept |
| `src/cnn/cnn_compute_lwdd.v` | `addr_14c4` | `leaf_addr_14c4` | Previously converted | Shared instance | Accepted in Phase 1 | `tb_leaf_cnn_helpers` PASS | Kept |
| `src/cnn/cnn_compute_lwdd.v` | `addr_7c8` | `leaf_addr_7c8` | Previously converted | Shared instance | Accepted in Phase 1 | `tb_leaf_cnn_helpers` PASS | Kept |
| `src/cnn/cnn_compute_lwdd.v` | `addr_7c16` | `leaf_addr_7c16` | Previously converted | Shared instance | Accepted in Phase 1 | `tb_leaf_cnn_helpers` PASS | Kept |
| `src/cnn/cnn_compute_lwdd.v` | `select_i16` | `leaf_select_i16` | Previously converted | Synthesis swept | Neutral | `tb_leaf_cnn_helpers` PASS | Kept |
| `src/cnn/cnn_compute_lwdd.v` | `sext32_to_acc` | `leaf_sext32_to_acc` | Previously converted | Synthesis swept | Neutral | `tb_leaf_cnn_helpers` PASS | Kept |
| `src/cnn/cnn_compute_lwdd.v` | `input_u8_to_i16` | `leaf_input_u8_to_i16` | Previously converted | Synthesis swept | Neutral | `tb_leaf_cnn_helpers` PASS | Kept |
| `src/cnn/cnn_compute_lwdd.v` | ReLU shift/saturate | `leaf_relu_shift_sat` | Previously converted | Synthesis swept | Neutral | `tb_leaf_cnn_helpers` PASS | Kept |
| `src/cnn/cnn_compute_lwdd.v` | `c5_word_offset` | `leaf_c5_word_offset` | Previously converted | 0 delta | Neutral | `tb_leaf_cnn_index_helpers` PASS | Kept |
| `src/cnn/cnn_compute_lwdd.v` | `conv6_word_offset` | `leaf_conv6_word_offset` | Previously converted | 0 delta | Neutral | `tb_leaf_cnn_index_helpers` PASS | Kept |
| `src/cnn/cnn_compute_lwdd.v` | `c5_cache_word` | `leaf_c5_cache_word` | Previously converted | 0 delta | Neutral | `tb_leaf_cnn_index_helpers` PASS | Kept |
| `src/cnn/cnn_compute_lwdd.v` | `scalar_c1` | `leaf_scalar_c1` | Previously converted | 0 delta | Neutral | `tb_leaf_cnn_index_helpers` PASS | Kept |
| `src/cnn/cnn_compute_lwdd.v` | `scalar_c2` | `leaf_scalar_c2` | Previously converted | 0 delta | Neutral | `tb_leaf_cnn_index_helpers` PASS | Kept |
| `src/cnn/cnn_compute_lwdd.v` | `scalar_c5` | `leaf_scalar_c5` | Previously converted | 0 delta | Neutral | `tb_leaf_cnn_index_helpers` PASS | Kept |
| `src/cnn/cnn_compute_lwdd.v` | `scalar_dense` | `leaf_scalar_dense` | Attempted before this pass | CLS changed, timing regressed | `I_clk 38.754 -> 31.570 MHz` | Helper/integration PASS before PnR | Rolled back |
| `src/cnn/cnn_compute_lwdd.v` | `scalar_c3` | `leaf_scalar_c3` | Attempted before this pass | Timing regressed | `I_clk 38.754 -> 36.325 MHz` and TNS worse | Helper/integration PASS before PnR | Rolled back |
| `src/cnn/cnn_compute_lwdd.v` | `scalar_c4` | `leaf_scalar_c4` | Attempted before this pass | CLS reached `2304/2304` | HyperRAM Fmax/TNS worse | Helper/integration PASS before PnR | Rolled back |
| `src/streaming_mnist_capture.v` | `start_capture`, `fail_capture` | N/A | Documentation only | 0 | 0 | Equivalence TB PASS | Keep behavioral |
| `src/cnn/cnn_compute_lwdd.v` | `start_contiguous_load`, `next_3x3_loop`, `next_sub_3x3_loop` | N/A | Documentation only | 0 | 0 | Full CNN suite PASS | Keep behavioral |
| `src/cnn/cnn_param_streamer.v` | Range/packing logic | N/A | Documentation only | 0 | 0 | Param streamer TB PASS | Keep behavioral |
| `src/video/mnist28_row_cache_bridge.v` | Row-cache request/response logic | N/A | Documentation only | 0 | 0 | Renderer TB PASS | Keep behavioral |

## Remaining Behavioral Blocks

- `cnn_compute_lwdd`: keep the algorithmic compute FSM, `scalar_c3`, `scalar_c4`, `scalar_dense`, and loop/load tasks behavioral. Previous scalar extraction attempts caused timing/resource regression.
- `cnn_spi_flash_reader`: keep one-process registered Mealy implementation. Three-block rewrite was functionally correct but reduced `I_clk` margin.
- `camera_live_flow_control`: keep original one-process FSM. Three-block rewrite was functionally correct but worsened generated-clock/video TNS.
- `streaming_mnist_capture`: keep `start_capture` and `fail_capture` tasks. They update many sequential registers and preserve one-cycle `mnist_wr_en`, `capture_done`, and `capture_error` behavior.
- `mnist28_row_cache_bridge`: keep original CDC-sensitive bridge logic to avoid reintroducing preview CDC bugs.
- Vendor/IP wrappers (`video_frame_buffer`, `dvi_tx`, `hyperram_memory_interface`): do not rewrite generated/vendor logic.

## Datapath Drawing Guide

| Diagram name | Blocks to draw | Registers/counters | Muxes/control | RAM | Leaf-cells/FSM relation |
| --- | --- | --- | --- | --- | --- |
| `top_camera_to_cnn_flow` | OV2640, camera live, HyperRAM/VFB, MNIST capture, preview, CNN system, HDMI result | Flow state, capture status, CNN status | HyperRAM owner request, preview/result select | HyperRAM/VFB, MNIST buffer | `camera_live_flow_control` chooses owner/start pulses |
| `cnn_param_stream_path` | `cnn_param_streamer`, `cnn_spi_flash_reader`, SPI flash model/device, compute param input | SPI divider, header shifter, byte/word pack counters | Param request range checks, byte-to-word pack mux | Parameter cache in compute | SPI FSM is registered Mealy; streamer feeds compute cache |
| `cnn_compute_datapath` | Feature buffers, word cache, multiplier, accumulator, activation/writeback | Layer counters, MAC accumulator, cache counters | Layer state muxes, scalar index selects | Feature buffers, word cache | Leaf address/scalar/cache helpers feed FSM-controlled RAM/MAC |
| `mnist_capture_downscale` | ROI filter, green grayscale, column sums, row flush/writeout | x/y counters, ROI counts, block sums | Vsync/error/start decisions | `col_sum`, MNIST buffer | Capture FSM controls clear/run/flush/write states |
| `preview_row_cache_bridge` | MNIST buffer reader, row cache, renderer | requested row, cached row, pixel counters | row-hit/refill select | row cache, MNIST RAM | CDC-sensitive bridge between I_clk RAM and pix_clk renderer |
| `flow_control_fsm` | Key debounce, flow state, image/CNN start pulses, result latch | `state`, `key_wait_release`, result regs | key event consume, owner select | N/A | Moore display/owner outputs plus registered Mealy start pulses |

## Final Verification

Final source state is rollback-clean for the two FSM attempts. The report was created after the rollback, and final simulation/PnR were rerun on the post-rollback build-passing source state.

Simulation:

- `tb_leaf_cnn_helpers`: PASS
- `tb_leaf_cnn_index_helpers`: PASS
- `tb_camera_live_state_flow`: PASS
- `tb_mnist28_upscale_renderer`: PASS
- `tb_cnn_param_streamer`: PASS
- `tb_cnn_compute_lwdd`: PASS, finish time `679620755 ns`
- `tb_cnn_system`: PASS, finish time `685410215 ns`
- `tb_cnn_reduced_top_integration`: PASS, finish time `342700715 ns`
- `tb_streaming_mnist_capture_equivalence`: PASS, finish time `25517765 ns`

Gowin build:

- Command: `C:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe run_final_build.tcl`
- Result: PASS
- Bitstream: `impl/pnr/full_system_GOWIN_camera_live_800x600_40_CNN.fs`
- `PR0003`: absent
- `TA2003`: absent
- Logic and I/O latches: 0
- BSRAM: 10/10
- DSP: 0.5/8
- Git metadata: not available; this workspace is not a git repository

Resource before/after:

| Metric | Baseline before this pass | Final after rollbacks | Delta |
| --- | ---: | ---: | ---: |
| Logic | 4511/4608 | 4511/4608 | 0 |
| LUT | 3749 | 3749 | 0 |
| ALU | 762 | 762 | 0 |
| Register | 2802/3612 | 2802/3612 | 0 |
| Latches | 0 | 0 | 0 |
| CLS | 2302/2304 | 2302/2304 | 0 |
| BSRAM | 10/10 | 10/10 | 0 |
| DSP | 0.5/8 | 0.5/8 | 0 |

Timing before/after:

| Clock | Baseline before this pass | Final after rollbacks |
| --- | ---: | ---: |
| `I_clk`, constraint 27 MHz | 38.754 MHz | 38.754 MHz |
| `PIXCLK`, constraint 24 MHz | 81.391 MHz | 81.391 MHz |
| `pix_clk`, constraint 40 MHz | 35.924 MHz | 35.924 MHz |
| TMDS CLKOUTD, constraint 12.488 MHz | 53.780 MHz | 53.780 MHz |
| HyperRAM clkdiv, constraint 79.5 MHz | 65.863 MHz | 65.863 MHz |

Inherited timing remains unchanged after rollback: `I_clk` and `PIXCLK` setup/hold TNS are 0, `pix_clk` setup TNS is `-30.247 ns`, and HyperRAM generated-clock setup TNS is `-23.839 ns`.

## Recommended Next Step

Do not attempt more structural FSM rewrites until timing/resource margin is recovered. The next useful work for diagrams is documentation-only: draw the current one-process FSMs as registered-Mealy/Moore hybrids, using the tables above as labels for state registers, registered pulses, counters, RAMs, and leaf-cell datapath boundaries.
