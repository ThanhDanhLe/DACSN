# structural_candidate Manifest

This variant is represented by the current source tree. The stable fallback copy is:

- `variants/stable_baseline_20260531_relaxed_phase`

Kept structural RTL changes:

- `src/leaf_cells/leaf_scalar_dense.v`
- `src/leaf_cells/leaf_rgb565_green_to_gray.v`
- `src/cnn/cnn_compute_lwdd.v`
- `src/streaming_mnist_capture.v`

Verification artifacts:

- Final ModelSim script: `sim/cnn_modelsim.do`
- Final streaming equivalence bench: `sim/tb_streaming_mnist_capture_equivalence.v`
- Structural report: `reports/structural_candidate_refactor_report.md`
- Final bitstream: `impl/pnr/full_system_GOWIN_camera_live_800x600_40_CNN.fs`

Final metrics:

- Logic `4511/4608`, LUT `3749`, ALU `762`, register `2802/3612`, CLS `2301/2304`
- Latches `0`, BSRAM `10/10`, DSP `0.5/8`
- `I_clk 31.570 MHz`, `PIXCLK 83.031 MHz`, `pix_clk 36.079 MHz`, HyperRAM clkdiv `67.131 MHz`
- `pix_clk` TNS `-18.439 ns`, HyperRAM TNS `-37.425 ns`

Board status: PnR accepted, board smoke pending.
