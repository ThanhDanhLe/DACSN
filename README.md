# DACSN

## Project Title

**Design an OV2640 Camera-Based Handwritten Digit Recognition System on Sipeed Tang Nano 4K FPGA Using a Post-Training Quantized CNN**

## Overview

This repository contains the source code, simulation files, implementation reports, and software model-preparation flow for a camera-based handwritten digit recognition system implemented on the **Sipeed Tang Nano 4K FPGA**.

The system captures live video from an **OV2640 camera**, displays the camera stream through **HDMI**, extracts a fixed region of interest, converts the selected region into a **28×28 MNIST-style image**, runs a **post-training quantized CNN** on FPGA, and displays the predicted digit directly on HDMI using a lightweight seven-segment-style overlay.

The main focus of this project is not to propose a new neural-network training algorithm. The main focus is the **FPGA hardware design and integration** of:

* OV2640 camera input
* HDMI live display
* HyperRAM/video frame buffering
* ROI-to-MNIST preprocessing
* SPI Flash parameter streaming
* fixed-point CNN inference
* CDC-safe result transfer
* HDMI seven-segment-style result overlay
* Verilog testbench verification
* Gowin FPGA build and board-level demonstration

## Final Project Status

The final FPGA candidate has been implemented and board-tested.

Final known status:

* Verilog simulation regression: **PASS**
* Gowin synthesis/place/route/bitstream: **PASS**
* PR0003 placement failure: **absent**
* TA2003 stale timing-constraint error: **absent**
* Latch inference: **0**
* Board smoke test: **PASS**
* Live OV2640 HDMI video: **PASS**
* MNIST preview after capture: **PASS**
* CNN computation: **PASS**
* HDMI seven-segment result overlay: **PASS**

Final resource/timing snapshot from the overlay candidate:

| Item                         |       Value |
| ---------------------------- | ----------: |
| Logic                        | 4548 / 4608 |
| CLS                          | 2304 / 2304 |
| BSRAM                        |     10 / 10 |
| DSP                          |     0.5 / 8 |
| I_clk Fmax                   |  36.316 MHz |
| pix_clk TNS                  |   -8.769 ns |
| HyperRAM generated-clock TNS |  -11.918 ns |

The design is extremely resource-constrained. The seven-segment overlay is intentionally minimal: one fixed green digit, no font ROM, no BSRAM, no multi-character text renderer.

## Repository Structure

```text
DACSN/
├── CNN_PTQ/
│   └── Python training, augmentation, post-training quantization,
│       model evaluation, and parameter export flow.
│
├── out_lwdd_numpy_ptq_fast/
│   └── Exported model/parameter/reference output artifacts used by
│       software verification and RTL testbenches.
│
├── full_system_GOWIN_camera_live_800x600_40_CNN/
│   ├── src/
│   │   ├── camera_video.v
│   │   ├── camera_live_top.v
│   │   ├── streaming_mnist_capture.v
│   │   ├── mnist_image_buffer_dualclk.v
│   │   ├── cnn/
│   │   │   ├── cnn_system.v
│   │   │   ├── cnn_compute_lwdd.v
│   │   │   ├── cnn_param_streamer.v
│   │   │   ├── cnn_spi_flash_reader.v
│   │   │   └── cnn_argmax.v
│   │   ├── cdc/
│   │   │   └── cdc_result_class_latch.v
│   │   ├── video/
│   │   │   ├── digit_to_7seg.v
│   │   │   ├── sevenseg_digit_overlay.v
│   │   │   ├── result_overlay_mux.v
│   │   │   ├── mnist28_row_cache_bridge.v
│   │   │   └── mnist28_upscale_renderer.v
│   │   ├── leaf_cells/
│   │   │   ├── leaf_rgb565_green_to_gray.v
│   │   │   ├── leaf_mnist_threshold_invert.v
│   │   │   ├── leaf_mnist_addr_28x28.v
│   │   │   ├── leaf_scalar_dense.v
│   │   │   └── other CNN helper leaf cells
│   │   ├── full_system_top.cst
│   │   └── full_system_top.sdc
│   │
│   ├── sim/
│   │   ├── cnn_modelsim.do
│   │   ├── cnn_tests.prj
│   │   ├── tb_digit_to_7seg.v
│   │   ├── tb_sevenseg_digit_overlay.v
│   │   ├── tb_cdc_result_class_latch.v
│   │   ├── tb_cnn_compute_lwdd.v
│   │   ├── tb_cnn_system.v
│   │   ├── tb_streaming_mnist_capture_equivalence.v
│   │   └── other unit/integration testbenches
│   │
│   ├── reports/
│   │   ├── gate_level_leaf_cell_refactor_report.md
│   │   ├── fsm_and_wrapper_refactor_report.md
│   │   ├── structural_candidate_refactor_report.md
│   │   └── sevenseg_overlay_and_wrapper_refactor_report.md
│   │
│   ├── full_system_GOWIN_camera_live_800x600_40_CNN.gprj
│   └── run_final_build.tcl
│
└── README.md
```

## Software Flow: CNN Training, PTQ, and Export

The CNN model is prepared offline in Python. The FPGA does not train the model. The software flow is:

```text
MNIST dataset
→ input preprocessing / normalization
→ data augmentation
→ floating-point CNN training
→ floating-point model evaluation
→ post-training quantization
→ integer reference inference
→ weight/bias export
→ flash/memory image generation
→ Verilog testbench reference files
```

The expected role of each software stage is:

| Stage                       | Purpose                                                                                          |
| --------------------------- | ------------------------------------------------------------------------------------------------ |
| MNIST loading               | Provides 28×28 grayscale digit samples and labels                                                |
| Data augmentation           | Improves tolerance to small geometric/input variations                                           |
| Floating-point training     | Trains the baseline CNN model                                                                    |
| Floating-point evaluation   | Measures baseline model behavior                                                                 |
| Post-training quantization  | Converts trained parameters into integer/fixed-point form                                        |
| Integer reference inference | Generates the golden reference for RTL verification                                              |
| Parameter export            | Produces weights, biases, memory files, binary/text files, expected logits, and expected classes |
| Verilog testbench input     | Allows the RTL CNN output to be compared against the quantized reference                         |

Important verification rule:

```text
The FPGA RTL is expected to match the post-training quantized integer reference,
not the original floating-point model directly.
```

A mismatch between the floating-point model and the quantized model is a quantization/model-preparation issue. A mismatch between the RTL and the quantized integer reference is a hardware or export-format issue.

## FPGA Hardware Flow

The final hardware datapath can be summarized as:

```text
OV2640 camera
→ camera byte packing / RGB565 video stream
→ HyperRAM / video frame buffering
→ HDMI live display
→ fixed ROI selection
→ RGB565 green-channel grayscale approximation
→ 16×16 block accumulation
→ 448×448 ROI to 28×28 MNIST-style downscaling
→ threshold and inversion
→ dual-clock MNIST image buffer
→ MNIST preview renderer
→ SPI Flash CNN parameter streaming
→ fixed-point CNN compute core
→ argmax predicted digit
→ CDC-safe result class latch
→ seven-segment-style HDMI overlay
```

The high-level user-visible flow is:

```text
Reset board
→ live OV2640 HDMI display
→ press key once: capture/process ROI and show MNIST preview
→ press key again: run CNN inference
→ show predicted digit on HDMI seven-segment overlay
→ repeat recognition flow
```

## Important FPGA Modules

### Camera and Display Path

| Module                       | Role                                                      |
| ---------------------------- | --------------------------------------------------------- |
| `camera_live_top.v`          | Top-level integration wrapper                             |
| `camera_video.v`             | Camera/video/HDMI datapath and result overlay integration |
| `OV2640_Controller.v`        | Camera configuration/control                              |
| `camera_byte_packer.v`       | Packs camera byte stream into RGB565 pixels               |
| `hyperram_mode_mux_direct.v` | Controls HyperRAM ownership/muxing                        |
| `video_frame_buffer.v`       | Video frame buffer path                                   |
| `dvi_tx.v`                   | HDMI/DVI output transmitter path                          |

### MNIST Preprocessing Path

| Module                          | Role                                                          |
| ------------------------------- | ------------------------------------------------------------- |
| `streaming_mnist_capture.v`     | Converts ROI stream into 28×28 MNIST-style image              |
| `leaf_rgb565_green_to_gray.v`   | Extracts green channel as lightweight grayscale approximation |
| `leaf_mnist_threshold_invert.v` | Applies threshold and inversion                               |
| `leaf_mnist_addr_28x28.v`       | Generates 28×28 image address using shift-add/sub logic       |
| `mnist_image_buffer_dualclk.v`  | Stores processed MNIST pixels across clock domains            |
| `mnist28_row_cache_bridge.v`    | Bridges MNIST buffer data to preview renderer                 |
| `mnist28_upscale_renderer.v`    | Displays processed MNIST image on HDMI                        |

### CNN Inference Path

| Module                    | Role                                                                               |
| ------------------------- | ---------------------------------------------------------------------------------- |
| `cnn_system.v`            | CNN subsystem wrapper                                                              |
| `cnn_compute_lwdd.v`      | Main fixed-point CNN inference core                                                |
| `cnn_param_streamer.v`    | Streams parameters to compute core                                                 |
| `cnn_spi_flash_reader.v`  | Reads parameter data from SPI Flash model/path                                     |
| `cnn_argmax.v`            | Selects predicted class from output logits                                         |
| `cnn_feature_buffer.v`    | Stores intermediate feature values                                                 |
| `cnn_word_cache_buffer.v` | Caches parameter/feature words                                                     |
| `leaf_*` helper cells     | Structural wrappers for arithmetic, indexing, selection, and activation operations |

### HDMI Result Overlay

| Module                     | Role                                                                                  |
| -------------------------- | ------------------------------------------------------------------------------------- |
| `cdc_result_class_latch.v` | Transfers final predicted class from CNN clock domain to HDMI pixel clock domain      |
| `digit_to_7seg.v`          | Converts class digit 0–9 into seven-segment mask                                      |
| `sevenseg_digit_overlay.v` | Draws one lightweight seven-segment digit using coordinate comparisons                |
| `result_overlay_mux.v`     | Documentation/reuse wrapper for overlay muxing; final path uses cheaper direct muxing |

## CDC Design Notes

The project uses several clock domains, including camera pixel clock, system/CNN clock, HDMI pixel clock, and generated clocks from vendor memory/video IP.

The final CNN result crosses from the system/CNN clock domain to the HDMI pixel clock domain using a held-class plus event-toggle CDC scheme:

```text
result_class/result_valid in I_clk
→ source-domain class latch
→ event toggle synchronizer
→ destination-domain displayed_class_pix
→ HDMI seven-segment overlay
```

This scheme assumes that the final class remains stable while `result_valid` is asserted in the result-display state. This assumption is valid for the current flow controller and was verified by simulation and board-level testing.

## Verification

The project includes unit-level and integration-level Verilog testbenches.

Important simulation tests include:

| Testbench                                | Purpose                                        |
| ---------------------------------------- | ---------------------------------------------- |
| `tb_digit_to_7seg`                       | Verifies digit-to-segment mask decoding        |
| `tb_sevenseg_digit_overlay`              | Verifies overlay pixel generation              |
| `tb_cdc_result_class_latch`              | Verifies CDC-safe result-class transfer        |
| `tb_leaf_cnn_helpers`                    | Verifies CNN helper leaf cells                 |
| `tb_leaf_cnn_index_helpers`              | Verifies CNN indexing/address helpers          |
| `tb_leaf_mnist_helpers`                  | Verifies MNIST preprocessing helper leaf cells |
| `tb_cnn_param_streamer`                  | Verifies parameter streaming                   |
| `tb_cnn_compute_lwdd`                    | Verifies fixed-point CNN compute core          |
| `tb_cnn_system`                          | Verifies CNN subsystem integration             |
| `tb_cnn_reduced_top_integration`         | Verifies reduced top integration path          |
| `tb_mnist28_upscale_renderer`            | Verifies MNIST preview rendering               |
| `tb_streaming_mnist_capture_equivalence` | Verifies ROI-to-MNIST preprocessing behavior   |
| `tb_camera_live_state_flow`              | Verifies top-level camera/CNN state flow       |

To run the main simulation regression:

```tcl
vsim -c -do sim/cnn_modelsim.do
```

## Gowin Build

Main Gowin project:

```text
full_system_GOWIN_camera_live_800x600_40_CNN/
└── full_system_GOWIN_camera_live_800x600_40_CNN.gprj
```

Main constraint files:

```text
src/full_system_top.cst
src/full_system_top.sdc
```

Final build script:

```text
run_final_build.tcl
```

Expected final build status:

```text
Synthesis: PASS
Placement: PASS
Routing: PASS
Bitstream generation: PASS
PR0003: absent
TA2003: absent
Latch inference: 0
```

Note: the current SDC is a practical project constraint file for the accepted build. Some generated-clock and vendor-IP timing warnings remain documented in reports. The project should not be described as fully timing-clean; it should be described as successfully implemented, bitstream-generated, and board-tested.

## Board-Level Demonstration

Board smoke test sequence:

```text
1. Program the generated bitstream.
2. Reset the Tang Nano 4K board.
3. Confirm live OV2640 camera video on HDMI.
4. Press the control key once.
5. Confirm that the ROI is captured/processed and the MNIST preview is shown.
6. Press the control key again.
7. Confirm that CNN inference runs.
8. Confirm that the predicted digit appears as a green seven-segment-style overlay on HDMI.
9. Repeat the flow with several handwritten digit samples.
```

Observed final board status:

```text
Live camera display: PASS
MNIST preview: PASS
CNN computation: PASS
Seven-segment HDMI result overlay: PASS
Repeat flow: PASS
```

## Repository Hygiene

The repository should keep source files, testbenches, constraints, reports, and reproducible model/export artifacts.

Files that should be kept:

```text
src/
sim/*.v
sim/*.do
sim/*.prj
sim/reference/
reports/
*.gprj
*.cst
*.sdc
run_final_build.tcl
CNN_PTQ/
out_lwdd_numpy_ptq_fast/
```

Generated files that should normally not be tracked:

```text
sim/work*/
sim/work_cnn/
*.qdb
*.qpg
*.qtl
_info
_vmake
transcript
*.wlf
*.vcd
*.fst
impl/temp/
impl/gwsynthesis/
impl/pnr/*.log
impl/pnr/*.html
impl/pnr/*.tr
impl/pnr/*.timing_paths
*.gprj.user
__pycache__/
*.pyc
.venv/
venv/
```

## Notes for Report Writing

When writing the project report, the GitHub source should be treated as the implementation reference.

Important report alignment points:

1. The FPGA does not train the CNN. Training and PTQ are performed offline in Python.
2. The FPGA verification target is the quantized integer reference model.
3. The camera preprocessing path converts a fixed ROI into a 28×28 MNIST-style image.
4. The preprocessing uses green-channel grayscale approximation, block accumulation, thresholding, and inversion.
5. The CNN core performs fixed-point inference using exported parameters.
6. The predicted class crosses into the HDMI pixel clock domain using `cdc_result_class_latch`.
7. The result is displayed using a lightweight HDMI seven-segment overlay.
8. The final design is resource-saturated, especially CLS and BSRAM.
9. The design passed simulation, Gowin implementation, and board-level smoke testing.
10. The report should not claim full timing closure beyond what the implementation reports support.

## Final Candidate Summary

The final source candidate is suitable for report writing and board demonstration. It demonstrates a complete FPGA-based embedded vision pipeline:

```text
camera input
→ image preprocessing
→ quantized CNN inference
→ visual HDMI result display
```

The main engineering achievement is integrating camera capture, video output, memory buffering, preprocessing, CNN inference, CDC handling, and visual result display into a resource-constrained Tang Nano 4K FPGA system.
# DACSN
