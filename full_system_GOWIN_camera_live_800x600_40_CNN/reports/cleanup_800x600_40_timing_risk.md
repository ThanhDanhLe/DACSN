# 800x600@40 Timing Risk

Date: 2026-05-24

## Risk

The branch is not timing-closed because setup still reports a severe
VFB/display-to-HyperRAM path.

## What Improved

- Required pixel clock dropped from 74.25 MHz to 40 MHz.
- Achieved pix Fmax is above requirement.
- Achieved HyperRAM Fmax is above requirement.
- Hold slack is close to zero at `-0.035 ns`.

## What Did Not Improve

- VFB/HyperRAM cross-clock setup remains negative.
- The issue is not in `streaming_mnist_capture`.
- The issue is not in the MNIST dual-clock RAM write path.

## Board-Test Read

If HDMI is stable on the board, the timing report likely needs vendor-boundary
constraint review. If HDMI tears, rolls, or shows unstable frame artifacts, the
VFB/HyperRAM boundary is still a practical blocker.
