# Preload Packing Verification

Date: 2026-05-24

## Module

`src/streaming_mnist_preload_packer.v`

This module is prepared for later NN integration only. It is not connected to `nn_system` in the accepted branch.

## Convention

Matches the accepted full-system preload convention:

- read MNIST RAM addresses `0..783`,
- even pixel goes to `preload_data[15:0]`,
- odd pixel goes to `preload_data[31:16]`,
- `preload_addr = mnist_addr[9:1]`,
- exactly 392 preload words are generated,
- `done` asserts after the final word.

## Testbench

`sim/tb_streaming_mnist_preload_pack.v`

Patterns tested:

- increasing pixel values `0..783 mod 256`,
- all zero,
- one-hot at address 0,
- one-hot at address 1,
- one-hot at address 782,
- one-hot at address 783,
- pseudo-random 784-pixel image.

## Result

Command:

```powershell
cd full_system_GOWIN_camera_live_800x600_40\sim
vlib work_preload
vlog -quiet -work work_preload ..\src\streaming_mnist_preload_packer.v tb_streaming_mnist_preload_pack.v
vsim -c -quiet work_preload.tb_streaming_mnist_preload_pack -do "run -all; quit"
```

Result:

`TB PASS: streaming_mnist_preload_packer packing checks passed`

Transcript:

`sim/preload_pack_transcript.log`

## Decision

Packing logic is verified and can be used in the later controlled NN integration attempt, subject to resource fit.
