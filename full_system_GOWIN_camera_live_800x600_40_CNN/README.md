# Camera Live 800x600@40 NN Integrated Branch

This is an independent integration branch based on the board-stable
800x600@40 camera-live branch. It adds the verified NN/SPI/preload path from
`full_system_GOWIN_nn_uart_standalone`.

It is not merged into `full_system_GOWIN`.

## Function

- OV2640 RGB565 camera live path through Gowin VFB/HyperRAM/HDMI.
- Streaming MNIST capture remains integrated.
- Dual-clock MNIST RAM remains integrated.
- Preload packer reads 784 MNIST bytes and emits 392 packed preload words.
- `nn_system`, `nn_spi_param_streamer`, and `nn_compute_mlp16_pocket` are wired.
- Lightweight HDMI seven-seg result overlay is active.
- Optional UART dump/debug logic remains in source but is disabled by default.
- SPI flash pins are used by `nn_system`; do not use the old UART-on-flash-pin
  debug build at the same time as NN integration.

## Video Mode

- Active: `800x600`
- Total: `1056x628`
- Pixel clock target: `40 MHz`
- ROI: `448x448` at `X=176`, `Y=76`
- Threshold/polarity/row-major MNIST format unchanged.
- `FLASH_PARAM_BASE = 24'h200000`
- SPI flash parameter offset: `0x200000`

## Board Test Notes

This is the NN-integrated VFB-based development candidate. Check:

- whether the monitor accepts true 800x600@60-style timing,
- whether live HDMI is stable,
- whether pressing the capture key runs NN inference,
- whether the HDMI seven-seg result updates,
- whether any artifact looks like VFB/display instability rather than camera input corruption.

The build still reports a VFB/HyperRAM cross-clock setup violation. Do not treat
this as timing-closed. Board behavior is currently better evidence for the live
display path than the remaining generated-clock report warning.

## Capture Dump Workflow

The old capture dump logic is still useful for diagnostic builds, but the
integrated default build keeps it disabled so SPI flash pins remain dedicated to
`nn_system`. For a debug-only variant, the capture output format is:

```text
BEGIN_CAPTURE
threshold=100
roi=448
block=16
addr,value
0,0x00
...
783,0x00
END_CAPTURE
```

Run Python inference on a captured dump from the repository root:

```powershell
python full_system_GOWIN_camera_live_800x600_40_nn_integrated/final/verify/predict_fpga_capture_dump.py `
  --dump path\to\capture.csv `
  --params final/out/direct_stream_params.bin `
  --label 5
```

The script writes a rendered 28x28 PNG, matrix CSV, pixel statistics, logits,
and predicted class.

## Build

```powershell
cd full_system_GOWIN_camera_live_800x600_40_nn_integrated
& 'C:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe' run_final_build.tcl
```

Bitstream:

`impl/pnr/full_system_GOWIN_camera_live_800x600_40_nn_integrated.fs`

## Programming

Program parameters to SPI flash:

```text
final/out/direct_stream_params.bin at offset 0x200000
```

Program FPGA SRAM/JTAG:

```text
impl/pnr/full_system_GOWIN_camera_live_800x600_40_nn_integrated.fs
```
