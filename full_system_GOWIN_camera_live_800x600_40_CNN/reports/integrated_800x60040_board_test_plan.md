# Integrated 800x600@40 Board Test Plan

Date: 2026-05-24

## Programming

Program parameters:

```powershell
final/out/direct_stream_params.bin
```

SPI flash offset:

```text
0x200000
```

Program FPGA SRAM/JTAG bitstream:

```text
full_system_GOWIN_camera_live_800x600_40_nn_integrated/impl/pnr/full_system_GOWIN_camera_live_800x600_40_nn_integrated.fs
```

## Smoke Test

1. Confirm HDMI monitor locks to the 800x600@40 live camera output.
2. Confirm live camera image is as stable as the non-NN 800x600@40 branch.
3. Press capture key.
4. Confirm result overlay appears or updates.
5. Confirm no visible live-display regression from NN integration.

## Result Consistency Test

For each digit `0..9`:

1. Place the same paper/digit under fixed lighting.
2. Capture five times.
3. Record the HDMI result digit.
4. If debug dump is enabled for a diagnostic build, save the 784-pixel dump.
5. Run Python inference on the exact dump.
6. Compare Python class and FPGA class.

## Interpretation

| Observation | Likely Cause |
|---|---|
| Python and FPGA match, both wrong | Model/training/domain mismatch |
| Python correct, FPGA wrong | Hardware integration, preload, SPI, or NN start sequencing |
| Repeated dumps differ strongly | Capture timing, lighting, ROI, or user input instability |
| Dump stable, live preview has artifacts | VFB/display boundary issue |
| Standalone NN still works, integrated fails | Camera capture/preload integration issue |

## Notes

- This branch does not change NN weights, direct stream parameter format, SPI offset, camera RGB565 mode, ROI, block size, threshold, polarity, or row-major order.
- UART dump/debug is optional and disabled by default to keep timing and pin use lean.
- The build is not timing-clean. Board testing should focus on whether the known-good NN path still matches Python when fed the exact integrated camera capture.

