# Gate-Level Leaf-Cell Refactor Report

Date: 2026-05-31

## Relaxed Acceptance Update

The later relaxed structural-candidate phase keeps `leaf_scalar_dense` after re-testing against the softer timing policy. See `reports/structural_candidate_refactor_report.md` for the current accepted/rejected list and final metrics.

## 2026-06-01 Overlay Phase Update

The current source tree also includes the later HDMI seven-segment result overlay and result CDC work. See `reports/sevenseg_overlay_and_wrapper_refactor_report.md` for the accepted final metrics and the added display/MNIST helper wrappers.

## Scope

Phase 1 was completed for `src/cnn/cnn_compute_lwdd.v`: the small CNN helper functions for activation addressing, word selection, sign extension, input conversion, and ReLU/shift/saturation were converted into explicit combinational leaf-cell modules under `src/leaf_cells/`. Phases 2 and 3 then converted only the parameter/cache/scalar helpers that stayed resource/timing neutral after full simulation and Gowin PnR.

No Gowin LUT/FF primitives were instantiated. No CNN arithmetic, quantization constants, tensor layout, FSM cycle count, RAM topology, or Python parameter files were changed.

## Current Module Hierarchy

- `camera_live_top`
- `camera_video`
- `streaming_mnist_capture`
- `mnist_image_buffer_dualclk`
- `mnist28_row_cache_bridge`
- `mnist28_upscale_renderer`
- `cnn_system`
- `cnn_param_streamer`
- `cnn_spi_flash_reader`
- `cnn_compute_lwdd`
- `cnn_feature_buffer`
- `cnn_word_cache_buffer`
- `cnn_argmax`
- `leaf_cells`

## Clock Domains

- `I_clk`: main system/control/CNN domain.
- `PIXCLK`: camera pixel input domain.
- `pix_clk`: HDMI/video render pixel domain.
- HyperRAM generated clocks: vendor IP generated clocks under `u_camera_video/g_hw`.

Known crossing points:

- Debounced key/control pulse crossing into the flow-control path.
- Camera/video stream into MNIST capture and buffer ownership.
- MNIST buffer read paths used by preview and CNN.
- Preview row-cache bridge between `I_clk` RAM reads and `pix_clk` rendering.
- CNN result/status synchronization into the HDMI display path.
- Existing HyperRAM/vendor generated-clock paths, unchanged by this refactor.

## Top-Level Datapath

Camera input flows through `camera_video` and the VFB/HyperRAM display path for live HDMI. In parallel, the camera stream is captured/downscaled by `streaming_mnist_capture` into the MNIST buffer. The MNIST buffer feeds the preview bridge/renderer before the second key press starts `cnn_system`. `cnn_system` streams parameters from SPI flash through `cnn_param_streamer`, runs `cnn_compute_lwdd`, then exports class/status/logit debug data to the result display path.

## FSM Summary

- `camera_live_flow_control`: idle/live preview, capture request, preview wait, CNN start, result/status phases.
- `streaming_mnist_capture`: frame tracking, ROI/downscale accumulation, MNIST writeout, done pulse.
- `cnn_system`: input preload/start, parameter streamer coordination, compute start, done/error/result valid.
- `cnn_param_streamer`: request acceptance, SPI word range reads, ready/done/error handshake.
- `cnn_spi_flash_reader`: flash command/address shift, data shift, word assembly.
- `cnn_compute_lwdd`: grouped phases for load B1, pool/conv B1, load B2, pool/conv B2, C5 tiled loads, C5, C6 per-output-channel loads, dense, argmax/done.

## Leaf-Cell Conversion Table

| Old function/block | New leaf-cell module | File | Type | Resource impact | TB status |
| --- | --- | --- | --- | --- | --- |
| `addr_img28` | `leaf_addr_img28` | `src/leaf_cells/leaf_addr_img28.v` | Combinational | Included in final build | PASS |
| `addr_14c4` | `leaf_addr_14c4` | `src/leaf_cells/leaf_addr_14c4.v` | Combinational | Shared one instance for write/read operands | PASS |
| `addr_7c8` | `leaf_addr_7c8` | `src/leaf_cells/leaf_addr_7c8.v` | Combinational | Shared one instance for write/read operands | PASS |
| `addr_7c16` | `leaf_addr_7c16` | `src/leaf_cells/leaf_addr_7c16.v` | Combinational | Shared one instance for write/read operands | PASS |
| `select_i16` | `leaf_select_i16` | `src/leaf_cells/leaf_select_i16.v` | Combinational | Swept/optimized by synthesis | PASS |
| `sext32_to_acc` | `leaf_sext32_to_acc` | `src/leaf_cells/leaf_sext32_to_acc.v` | Combinational | Swept/optimized by synthesis | PASS |
| `input_u8_to_i16` | `leaf_input_u8_to_i16` | `src/leaf_cells/leaf_input_u8_to_i16.v` | Combinational | Swept/optimized by synthesis | PASS |
| `relu_shift_sat15` | `leaf_relu_shift_sat` with `SHIFT=15` | `src/leaf_cells/leaf_relu_shift_sat.v` | Combinational | Swept/optimized by synthesis | PASS |
| `relu_shift_sat16` | `leaf_relu_shift_sat` with `SHIFT=16` | `src/leaf_cells/leaf_relu_shift_sat.v` | Combinational | Swept/optimized by synthesis | PASS |

## Remaining Behavioral Code

Remaining helper functions in `cnn_compute_lwdd.v` after Phase 3:

- `scalar_c3`, `scalar_c4`
- `scalar_dense`
- Control tasks `start_contiguous_load`, `next_3x3_loop`, `next_sub_3x3_loop`

Reason left behavioral: `scalar_dense`, `scalar_c3`, and `scalar_c4` were each attempted and rolled back because PnR showed timing/resource regression. The control tasks own sequential FSM/register updates and are documented below instead of moduleized.

## Verification Summary

Simulation:

- `tb_leaf_cnn_helpers`: PASS
- `tb_cnn_param_streamer`: PASS
- `tb_cnn_compute_lwdd`: PASS, final build-passing version, finish time `679620755 ns`
- `tb_cnn_system`: PASS, final build-passing version, finish time `685410215 ns`
- `tb_cnn_reduced_top_integration`: PASS
- `tb_camera_live_state_flow`: PASS
- `tb_mnist28_upscale_renderer`: PASS
- `tb_streaming_mnist_capture_equivalence`: PASS

Gowin build:

- Command: `gw_sh.exe run_final_build.tcl`
- Result: PASS
- Bitstream generation: completed
- `PR0003`: absent in final build
- `TA2003`: absent in final build log
- Latches: 0
- BSRAM: 10/10
- DSP: 0.5/8, one `MULT18X18`

## Resource Comparison

| Metric | Baseline, 2026-05-31 11:21 build | After Phase 1, 2026-05-31 13:27 build |
| --- | ---: | ---: |
| Logic | 4494/4608 | 4511/4608 |
| LUT | 3724 | 3749 |
| ALU | 770 | 762 |
| Register | 2802/3612 | 2802/3612 |
| Logic FF | 2795/3456 | 2795/3456 |
| Latches | 0 | 0 |
| CLS | 2301/2304 | 2302/2304 |
| BSRAM | 10/10 | 10/10 |
| DSP | 0.5/8 | 0.5/8 |

Resource note: an initial one-instance-per-use address conversion placed at `2304/2304` CLS and failed with `PR0003`. The final implementation shares one leaf address module per feature-map shape with operand muxing, which recovered placement and left 2 CLS margin.

## Timing Comparison

| Clock | Baseline actual Fmax | After Phase 1 actual Fmax |
| --- | ---: | ---: |
| `I_clk`, constraint 27 MHz | 40.904 MHz | 38.753 MHz |
| `PIXCLK`, constraint 24 MHz | 79.359 MHz | 81.391 MHz |
| `pix_clk`, constraint 40 MHz | 35.441 MHz | 35.924 MHz |
| TMDS CLKOUTD, constraint 12.488 MHz | 77.943 MHz | 53.779 MHz |
| HyperRAM clkdiv, constraint 79.5 MHz | 64.114 MHz | 65.862 MHz |

Worst reported setup slack after Phase 1 is still on inherited HyperRAM/generated-clock paths, with worst setup slack `-6.992 ns`. The refactor did not introduce new CDC logic or new RAM paths.

## Phase 2: Parameter/Index Helper Leaf-Cell Attempt

Phase 2A converted only the C5 and Conv6 parameter word-offset helpers. This was the smallest safe parameter/indexing group because both helpers are combinational, used once each in the parameter-load path, and do not touch CNN arithmetic, quantization, tensor layout, RAM topology, FSM state count, or cycle timing.

Converted helpers:

- `c5_word_offset` -> `leaf_c5_word_offset`
- `conv6_word_offset` -> `leaf_conv6_word_offset`

Kept behavioral:

- `scalar_c1`, `scalar_c2`, `scalar_c3`, `scalar_c4`, `scalar_c5`
- `scalar_dense`
- `c5_cache_word`
- Control tasks `start_contiguous_load`, `next_3x3_loop`, `next_sub_3x3_loop`

Reason kept behavioral: the scalar helpers are in MAC/cache read states and a shared mode mux would add cross-layer fan-in. `c5_cache_word` is coupled to the C5 cache address and half-select flow. With only 2 CLS margin, those should be attempted separately only if synthesis can sweep the added hierarchy.

Files added:

- `src/leaf_cells/leaf_c5_word_offset.v`
- `src/leaf_cells/leaf_conv6_word_offset.v`
- `sim/tb_leaf_cnn_index_helpers.v`

Files modified:

- `src/cnn/cnn_compute_lwdd.v`
- `sim/cnn_tests.prj`
- `sim/cnn_modelsim.do`
- `full_system_GOWIN_camera_live_800x600_40_CNN.gprj`
- `reports/gate_level_leaf_cell_refactor_report.md`

| Helper | Action | New leaf-cell | Resource impact | Verification | Decision |
| ------ | ------ | ------------- | --------------- | ------------ | -------- |
| `c5_word_offset` | Moved from behavioral function to shared combinational leaf instance | `leaf_c5_word_offset` | 0 delta; synthesis swept `u_leaf_c5_word_offset` | `tb_leaf_cnn_index_helpers` PASS; CNN suite PASS; Gowin build PASS | Converted |
| `conv6_word_offset` | Moved from behavioral function to shared combinational leaf instance | `leaf_conv6_word_offset` | 0 delta; synthesis swept `u_leaf_conv6_word_offset` | `tb_leaf_cnn_index_helpers` PASS; CNN suite PASS; Gowin build PASS | Converted |
| `scalar_c1` | Kept behavioral | N/A | Not attempted; mode/shared mux risk | Covered indirectly by CNN suite | Kept behavioral |
| `scalar_c2` | Kept behavioral | N/A | Not attempted; mode/shared mux risk | Covered indirectly by CNN suite | Kept behavioral |
| `scalar_c3` | Kept behavioral | N/A | Not attempted; mode/shared mux risk | Covered indirectly by CNN suite | Kept behavioral |
| `scalar_c4` | Kept behavioral | N/A | Not attempted; mode/shared mux risk | Covered indirectly by CNN suite | Kept behavioral |
| `scalar_c5` | Kept behavioral | N/A | Not attempted; coupled to C5 cache half-select | Covered indirectly by CNN suite | Kept behavioral |
| `scalar_dense` | Kept behavioral | N/A | Not attempted; dense MAC path fan-in risk | Covered indirectly by CNN suite | Kept behavioral |
| `c5_cache_word` | Kept behavioral | N/A | Not attempted; C5 cache address flow should be isolated in a later attempt | Covered indirectly by CNN suite | Kept behavioral |

Phase 2 verification, 2026-05-31 16:13 build:

- `tb_leaf_cnn_helpers`: PASS
- `tb_leaf_cnn_index_helpers`: PASS
- `tb_camera_live_state_flow`: PASS
- `tb_mnist28_upscale_renderer`: PASS
- `tb_cnn_param_streamer`: PASS
- `tb_cnn_compute_lwdd`: PASS, finish time `679620755 ns`
- `tb_cnn_system`: PASS, finish time `685410215 ns`
- `tb_cnn_reduced_top_integration`: PASS, finish time `342700715 ns`
- Gowin build command: `C:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe run_final_build.tcl`
- Gowin build result: PASS
- Bitstream path: `impl/pnr/full_system_GOWIN_camera_live_800x600_40_CNN.fs`
- `PR0003`: absent
- `TA2003`: absent
- Logic and I/O latches: 0
- BSRAM: 10/10
- DSP: 0.5/8, one `MULT18X18`
- Git metadata: not available in this workspace; `git status` reports this directory is not a repository

Resource before/after:

| Metric | After Phase 1, 2026-05-31 13:27 build | After Phase 2, 2026-05-31 16:13 build | Delta |
| --- | ---: | ---: | ---: |
| Logic | 4511/4608 | 4511/4608 | 0 |
| LUT | 3749 | 3749 | 0 |
| ALU | 762 | 762 | 0 |
| Register | 2802/3612 | 2802/3612 | 0 |
| Logic FF | 2795/3456 | 2795/3456 | 0 |
| Latches | 0 | 0 | 0 |
| CLS | 2302/2304 | 2302/2304 | 0 |
| BSRAM | 10/10 | 10/10 | 0 |
| DSP | 0.5/8 | 0.5/8 | 0 |

Timing before/after:

| Clock | After Phase 1 actual Fmax | After Phase 2 actual Fmax |
| --- | ---: | ---: |
| `I_clk`, constraint 27 MHz | 38.753 MHz | 38.754 MHz |
| `PIXCLK`, constraint 24 MHz | 81.391 MHz | 81.391 MHz |
| `pix_clk`, constraint 40 MHz | 35.924 MHz | 35.924 MHz |
| TMDS CLKOUTD, constraint 12.488 MHz | 53.779 MHz | 53.780 MHz |
| HyperRAM clkdiv, constraint 79.5 MHz | 65.862 MHz | 65.863 MHz |

Worst setup slack after Phase 2 is `-6.992 ns`, again on inherited HyperRAM/generated-clock paths. The worst recovery slack is `-7.279 ns`, also on inherited HyperRAM reset/generated-clock paths. `I_clk` and `PIXCLK` setup/hold TNS remain 0.

Next recommended phase: keep Phase 3 narrow. The next safest candidate is a single isolated `c5_cache_word` attempt or documentation-only mapping for the remaining scalar helpers. Do not attempt a shared scalar mode module unless a quick synth/P&R proves it is swept or neutral.

## Phase 3: Scalar/Cache Helper Leaf-Cell Attempts

Phase 3 tried the remaining scalar/cache helpers one at a time. A helper was kept only when RTL simulation passed and Gowin PnR stayed resource/timing neutral versus the Phase 2 baseline.

Final kept conversions:

- `c5_cache_word` -> `leaf_c5_cache_word`
- `scalar_c5` -> `leaf_scalar_c5`
- `scalar_c1` -> `leaf_scalar_c1`
- `scalar_c2` -> `leaf_scalar_c2`

Rolled back attempts:

- `scalar_dense` -> `leaf_scalar_dense`
- `scalar_c3` -> `leaf_scalar_c3`
- `scalar_c4` -> `leaf_scalar_c4`

Control-task mapping, documentation only:

- `start_contiguous_load`: loads `load_offset`, `load_len`, `load_next_state`, resets `load_count`, then enters `S_LOAD_REQ`.
- `next_3x3_loop`: advances `cin`, `kx`, and `ky` for the main 3x3 convolution loops, otherwise moves to the caller-provided done state.
- `next_sub_3x3_loop`: advances `sub_cin`, `sub_kx`, and `sub_ky` for nested/sub-convolution loops, otherwise moves to the caller-provided done state.

These tasks were not moduleized because they own sequential state/register updates and FSM transitions. Splitting them into modules would add mux/fan-in or change cycle ownership with no safe resource margin.

| Helper/task | Attempt | New leaf-cell | Result | Resource delta | Timing delta | Verification | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `c5_cache_word` | Convert behavioral cache word index | `leaf_c5_cache_word` | Build PASS; swept by synthesis | 0 delta, final `4511/4608` logic, `2302/2304` CLS | Neutral, final `I_clk 38.754 MHz`, HyperRAM `65.863 MHz` | Helper PASS; compute/system/reduced PASS; Gowin PASS | Converted |
| `scalar_c5` | Convert C5 scalar parameter index | `leaf_scalar_c5` | Build PASS; swept by synthesis | 0 delta | Neutral | Helper PASS; compute/system/reduced PASS; Gowin PASS | Converted |
| `scalar_c1` | Convert B1 C1 scalar index | `leaf_scalar_c1` | Build PASS | 0 delta | Neutral | Helper PASS; compute/system/reduced PASS; Gowin PASS | Converted |
| `scalar_c2` | Convert B1 C2 scalar index | `leaf_scalar_c2` | Build PASS | 0 delta | Neutral | Helper PASS; compute/system/reduced PASS; Gowin PASS | Converted |
| `scalar_dense` | Convert dense scalar index | `leaf_scalar_dense` | Build PASS but timing regression | CLS `2301/2304`; other major resources unchanged | `I_clk 38.754 -> 31.570 MHz`; HyperRAM TNS worsened to `-37.425 ns` | Helper/integration PASS before PnR | Rolled back |
| `scalar_c3` | Convert B2 C3 scalar index | `leaf_scalar_c3` | Build PASS but timing regression | CLS `2301/2304`; logic unchanged | `I_clk 38.754 -> 36.325 MHz`; `pix_clk` TNS `-30.247 -> -60.081 ns`; HyperRAM TNS `-23.839 -> -35.557 ns` | Helper/integration PASS before PnR | Rolled back |
| `scalar_c4` | Convert B2 C4 scalar index | `leaf_scalar_c4` | Build PASS but resource/timing regression | Logic `4511 -> 4494`, CLS `2302 -> 2304/2304` | HyperRAM Fmax `65.863 -> 59.038 MHz`; `pix_clk` TNS `-30.247 -> -63.867 ns`; HyperRAM TNS `-23.839 -> -52.024 ns` | Helper/integration PASS before PnR | Rolled back |
| `start_contiguous_load` | Documentation only | N/A | Sequential FSM task kept behavioral | 0 delta | 0 delta | Covered by full CNN suite | Kept behavioral |
| `next_3x3_loop` | Documentation only | N/A | Sequential loop/FSM task kept behavioral | 0 delta | 0 delta | Covered by full CNN suite | Kept behavioral |
| `next_sub_3x3_loop` | Documentation only | N/A | Sequential loop/FSM task kept behavioral | 0 delta | 0 delta | Covered by full CNN suite | Kept behavioral |

Files added and kept:

- `src/leaf_cells/leaf_c5_cache_word.v`
- `src/leaf_cells/leaf_scalar_c5.v`
- `src/leaf_cells/leaf_scalar_c1.v`
- `src/leaf_cells/leaf_scalar_c2.v`

Files modified:

- `src/cnn/cnn_compute_lwdd.v`
- `sim/tb_leaf_cnn_index_helpers.v`
- `sim/cnn_tests.prj`
- `full_system_GOWIN_camera_live_800x600_40_CNN.gprj`
- `reports/gate_level_leaf_cell_refactor_report.md`

Remaining behavioral after Phase 3:

- `scalar_c3`
- `scalar_c4`
- `scalar_dense`
- `start_contiguous_load`
- `next_3x3_loop`
- `next_sub_3x3_loop`

Phase 3 final verification, 2026-05-31 18:55 build:

- `tb_leaf_cnn_helpers`: PASS
- `tb_leaf_cnn_index_helpers`: PASS
- `tb_camera_live_state_flow`: PASS
- `tb_mnist28_upscale_renderer`: PASS
- `tb_cnn_param_streamer`: PASS
- `tb_cnn_compute_lwdd`: PASS, finish time `679620755 ns`
- `tb_cnn_system`: PASS, finish time `685410215 ns`
- `tb_cnn_reduced_top_integration`: PASS, finish time `342700715 ns`
- `tb_streaming_mnist_capture_equivalence`: PASS, finish time `25517765 ns`
- Gowin build command: `C:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe run_final_build.tcl`
- Gowin build result: PASS, bitstream generated
- `PR0003`: absent
- `TA2003`: absent
- Logic and I/O latches: 0
- BSRAM: 10/10
- DSP: 0.5/8
- Git metadata: not available in this workspace; `git status` reports this directory is not a repository

Resource before/after Phase 3:

| Metric | After Phase 2 baseline | Phase 3 final | Delta |
| --- | ---: | ---: | ---: |
| Logic | 4511/4608 | 4511/4608 | 0 |
| LUT | 3749 | 3749 | 0 |
| ALU | 762 | 762 | 0 |
| Register | 2802/3612 | 2802/3612 | 0 |
| Latches | 0 | 0 | 0 |
| CLS | 2302/2304 | 2302/2304 | 0 |
| BSRAM | 10/10 | 10/10 | 0 |
| DSP | 0.5/8 | 0.5/8 | 0 |

Timing before/after Phase 3:

| Clock | After Phase 2 baseline | Phase 3 final |
| --- | ---: | ---: |
| `I_clk`, constraint 27 MHz | 38.754 MHz | 38.754 MHz |
| `PIXCLK`, constraint 24 MHz | 81.391 MHz | 81.391 MHz |
| `pix_clk`, constraint 40 MHz | 35.924 MHz | 35.924 MHz |
| TMDS CLKOUTD, constraint 12.488 MHz | 53.780 MHz | 53.780 MHz |
| HyperRAM clkdiv, constraint 79.5 MHz | 65.863 MHz | 65.863 MHz |

Final TNS after Phase 3 remains unchanged from Phase 2: `I_clk` and `PIXCLK` setup/hold TNS are 0, `pix_clk` setup TNS is `-30.247 ns`, and HyperRAM generated-clock setup TNS is `-23.839 ns`. Worst inherited setup slack remains `-6.992 ns`; worst recovery slack remains `-7.279 ns`.

Next recommended phase: stop structural scalar extraction on this device unless more CLS/timing margin is created first. The next useful work is constraint cleanup for inherited generated-clock/reset timing, or a resource-reduction pass that recovers CLS before any more hierarchy extraction.

## Risk Notes

- Resource margin remains extremely tight: final build uses `2302/2304` CLS and `10/10` BSRAM.
- The added leaf-cell hierarchy increases ModelSim wall-clock time for CNN tests, although simulated finish times and golden outputs are unchanged.
- Further structural work should be attempted only one small block at a time with immediate PnR. Any additional address/datapath duplication can trip `PR0003`.
- Remaining `scalar_c3`, `scalar_c4`, and `scalar_dense` helpers should stay behavioral unless more CLS/timing margin is recovered first; sequential accumulator/control splitting should wait for more margin.
