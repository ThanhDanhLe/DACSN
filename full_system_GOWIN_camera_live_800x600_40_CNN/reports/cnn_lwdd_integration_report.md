# CNN LWDD Integration Report

Project copy:

- Source project preserved: `full_system_GOWIN_camera_live_800x600_40_nn_integrated`
- CNN project: `full_system_GOWIN_camera_live_800x600_40_CNN`
- Gowin project: `full_system_GOWIN_camera_live_800x600_40_CNN.gprj`
- Synthesis project list: `impl/gwsynthesis/full_system_GOWIN_camera_live_800x600_40_CNN.prj`

Final verification date: 2026-05-26.

## Final Status

The CNN project still fits the target `GW1NSR-4C` device after adding the MNIST 28x28 HDMI preview state.

- Python bit-exact collateral generation: PASS
- MNIST 28x28 renderer ModelSim test: PASS
- ModelSim CNN suite: PASS, 4/4 testbenches
- Gowin synthesis/resource mapping: PASS
- Gowin place and route: PASS
- Gowin bitstream generation: PASS
- BSRAM: 10/10, unchanged by the new preview display
- Latches: 0 logic latches, 0 I/O latches
- Timing: P&R completed and bitstream generated. `I_clk`, `PIXCLK`, and `pix_clk` have zero TNS; remaining timing violations are inherited HyperRAM/VFB/generated-clock paths.

Bitstream outputs:

- `impl/pnr/full_system_GOWIN_camera_live_800x600_40_CNN.fs`
- `impl/pnr/full_system_GOWIN_camera_live_800x600_40_CNN.bin`

Latest artifact timestamps:

```text
BITSTREAM E:\Codework\DACSN\FPGA_GOWIN\full_system\full_system_GOWIN_camera_live_800x600_40_CNN\impl\pnr\full_system_GOWIN_camera_live_800x600_40_CNN.fs  LENGTH=1773017  WRITE=2026-05-26 07:20:49
BITSTREAM E:\Codework\DACSN\FPGA_GOWIN\full_system\full_system_GOWIN_camera_live_800x600_40_CNN\impl\pnr\full_system_GOWIN_camera_live_800x600_40_CNN.bin LENGTH=221368   WRITE=2026-05-26 07:20:49
```

## Board Flow

The old `nn_system` instance in `src/camera_live_top.v` remains replaced by `cnn_system` as `u_cnn_system`. The camera, HDMI, HyperRAM, VFB, streaming MNIST image-processing path, and CNN fixed-point datapath were not refactored.

Current user-visible FSM flow:

```text
S_CAMERA_LIVE
  -> capture/image_processing done
S_SHOW_PROCESSED
  -> key_count press
S_SHOW_MNIST_28X28
  -> key_count press
S_CNN_COMPUTE
  -> cnn output_valid/error
S_SHOW_RESULT
  -> key_count press returns to capture flow
```

CNN no longer starts automatically after `S_SHOW_PROCESSED`. The user must press `key_count` once to view the enlarged MNIST image and press it again to start CNN compute.

## MNIST 28x28 HDMI Preview

New files:

- `src/leaf_cells/leaf_addr_28_mul_shiftadd.v`
- `src/video/mnist28_upscale_renderer.v`
- `src/video/mnist28_row_cache_bridge.v`
- `sim/tb_mnist28_upscale_renderer.v`
- `sim/mnist28_renderer_modelsim.do`

Renderer mapping:

```text
screen_x 176..623 -> mnist_x = (screen_x - 176) >> 4
screen_y  76..523 -> mnist_y = (screen_y -  76) >> 4
addr = mnist_y*28 + mnist_x = (mnist_y << 5) - (mnist_y << 2) + mnist_x
RGB = {mnist_u8, mnist_u8, mnist_u8}
outside ROI = black
```

The 28x28 image is enlarged by nearest-neighbor to 448x448 and centered at the existing ROI: `X0=176`, `Y0=76`, `SCALE=16`. The renderer does not use division or general multiplication.

The original row-cache idea exceeded placement pressure on this nearly full device, so the final fitting implementation uses a single-pixel CDC cache:

- No new BSRAM.
- No direct HDMI pix_clk read of the MNIST BRAM.
- `mnist_image_buffer_dualclk` still uses its read port in `I_clk`.
- `mnist28_row_cache_bridge` transfers one requested MNIST pixel at a time between pix_clk and I_clk with toggle handshakes.
- The bridge is enabled only in `S_SHOW_MNIST_28X28`; it is disabled while CNN is computing, so it does not contend with CNN reads.
- Targeted SDC false paths are added only for this preview CDC payload and first-stage toggles.
- Display trade-off: the first few pixels after a 16-pixel cell change can be black while the I_clk read completes, but the preview remains resource-minimal and stable enough for the button-triggered demo.
- The top-level renderer instance uses `LOOKAHEAD=0` with the pixel-cache bridge so the requested MNIST coordinate follows the current HDMI coordinate.

## CNN Architecture

Implemented architecture:

1. conv1: 3x3 same, Cin=1, Cout=4, no bias, ReLU
2. conv2: 3x3 same, Cin=4, Cout=4, no bias, ReLU
3. maxpool1: 2x2, output 14x14x4
4. conv3: 3x3 same, Cin=4, Cout=8, no bias, ReLU
5. conv4: 3x3 same, Cin=8, Cout=8, no bias, ReLU
6. maxpool2: 2x2, output 7x7x8
7. conv5: 3x3 same, Cin=8, Cout=16, no bias, ReLU
8. conv6: 3x3 same, Cin=16, Cout=16, no bias, ReLU
9. global max pool: 7x7x16 -> 16
10. dense classifier: 16 -> 10, int16 weights, int32 bias
11. registered argmax, first maximum wins

## Tensor Memory Map

The SPI Flash base is `24'h200000`. The binary layout is fixed and little-endian.

| Tensor | Byte offset | Bytes | Word offset | Words | Shape |
| --- | ---: | ---: | ---: | ---: | --- |
| conv1.filters | 0 | 72 | 0 | 18 | [3,3,1,4] int16 |
| conv2.filters | 72 | 288 | 18 | 72 | [3,3,4,4] int16 |
| conv3.filters | 360 | 576 | 90 | 144 | [3,3,4,8] int16 |
| conv4.filters | 936 | 1152 | 234 | 288 | [3,3,8,8] int16 |
| conv5.filters | 2088 | 2304 | 522 | 576 | [3,3,8,16] int16 |
| conv6.filters | 4392 | 4608 | 1098 | 1152 | [3,3,16,16] int16 |
| classifier.weights | 9000 | 320 | 2250 | 80 | [16,10] int16 |
| classifier.bias | 9320 | 40 | 2330 | 10 | [10] int32 |

Total parameter size: 9360 bytes, 2340 32-bit words.

Conv scalar order is `(((ky*3 + kx)*Cin + cin)*Cout + cout)`. Dense scalar order is `in_idx*10 + out_idx`. Two int16 values are packed into each 32-bit word with the first scalar in bits `[15:0]` and the second in bits `[31:16]`.

## Fixed Point Contract

The bit-exact reference is `scripts/cnn_lwdd_bitexact.py`. Generated collateral:

- `src/cnn/cnn_quant_params.vh`
- `data/lwdd_params_words.mem`
- `data/cnn_tb_image_words.mem`
- `data/cnn_tb_logits.mem`
- `data/cnn_tb_classes.mem`
- `data/cnn_golden_summary.txt`

Hardware fixed-point behavior:

- Input: unsigned MNIST byte from each 16-bit pixel lower byte, stored as signed int16 in range 0..255.
- Conv accumulation: signed int64.
- Conv activation: arithmetic right shift, signed ReLU compare, saturate to 0..32767.
- Conv shifts: conv1=15, conv2=16, conv3=16, conv4=16, conv5=16, conv6=16.
- Pooling: signed int16 max.
- Dense: signed int64 accumulation.
- Dense bias: int32 bias is sign-extended to int64 and arithmetic-shifted right by 11 before weight products are added.
- Argmax: compares signed int64 logits, stable first-maximum behavior.

The RTL tests compare against this bit-exact Python model, not float inference. No RTL float logic is used.

## Memory-Minimal CNN Datapath

Final CNN memory architecture:

- No full 2340-word parameter cache.
- Weights are streamed from SPI Flash through `cnn_param_streamer`.
- Only the active layer/tile is cached in the 512x32 synchronous weight cache.
- conv5 is tiled into output-channel groups so the cache stays <= 512x32.
- conv1+conv2+pool1 are fused/recomputed to avoid storing the full 28x28x4 conv1 feature map.
- conv3+conv4+pool2 are fused/recomputed to avoid storing the full 14x14x8 conv3 feature map.
- No separate CNN `image_mem`; the board path reads the existing 28x28 MNIST image buffer.
- Two reusable 784-entry int16 feature buffers hold pooled/intermediate data instead of two full 3136-entry feature maps.
- Dense/classifier stores only the 16-value global max vector and streams/caches small classifier parameter ranges.
- `streaming_mnist_capture` keeps `col_sum` RAM-inferred; synthesis logs confirm RAM extraction.

This trades speed for BSRAM fit, which is acceptable for the button-triggered demo.

## Known Bug Fixes In Final RTL

- Fixed conv5 -> conv6 transition by resetting `cout <= 0` before entering conv6 weight load.
- Fixed ReLU/saturation comparisons to use signed constants, preventing negative accumulators from being treated as unsigned positive values.
- Connected compute debug ports in `cnn_system` so ModelSim runs without port-count warnings.
- Removed the full parameter cache and separate CNN image memory that caused the old 23 BSRAM resource failure.
- Added `S_SHOW_MNIST_28X28` and delayed CNN start until the second key press after processed-image display.
- Replaced the attempted row-cache preview bridge with a single-pixel CDC cache to keep placement/resource fit.

## File List Checks

- `.gprj` includes `src/leaf_cells/leaf_addr_28_mul_shiftadd.v`, `src/video/mnist28_row_cache_bridge.v`, and `src/video/mnist28_upscale_renderer.v` with `enable="1"`.
- `.gprj` includes `sim/tb_mnist28_upscale_renderer.v` with `enable="0"`.
- `impl/gwsynthesis/full_system_GOWIN_camera_live_800x600_40_CNN.prj` includes the new preview RTL files.
- `src/camera_live_top.v` instantiates `cnn_system` as `u_cnn_system`.
- No `nn_system` instance remains in `src/camera_live_top.v`.

## Verification Commands

Run from the project root:

```powershell
python scripts\cnn_lwdd_bitexact.py
vsim -c -do sim\mnist28_renderer_modelsim.do
vsim -c -do sim\cnn_modelsim.do
& 'C:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe' run_final_build.tcl
```

Final logs:

- `sim/log_python_cnn_lwdd_bitexact_mnist28_final.txt`
- `sim/log_tb_mnist28_upscale_renderer_pixel_cache.txt`
- `sim/log_cnn_modelsim_mnist28_final.txt`
- `impl/log_gowin_final_build_mnist28_final.txt`

Python reference output:

```text
Generated CNN quant include and golden vectors in E:\Codework\DACSN\FPGA_GOWIN\full_system\full_system_GOWIN_camera_live_800x600_40_CNN
```

Renderer PASS summary:

```text
# PASS tb_mnist28_upscale_renderer
#    Time: 146 ns  Iteration: 0  Instance: /tb_mnist28_upscale_renderer
# Errors: 0, Warnings: 0
```

ModelSim CNN PASS summary:

```text
# PASS tb_cnn_param_streamer
#    Time: 11335 ns  Iteration: 1  Instance: /tb_cnn_param_streamer
# Errors: 0, Warnings: 0

# PASS tb_cnn_compute_lwdd
#    Time: 679620755 ns  Iteration: 1  Instance: /tb_cnn_compute_lwdd
# Errors: 0, Warnings: 0

# PASS tb_cnn_system
#    Time: 685410215 ns  Iteration: 1  Instance: /tb_cnn_system
# Errors: 0, Warnings: 0

# PASS tb_cnn_reduced_top_integration
#    Time: 342700165 ns  Iteration: 1  Instance: /tb_cnn_reduced_top_integration
# Errors: 0, Warnings: 0
```

## Latency

The CNN latency is unchanged by the preview display because the CNN datapath was not refactored.

Measured in simulation with a 10 ns clock:

- `tb_cnn_compute_lwdd`: 679,620,755 ns for two compute samples, about 67,962,076 cycles total, about 33,981,038 cycles/sample.
- `tb_cnn_system`: 685,410,215 ns for two wrapper inferences, about 68,541,022 cycles total, about 34,270,511 cycles/inference.
- `tb_cnn_reduced_top_integration`: 342,700,165 ns for one reduced-top inference, about 34,270,017 cycles.

At the board `I_clk` constraint of 27 MHz, the wrapper/reduced-top estimate is roughly 1.27 seconds per CNN inference.

## Resource Summary

Final report: `impl/pnr/full_system_GOWIN_camera_live_800x600_40_CNN.rpt.txt`

Before MNIST preview display, the fitting CNN build used:

```text
Logic 4326/4608, LUT 3600, ALU 726, Register 2708/3612, CLS 2284/2304, BSRAM 10/10, DSP 0.5/8
```

After adding the preview display:

```text
Logic                       | 4487/4608                           | 98%
  --LUT,ALU,ROM16           | 4487(3737 LUT, 750 ALU, 0 ROM16)
  --SSRAM(RAM16)            | 0
Register                    | 2786/3612                           | 78%
  --Logic Register as Latch | 0/3456                              | 0%
  --Logic Register as FF    | 2779/3456                           | 81%
  --I/O Register as Latch   | 0/156                               | 0%
  --I/O Register as FF      | 7/156                               | 5%
CLS                         | 2300/2304                           | 100%
I/O Port                    | 29/39                               | 75%
IOLOGIC                     | 28/53                               | 53%
BSRAM                       | 10/10                               | 100%
  --SDPB                    | 4
  --SDPX9B                  | 5
  --pROM                    | 1
DSP                         | 0.5/8                               | 7%
  --MULT18X18               | 1
```

Delta from the pre-preview fitting build:

```text
Logic +161, LUT +137, ALU +24, Register +78, CLS +16, BSRAM +0, DSP +0
```

BSRAM remains exactly `10/10`, meeting the acceptance target of <= 10/10.

## Timing Summary

Final timing report: `impl/pnr/full_system_GOWIN_camera_live_800x600_40_CNN.tr`

```text
<Numbers of Endpoints Analyzed>:8124
<Numbers of Setup Violated Endpoints>:846
<Numbers of Hold Violated Endpoints>:1
```

Max frequency summary:

```text
Clock Name                                                       Constraint    Actual Fmax
I_clk                                                            27.000 MHz    34.527 MHz
PIXCLK                                                           24.000 MHz    47.432 MHz
pix_clk                                                          40.000 MHz    46.548 MHz
u_camera_video/g_hw.u_tmds_pll/.../CLKOUTD.default_gen_clk       12.488 MHz    65.291 MHz
u_camera_video/g_hw.u_hyperram/u_hpram_top/clkdiv/CLKOUT...      79.500 MHz    68.005 MHz
```

Total negative slack summary:

```text
I_clk                                                            setup 0.000, hold 0.000, endpoints 0
PIXCLK                                                           setup 0.000, hold 0.000, endpoints 0
pix_clk                                                          setup 0.000, hold 0.000, endpoints 0
u_camera_video/g_hw.u_hyperram/u_hpram_top/clkdiv/CLKOUT...      setup -35.067, endpoints 40
u_camera_video/g_hw.u_hyperram/u_hpram_top/clkdiv/CLKOUT...      hold 0.000, endpoints 0
```

Worst setup paths are still in the existing HyperRAM/VFB/generated-clock area:

```text
1  Slack -6.649  I_clk -> mem_pll CLKOUT
   From u_camera_video/g_hw.u_hyperram/u_hpram_top/u_hpram_sync/cs_memsync[4]/Q
   To   u_camera_video/g_hw.u_hyperram/u_hpram_top/u_dqce_clk_x2p/CE

2  Slack -6.297  pix_clk -> HyperRAM clkdiv
   From u_camera_video/g_hw.u_syn_gen/O_vs_s0/Q
   To   u_camera_video/g_hw.u_frame_buffer/.../u_dma_frame_ctrl/vout_vs_n_sync0_s1/D

3  Slack -4.330  mem_pll CLKOUT -> HyperRAM clkdiv
   From u_camera_video/g_hw.u_hyperram/u_hpram_top/u_dll/CLKIN
   To   u_camera_video/g_hw.u_hyperram/u_hpram_top/u_hpram_wd/step_Z[8]/D
```

The new MNIST preview CDC false paths are active in the timing report, and no `mnist28_row_cache_bridge` path appears in the reported worst setup paths after constraints.

## Important Remaining Warnings

Final Gowin log: `impl/log_gowin_final_build_mnist28_final.txt`

- `EX1998`: undriven net inside generated `hyperram_memory_interface.v`.
- `EX0211`: undriven HyperRAM generated-IP bits such as `rd_data[10]`, `rd_data[5]`, and `addr_d[19]`, assigned to Z, with simulation mismatch warning.
- `IF0007`: `syn_ramstyle/syn_romstyle` attribute warning at `src/streaming_mnist_capture.v:66`; the same log confirms RAM extraction for `col_sum`.
- `NL0002`: `leaf_reg_bus_rst` instance `g_hw.u_video_stream_pipe_reg` swept in optimization.
- `CK3000`, `TA1132`, `TA1117`: clock relationship warnings among `I_clk`, `PIXCLK`, and HyperRAM generated clocks.
- `PR1014`: generic routing resource used for constrained clock signal `I_clk_d`.

Checks from final reports:

- Logic latches: 0
- I/O latches: 0
- ModelSim warnings: 0
- Final Gowin errors: none
- No new multiple-driver warning was reported
- No flash pin/MSPI error was reported

Flash pin/config notes from final P&R:

```text
FLASH_CS_N   2/0   out  IOT10[B]  MCS_N/D5  LVCMOS33
FLASH_SCLK   1/0   out  IOT10[A]  MCLK/D4   LVCMOS33
FLASH_MOSI   48/1  out  IOT11[A]  MO/D6     LVCMOS33
FLASH_MISO   47/1  in   IOT11[B]  MI/D7     LVCMOS33
```

## Rebuild Notes

Use this command to rebuild the final bitstream:

```powershell
& 'C:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe' run_final_build.tcl
```

The final bitstream to program is:

```text
E:\Codework\DACSN\FPGA_GOWIN\full_system\full_system_GOWIN_camera_live_800x600_40_CNN\impl\pnr\full_system_GOWIN_camera_live_800x600_40_CNN.fs
```
