# UART Dump Handshake Fix Report

Date: 2026-05-24

## Problem

Board UART logs on ESP32 showed dropped/corrupted dump text:

```text
6,x0
7,x0
1000
120B
EDCPUE
```

The UART wiring/baud were partly alive, but the dump FSM could advance text/address state using only `!uart_busy`. That made the byte launch contract too implicit.

## RTL Fix

Changed:

- `src/uart_tx.v`
- `src/capture_dump_controller.v`
- `src/camera_live_top.v`

`uart_tx` now exposes:

- `tx_ready = state == S_IDLE`

`capture_dump_controller` now has a pending-byte register:

- `pending_data`
- `pending_valid`
- `uart_start = pending_valid & uart_ready`

The dump FSM queues one byte and does not advance string index, address digit state, pixel index, or footer index until:

```verilog
byte_accepted = pending_valid & uart_ready
```

Thus each byte is held stable until the UART accepts it.

## UART Test Mode

Added parameter:

```verilog
parameter UART_TEST_MODE = 0
```

When set to `1` on `camera_live_top`, the controller continuously sends:

```text
HELLO_UART_TEST\r\n
```

The normal build keeps `UART_TEST_MODE=0`.

Hardware UART settings remain:

- `CLK_HZ = 27000000`
- `BAUD = 115200`
- 8N1

## Testbench

Added:

`sim/tb_capture_dump_controller.v`

The TB instantiates `capture_dump_controller` and the real `uart_tx`, triggers one capture, records bytes only when the UART handshake accepts them, and compares the exact expected 784-pixel dump:

- header
- `threshold=100`
- `roi=448`
- `block=16`
- `addr,value`
- addresses `0..783`
- exact `0xXX` values from known RAM data
- footer

It also checks that `pending_data` does not change while waiting for UART acceptance.

Result:

`TB PASS: capture_dump_controller emitted exact 784-pixel UART dump`

Other regression tests:

- `tb_streaming_mnist_preload_pack.v`: PASS
- `tb_streaming_mnist_capture_equivalence.v`: PASS

## P&R Result

Bitstream generated:

`impl/pnr/full_system_GOWIN_camera_live_800x600_40.fs`

| Metric | Before UART handshake fix | After UART handshake fix | Delta |
|---|---:|---:|---:|
| Logic | 3192 / 4608 | 3224 / 4608 | +32 |
| LUT | 2830 | 2862 | +32 |
| ALU | 362 | 362 | 0 |
| Reg | 1869 / 3612 | 1868 / 3612 | -1 |
| CLS | 1924 / 2304 | 1941 / 2304 | +17 |
| BSRAM | 7 / 10 | 7 / 10 | 0 |
| DSP | 0 / 8 | 0 / 8 | 0 |
| pix required/Fmax | 40.000 / 65.428 MHz | 40.000 / 68.581 MHz | +3.153 MHz |
| HyperRAM required/Fmax | 79.500 / 79.741 MHz | 79.500 / 79.732 MHz | -0.009 MHz |
| setup slack | -6.770 ns | -6.279 ns | +0.491 ns |
| hold slack | +0.570 ns | -0.970 ns | -1.540 ns |

Top setup remains in the VFB/HyperRAM boundary:

`I_clk_ibuf -> u_camera_video/g_hw.u_hyperram/u_hpram_top/u_hpram_sync/cs_memsync[4] -> u_camera_video/g_hw.u_hyperram/u_hpram_top/u_dqce_clk_x2p`

Top hold is again the known HyperRAM vendor calibration path:

`u_hpram_init/read_calibration[0].calib[0] -> u_hpram_wd/data_lane_gen[0].u_hpram_lane/iserdes_gen[7].u_ides4`

## Decision

The UART dump logic is fixed and verified. The bitstream is suitable for a UART-debug board test, but the timing report is not clean because the unrelated HyperRAM vendor hold path moved negative again.

If board live HDMI remains stable, test UART first with `UART_TEST_MODE=1`, then return to `UART_TEST_MODE=0` and capture a full 784-pixel dump.
