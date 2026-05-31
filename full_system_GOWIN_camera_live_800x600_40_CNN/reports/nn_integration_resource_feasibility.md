# NN Integration Resource Feasibility

Date: 2026-05-24

## Current Branch Resources

Current debug/export branch:

| Metric | Value |
|---|---:|
| Logic | 3192 / 4608 |
| LUT | 2830 |
| ALU | 362 |
| Reg | 1869 / 3612 |
| CLS | 1924 / 2304 |
| BSRAM | 7 / 10 |
| DSP | 0 / 8 |

## NN Modules Considered

Copied into an isolated compile-only variant under:

`nn_compile_only_build/`

Modules:

- `nn_system.v`
- `nn_spi_param_streamer.v`
- `nn_compute_mlp16_pocket.v`
- `nn_mac_unit.v`
- `nn_weight16_unpack2.v`
- `nn_bram_sdp.v`
- `nn_pocket_tanh_activation_seq_runtime.v`
- `nn_signed_divider_seq.v`
- `nn_argmax_stream.v`
- required leaf arithmetic/register helpers

## Compile/P&R Experiment

The variant instantiated `nn_system` enough to force resource accounting, without connecting it to the main branch as an accepted feature. The accepted branch source was not merged with NN.

One pin-placement diagnostic issue occurred when trying to use the board MSPI pins dynamically. In the compile-only variant only, those flash constraints were removed so P&R could answer the resource-fit question.

## Result

Placement failed:

`ERROR (PR0003): Failed to place with '46 LUT(s)(equivalent, include LUT/MUX/ALU) unPlaced'`

Failed-place resource summary:

| Metric | Value |
|---|---:|
| Logic | 4549 / 4608 |
| LUT | 3927 |
| ALU | 622 |
| Reg | 2664 / 3612 |
| CLS | 2304 / 2304 |
| BSRAM | 10 / 10 |
| DSP | 2 / 8 |

## Analysis

Direct NN addition is at the hard edge:

- BSRAM reaches 10/10.
- CLS reaches 2304/2304.
- Placement fails even before timing can be evaluated.
- The UART dump/debug logic is useful now, but likely must be disabled or replaced with a cheaper result/debug path before full NN integration.

## Reuse Notes

Potentially reusable:

- current dual-clock MNIST RAM as the only capture image buffer,
- `streaming_mnist_preload_packer`,
- `nn_system` and existing SPI direct-stream flow,
- existing parameter binary at SPI flash offset `0x200000`.

Do not copy:

- old VFB readback image-processing path,
- old snapshot CDC held-bus payload path,
- processed 28x28 preview,
- bit-box/debug overlays.

## Decision

Do not integrate NN in this pass. Collect real 784-pixel board dumps first, then retry NN integration with debug UART disabled and only the minimal preload/result path enabled.
