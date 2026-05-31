# Board Repeatability Test Checklist

Date: 2026-05-24

## Setup

1. Fix the camera position.
2. Fix the paper/digit position.
3. Keep lighting constant.
4. Use the 800x600@40 debug bitstream.
5. Capture UART dumps from `FLASH_MOSI` or remap UART TX to a convenient header in a later board-debug build.

## Per Digit

For each digit `0..9`:

1. Capture 10 times.
2. Save each dump file.
3. Run `predict_fpga_capture_dump.py`.
4. Record:
   - file name,
   - pixel sum,
   - nonzero count,
   - bbox,
   - predicted class,
   - checksum/file hash,
   - notes about lighting or position.

## Decision

- Stable dumps, wrong Python prediction: input/model/domain problem.
- Unstable dumps: capture/lighting/timing problem.
- Stable dumps, Python correct: safe to attempt minimal NN integration next.
