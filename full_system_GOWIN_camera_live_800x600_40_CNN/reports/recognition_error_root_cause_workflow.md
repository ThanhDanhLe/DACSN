# Recognition Error Root-Cause Workflow

Date: 2026-05-24

## Step 1: Capture

Place a known digit in the ROI and trigger capture. Save the 784-pixel UART dump.

## Step 2: Python Inference

```powershell
python full_system_GOWIN_camera_live_800x600_40/final/verify/predict_fpga_capture_dump.py `
  --dump captured.csv `
  --params final/out/direct_stream_params.bin `
  --label X
```

## Step 3: Compare Results

Record:

- expected label,
- Python predicted class,
- future FPGA predicted class,
- pixel sum,
- nonzero count,
- bbox,
- min/max pixel,
- dump checksum or saved file hash.

## Interpretation

Case 1: Python wrong, FPGA same wrong.

Result: model/preprocessing/input distribution issue.

Next action: lighting, ROI positioning, threshold sweep offline, camera-like data augmentation, or retraining.

Case 2: Python correct, FPGA wrong.

Result: hardware NN, preload packing, SPI parameter read, flash offset, or timing issue.

Next action: verify preload words, SPI offset `0x200000`, direct-stream NN TB, and parameter readback.

Case 3: repeated dumps of the same fixed digit differ.

Result: capture, lighting, trigger, VSYNC, or camera stability issue.

Next action: improve capture trigger, paper/camera fixture, exposure/lighting, and CRC repeatability.

Case 4: dump stable, Python correct, fixed-vector FPGA correct, live wrong.

Result: live capture/user input/threshold condition is likely.

Next action: collect more board dumps and classify failure variants.
