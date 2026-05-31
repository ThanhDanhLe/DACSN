# NN Integration Build Report

Date: 2026-05-24

Branch:

`full_system_GOWIN_camera_live_800x600_40_nn_integrated`

## Build

Command:

```powershell
cd full_system_GOWIN_camera_live_800x600_40_nn_integrated
& 'C:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe' run_final_build.tcl
```

Bitstream:

`impl/pnr/full_system_GOWIN_camera_live_800x600_40_nn_integrated.fs`

Bitstream size:

`1,773,017 bytes`

Last build time:

`2026-05-24 18:56:27`

## Resource Use

| Resource | Usage |
|---|---:|
| Logic | `4397/4608` |
| LUT | `3706` |
| ALU | `691` |
| Register | `2666/3612` |
| CLS | `2281/2304` |
| BSRAM | `10/10` |
| DSP | `2/8` |

## Timing

| Clock | Required | Achieved Fmax | Status |
|---|---:|---:|---|
| `I_clk` | `27.000 MHz` | `39.191 MHz` | PASS |
| `PIXCLK` | `24.000 MHz` | `60.109 MHz` | PASS |
| `pix_clk` | `40.000 MHz` | `55.784 MHz` | PASS |
| HyperRAM `clkdiv` | `79.500 MHz` | `69.765 MHz` | FAIL |

Worst setup slack:

`-8.070 ns`

Worst hold slack:

`-0.916 ns`

## Top Remaining Setup Paths

| Slack | Classification | From | To |
|---:|---|---|---|
| `-8.070 ns` | HyperRAM/VFB boundary | `u_hpram_sync/cs_memsync[4]` | `u_dqce_clk_x2p/CE` |
| `-6.449 ns` | pix_clk -> HyperRAM VFB sync | `u_syn_gen/O_vs_s0` | `vout_vs_n_sync0_s1` |
| `-5.718 ns` | HyperRAM DLL/vendor path | `u_dll/CLKIN` | `u_hpram_wd/step_Z[8]` |
| `-5.661 ns` | HyperRAM DLL/vendor path | `u_dll/CLKIN` | `u_hpram_wd/step_Z[7]` |
| `-5.604 ns` | HyperRAM DLL/vendor path | `u_dll/CLKIN` | `u_hpram_wd/step_Z[6]` |

## Top Remaining Hold Paths

| Slack | Classification | From | To |
|---:|---|---|---|
| `-0.916 ns` | HyperRAM calibration/vendor path | `read_calibration[0].calib[0]` | `iserdes_gen[7].u_ides4/CALIB` |
| `-0.143 ns` | HyperRAM calibration/vendor path | `read_calibration[0].calib[0]` | `iserdes_gen[5].u_ides4/CALIB` |
| `-0.143 ns` | HyperRAM calibration/vendor path | `read_calibration[0].calib[0]` | `iserdes_gen[6].u_ides4/CALIB` |
| `-0.121 ns` | HyperRAM calibration/vendor path | `read_calibration[0].calib[0]` | `iserdes_gen[4].u_ides4/CALIB` |

## SDC Note

A small targeted exception was added only for first-stage display-result synchronizer flops in `camera_video.v`:

- `result_valid_pix0`
- `result_busy_pix0`
- `result_error_pix0`
- `result_class_pix0[3:0]`

These are display-only status/control crossings from `I_clk` to `pix_clk`. No broad clock-domain false path was added. Normal datapath, NN datapath, camera capture, and VFB/HyperRAM paths remain timed.

## Decision

Build accepted as an integration/board-test candidate, not as timing-closed.

The integrated NN path fits, the bitstream is generated, and camera/live pixel timing remains at 800x600@40. The remaining timing report is still dominated by VFB/HyperRAM generated-clock and vendor-boundary paths, not the streaming MNIST capture or preload packer.

