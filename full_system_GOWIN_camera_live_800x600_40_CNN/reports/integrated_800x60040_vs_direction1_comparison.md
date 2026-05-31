# Integrated 800x600@40 vs Direction-1 Full System

Date: 2026-05-24

## Summary

The new branch keeps the board-proven 800x600@40 live camera base and adds the verified NN/SPI/preload path from `full_system_GOWIN_nn_uart_standalone`.

The old `full_system_GOWIN` direction-1 branch remains archive/reference only. It is not modified by this integration.

## Architecture Comparison

| Item | Old `full_system_GOWIN` direction 1 | New `800x600@40_nn_integrated` |
|---|---|---|
| Video timing | 74.25 MHz-class HDMI timing | true 800x600@40 |
| Live camera | yes | yes |
| NN input source | frozen VFB/ROI readback path | direct streaming camera capture |
| Uses VFB as NN input | yes | no |
| Streaming MNIST capture | no | yes |
| NN/SPI path | yes | yes, imported from verified `nn_uart_standalone` |
| Processed 28x28 preview | yes | no |
| Result display | HDMI seven-seg/result overlay | lightweight HDMI seven-seg overlay |
| UART dump/debug | not primary | optional, disabled by default |
| Params | `direct_stream_params.bin` at `0x200000` | same |

## Resource and Timing

| Metric | Old direction 1 | New integrated branch |
|---|---:|---:|
| Logic | `4424/4608` | `4397/4608` |
| LUT | `3716` | `3706` |
| ALU | `708` | `691` |
| Register | `2737` | `2666` |
| CLS | `2287/2304` | `2281/2304` |
| BSRAM | `10/10` | `10/10` |
| DSP | `2/8` | `2/8` |
| Pixel required | `74.250 MHz` | `40.000 MHz` |
| Pixel Fmax | `67.849 MHz` | `55.784 MHz` |
| HyperRAM required | `79.500 MHz` | `79.500 MHz` |
| HyperRAM Fmax | `72.185 MHz` | `69.765 MHz` |
| Worst setup slack | `-8.474 ns` | `-8.070 ns` |
| Worst hold slack | `-1.302 ns` | `-0.916 ns` |

## Stability Interpretation

- Pixel-clock timing is materially safer in the new branch because the required pixel clock is `40 MHz`, not `74.25 MHz`.
- HyperRAM/VFB timing is still not clean in the report.
- The remaining worst setup/hold paths are still VFB/HyperRAM generated-clock, sync, and vendor-calibration paths.
- Streaming capture and preload packing are not top timing limiters.
- The new branch avoids using the VFB readback path as the NN input, so VFB/display artifacts are less likely to corrupt NN input.

## Accuracy and Consistency Status

Board accuracy comparison is pending.

Known-good baseline facts:

- `nn_uart_standalone` passed board test.
- Python prediction and FPGA/HDMI result matched in the standalone NN path.
- Therefore NN arithmetic, SPI flash parameter read, parameter layout, and preload convention are treated as known-good.

Required integrated-board comparison:

1. Program params to SPI flash offset `0x200000`.
2. Program the integrated bitstream.
3. Capture digits 0..9, five captures per digit.
4. For each capture, compare:
   - Python prediction from the exact 784-pixel capture dump, if enabled
   - integrated FPGA HDMI result
   - old direction-1 result on the same physical input

Decision rule:

- Python wrong and FPGA same wrong: model/input-domain mismatch.
- Python correct and FPGA wrong: preload/SPI/NN integration issue.
- Repeated capture dumps unstable: capture/lighting/timing instability.
- HDMI live view artifact but stable capture dump: display/VFB issue, not NN input corruption.

