# Main Branch 800x600@40 Development Report

Date: 2026-05-24

## Branch Confirmation

`full_system_GOWIN_camera_live_800x600_40` is the main practical branch. Board test confirmed stable, visually good 800x600@40 live camera output.

`full_system_GOWIN` remains reference/archive only. No merge was made.

## Implemented This Pass

- Added optional 784-pixel UART capture dump:
  - `src/uart_tx.v`
  - `src/capture_dump_controller.v`
  - `camera_live_top.v` wiring
- Added Python dump inference workflow:
  - `final/verify/predict_fpga_capture_dump.py`
- Added verified preload packer for future NN integration:
  - `src/streaming_mnist_preload_packer.v`
  - `sim/tb_streaming_mnist_preload_pack.v`
- Added isolated NN compile-only resource experiment:
  - `nn_compile_only_build/`

## Verification

- `tb_streaming_mnist_capture_equivalence.v`: PASS, still matches mode-2 reference.
- `tb_streaming_mnist_preload_pack.v`: PASS.
- `predict_fpga_capture_dump.py`: PASS on synthetic 784-pixel dump.
- Gowin P&R for debug branch: PASS, bitstream generated.

## Debug Branch Metrics

| Metric | Value |
|---|---:|
| Logic | 3192 / 4608 |
| LUT | 2830 |
| ALU | 362 |
| Reg | 1869 / 3612 |
| CLS | 1924 / 2304 |
| BSRAM | 7 / 10 |
| DSP | 0 / 8 |
| pix required/Fmax | 40.000 / 65.428 MHz |
| HyperRAM required/Fmax | 79.500 / 79.741 MHz |
| setup slack | -6.770 ns |
| hold slack | +0.570 ns |

Bitstream:

`impl/pnr/full_system_GOWIN_camera_live_800x600_40.fs`

## NN Feasibility

Direct NN compile-only addition was tested in `nn_compile_only_build/`.

Placement failed:

`Failed to place with 46 LUT(s) unPlaced`

Resource at failure:

- Logic: 4549 / 4608
- LUT: 3927
- ALU: 622
- Reg: 2664 / 3612
- CLS: 2304 / 2304
- BSRAM: 10 / 10
- DSP: 2 / 8

This means NN integration is not accepted yet. The next attempt should disable UART dump and keep only the preload/result path.

## Next Board Test

1. Program `impl/pnr/full_system_GOWIN_camera_live_800x600_40.fs`.
2. Trigger capture on a known digit.
3. Capture UART dump from the debug TX path.
4. Run `predict_fpga_capture_dump.py`.
5. Repeat 10 captures for one fixed digit and compare stability.

## Decision

Collect board dumps first. Do not integrate NN until the captured 784-pixel input is proven stable and Python inference says the current preprocessing/model can classify it.
