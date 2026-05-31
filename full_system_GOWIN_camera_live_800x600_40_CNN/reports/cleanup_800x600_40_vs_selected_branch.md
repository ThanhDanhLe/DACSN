# 800x600@40 vs Selected Camera-Live Branch

Date: 2026-05-24

| Metric | Selected streaming baseline | Standalone 800x600@40 |
|---|---:|---:|
| Live HDMI | yes | yes |
| Streaming capture | yes | yes |
| NN | no | no |
| Video active | 800x600 | 800x600 |
| Video total | 1650x750 | 1056x628 |
| Required pix_clk | 74.250 MHz | 40.000 MHz |
| pix Fmax | 71.829 MHz | 61.161 MHz |
| Required HyperRAM | 79.500 MHz | 79.500 MHz |
| HyperRAM Fmax | 76.763 MHz | 83.557 MHz |
| Setup slack | -6.406 ns | -7.100 ns |
| Hold slack | -0.344 ns | -0.035 ns |
| Logic | 2917 | 2908 |
| LUT | 2555 | 2546 |
| Reg | 1798 | 1798 |
| CLS | 1865 | 1840 |
| BSRAM | 7 | 7 |

## Interpretation

The 800x600@40 branch makes the per-clock requirements realistic:

- `pix_clk` Fmax exceeds the 40 MHz requirement.
- HyperRAM Fmax exceeds the 79.5 MHz requirement.
- Hold is much closer to clean.

The remaining setup failure is still the VFB/HyperRAM cross-clock boundary, so
this branch should be board-tested but not merged as a timing-closed solution.
