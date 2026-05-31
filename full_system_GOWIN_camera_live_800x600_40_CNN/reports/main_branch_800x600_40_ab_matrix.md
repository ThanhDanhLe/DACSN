# Main Branch 800x600@40 A/B Matrix

Date: 2026-05-24

| Step | Files changed | NN included | UART/debug included | Logic | LUT | ALU | Reg | CLS | BSRAM | DSP | pix req/Fmax | HyperRAM req/Fmax | setup | hold | TB result | Bitstream | Decision |
|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| Current 800x600@40 base | prior branch | no | one-sample minimal | 2908 | 2546 | 362 | 1798 | 1840 | 7 | 0 | 40.000 / 61.161 | 79.500 / 83.557 | -7.100 | -0.035 | equivalence PASS | yes | superseded by debug build |
| + capture dump/debug | `camera_live_top.v`, `uart_tx.v`, `capture_dump_controller.v`, `.gprj` | no | UART 784 dump | 3192 | 2830 | 362 | 1869 | 1924 | 7 | 0 | 40.000 / 65.428 | 79.500 / 79.741 | -6.770 | +0.570 | equivalence PASS | yes | keep for board dumps |
| + Python dump workflow | `final/verify/predict_fpga_capture_dump.py` | no | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | synthetic dump PASS | n/a | keep |
| + preload packer only | `streaming_mnist_preload_packer.v`, TB, `.gprj` | no | no runtime use | included above | included above | included above | included above | included above | included above | included above | included above | included above | included above | included above | preload TB PASS | yes | keep as verified future block |
| + NN modules compile-only | isolated `nn_compile_only_build/` | yes | diagnostic | 4549 | 3927 | 622 | 2664 | 2304 | 10 | 2 | n/a | n/a | n/a | n/a | not functional integration | no, placement failed | reject/direct integration blocked |
| + controlled NN integration | not attempted | no | no | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | blocked | n/a | collect board dumps first |

## Top Path After Debug Build

Top setup remains in the VFB/HyperRAM boundary:

`I_clk_ibuf -> u_camera_video/g_hw.u_hyperram/u_hpram_top/u_hpram_sync/cs_memsync[4] -> u_camera_video/g_hw.u_hyperram/u_hpram_top/u_dqce_clk_x2p`

Top hold is now positive; examples are DVI encoder and VFB FIFO sync paths around +0.57 ns.
