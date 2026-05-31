#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

import numpy as np
from PIL import Image


BRANCH_DIR = Path(__file__).resolve().parents[2]
ROOT_DIR = BRANCH_DIR.parent
ROOT_VERIFY = ROOT_DIR / "final" / "verify"
if str(ROOT_VERIFY) not in sys.path:
    sys.path.insert(0, str(ROOT_VERIFY))

import decode_direct_stream_params as dsp  # noqa: E402


DEFAULT_PARAMS = ROOT_DIR / "final" / "out" / "direct_stream_params.bin"
DEFAULT_MAP = ROOT_DIR / "final" / "out" / "direct_stream_memory_map.json"
DEFAULT_OUTDIR = BRANCH_DIR / "final" / "out" / "fpga_capture_dump"


def parse_value(text: str) -> int:
    text = text.strip()
    if not text:
        raise ValueError("empty value")
    return int(text, 0)


def parse_dump(path: Path) -> List[int]:
    values: List[Optional[int]] = [None] * 784
    sequential: List[int] = []
    in_capture = False
    saw_markers = False

    for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if not line:
            continue
        if line == "BEGIN_CAPTURE":
            in_capture = True
            saw_markers = True
            continue
        if line == "END_CAPTURE":
            in_capture = False
            continue
        if saw_markers and not in_capture:
            continue
        if line.lower() == "addr,value":
            continue
        if line.startswith("threshold=") or line.startswith("roi=") or line.startswith("block="):
            continue

        if "," in line:
            left, right = line.split(",", 1)
            if not re.match(r"^\s*(0x[0-9a-fA-F]+|\d+)\s*$", left):
                continue
            addr = parse_value(left)
            value = parse_value(right)
            if 0 <= addr < 784:
                values[addr] = value & 0xFF
        else:
            tokens = re.split(r"[\s,]+", line)
            for token in tokens:
                if token:
                    sequential.append(parse_value(token) & 0xFF)

    if any(value is not None for value in values):
        missing = [idx for idx, value in enumerate(values) if value is None]
        if missing:
            raise ValueError(f"{path}: missing {len(missing)} addresses, first={missing[:8]}")
        return [int(value) for value in values if value is not None]

    if len(sequential) != 784:
        raise ValueError(f"{path}: expected 784 sequential values, got {len(sequential)}")
    return sequential


def bbox(values: Sequence[int]) -> Tuple[int, int, int, int]:
    arr = np.asarray(values, dtype=np.uint8).reshape(28, 28)
    ys, xs = np.nonzero(arr)
    if len(xs) == 0:
        return 0, 0, 0, 0
    return int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())


def save_png(path: Path, values: Sequence[int]) -> None:
    arr = np.asarray(values, dtype=np.uint8).reshape(28, 28)
    image = Image.fromarray(arr, mode="L").resize((280, 280), Image.Resampling.NEAREST)
    image.save(path)


def decode_model(params: Path, mem_map: Path):
    data = params.read_bytes()
    import json

    model_map = json.loads(mem_map.read_text(encoding="utf-8"))
    dims = model_map["model"]
    regions_raw = model_map["regions"]
    if isinstance(regions_raw, dict):
        regions = {name.lower(): region for name, region in regions_raw.items()}
    else:
        regions = {region["name"].lower(): region for region in regions_raw}
    decoded = {}
    for key, w_key, b_key in [
        ("fc1", "w1", "b1"),
        ("fc2", "w2", "b2"),
        ("fc3", "w3", "b3"),
    ]:
        weights, biases, _ = dsp.decode_layer(data, regions[key])
        decoded[w_key] = weights
        decoded[b_key] = biases
    return decoded, dims


def write_matrix_csv(path: Path, values: Sequence[int]) -> None:
    arr = np.asarray(values, dtype=np.uint8).reshape(28, 28)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerows(arr.tolist())


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Python NN inference on an FPGA 784-pixel capture dump.")
    parser.add_argument("--dump", type=Path, required=True)
    parser.add_argument("--params", type=Path, default=DEFAULT_PARAMS)
    parser.add_argument("--map", type=Path, default=DEFAULT_MAP)
    parser.add_argument("--label", type=int, default=None)
    parser.add_argument("--outdir", type=Path, default=DEFAULT_OUTDIR)
    args = parser.parse_args()

    values = parse_dump(args.dump.resolve())
    decoded, dims = decode_model(args.params.resolve(), args.map.resolve())
    z1, a1, z2, a2, z3, final, pred = dsp.forward(values, decoded, dims)

    args.outdir.mkdir(parents=True, exist_ok=True)
    stem = args.dump.stem
    png_path = args.outdir / f"{stem}_28x28.png"
    csv_path = args.outdir / f"{stem}_matrix.csv"
    report_path = args.outdir / f"{stem}_report.txt"
    save_png(png_path, values)
    write_matrix_csv(csv_path, values)

    pixel_sum = int(sum(values))
    nonzero_count = int(sum(1 for value in values if value != 0))
    min_value = int(min(values))
    max_value = int(max(values))
    box = bbox(values)

    lines = [
        f"dump={args.dump.resolve()}",
        f"params={args.params.resolve()}",
        f"pixel_sum={pixel_sum}",
        f"nonzero_count={nonzero_count}",
        f"bbox_min_x={box[0]}",
        f"bbox_max_x={box[1]}",
        f"bbox_min_y={box[2]}",
        f"bbox_max_y={box[3]}",
        f"min_pixel={min_value}",
        f"max_pixel={max_value}",
        "logits=" + ",".join(str(int(v)) for v in final),
        f"predicted_class={pred}",
    ]
    if args.label is not None:
        lines.append(f"expected_label={args.label}")
        lines.append(f"match={int(pred) == int(args.label)}")
    lines.extend([
        f"png={png_path}",
        f"matrix_csv={csv_path}",
    ])
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    print(f"report={report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
