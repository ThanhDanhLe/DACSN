# NN Integrated A/B Matrix

Date: 2026-05-24

| Step | Files changed | NN included | UART/debug included | Logic | LUT | ALU | Reg | CLS | BSRAM | DSP | pix req/Fmax | HyperRAM req/Fmax | Setup | Hold | Tests | Bitstream | Decision |
|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| 800x600@40 base | none in this branch | no | optional dump | 2908 | 2546 | 362 | 1798 | 1840 | 7 | 0 | 40.000 / 61.161 | 79.500 / 83.557 | -7.100 | -0.035 | equivalence PASS, preload PASS | generated | reference base |
| NN integrated, pre-display-CDC SDC | `camera_live_top.v`, `camera_video.v`, project, NN imports | yes | disabled by default | 4397 | 3706 | 691 | 2666 | 2281 | 10 | 2 | 40.000 / 61.872 | 79.500 / 71.488 | display CDC dominated | display/vendor dominated | preload PASS, RAM preload PASS, equivalence PASS | generated | diagnostic |
| NN integrated, targeted display CDC SDC | `src/full_system_top.sdc` | yes | disabled by default | 4397 | 3706 | 691 | 2666 | 2281 | 10 | 2 | 40.000 / 55.784 | 79.500 / 69.765 | -8.070 | -0.916 | preload PASS, RAM preload PASS, equivalence PASS | generated | board-test candidate |

## Decision

Keep the targeted-display-CDC SDC build as the branch head because it removes report noise from display-only first-stage synchronizer crossings without applying broad clock-domain false paths.

The branch remains extremely resource-tight and not timing-clean. The remaining failures are VFB/HyperRAM boundary and vendor-calibration paths.

