# Python Capture Dump Inference Workflow

Date: 2026-05-24

## Script

`final/verify/predict_fpga_capture_dump.py`

The script accepts the FPGA text dump, renders the 28x28 image, computes statistics, decodes `final/out/direct_stream_params.bin`, and runs the same Python direct-stream model path used for existing parameter-bin verification.

## Command

From the repository root:

```powershell
python full_system_GOWIN_camera_live_800x600_40/final/verify/predict_fpga_capture_dump.py `
  --dump path\to\capture.csv `
  --params final/out/direct_stream_params.bin `
  --label 5 `
  --outdir full_system_GOWIN_camera_live_800x600_40/final/out/fpga_capture_dump
```

## Outputs

- `<dump>_28x28.png`
- `<dump>_matrix.csv`
- `<dump>_report.txt`

The report includes:

- pixel sum
- nonzero count
- bbox min/max x/y
- min/max pixel
- logits
- predicted class
- optional expected label and match flag

## Smoke Test

The script was run on a synthetic 784-pixel dump:

- pixel sum: 7140
- nonzero count: 28
- predicted class: 4

This verifies parsing, memory-map decoding, PNG/CSV/report generation, and Python inference plumbing.

## Interpretation

- Python wrong and future FPGA same wrong: input/preprocessing/model/domain mismatch.
- Python correct and future FPGA wrong: hardware NN, preload, SPI flash, or timing issue.
- Repeated dumps differ for fixed paper/camera: capture/lighting/timing instability.
- Dumps stable but predictions wrong: threshold/domain/model problem is likely.
