#!/usr/bin/env python3
"""Bit-exact integer reference for the LWDD CNN RTL.

The exported LWDD file contains int16/int32 parameters but no activation
quantization table. This script defines the hardware contract used by the RTL:

* input pixels are the lower 8 bits from image_processing, interpreted as
  unsigned Q0.8-ish activation values in the integer range 0..255;
* every conv uses signed int64 accumulation;
* conv outputs apply ReLU, an explicit right shift, then unsigned saturation to
  signed int16 range 0..32767;
* maxpool/global maxpool are exact integer maxima;
* dense uses int64 accumulation with classifier bias arithmetically shifted to
  the same integer domain as the activation*weight products;
* argmax picks the first maximum class.

The generated Verilog include and golden vector files are consumed by the RTL
testbenches, so the tests compare against this contract rather than a guessed
float replay.
"""

from __future__ import annotations

import argparse
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
SRC_CNN_DIR = ROOT / "src" / "cnn"


@dataclass(frozen=True)
class TensorSpec:
    name: str
    offset: int
    byte_count: int
    dtype: str
    shape: Tuple[int, ...]
    word_offset: int
    len_words: int


TENSORS: Tuple[TensorSpec, ...] = (
    TensorSpec("conv1.filters", 0, 72, "int16", (3, 3, 1, 4), 0, 18),
    TensorSpec("conv2.filters", 72, 288, "int16", (3, 3, 4, 4), 18, 72),
    TensorSpec("conv3.filters", 360, 576, "int16", (3, 3, 4, 8), 90, 144),
    TensorSpec("conv4.filters", 936, 1152, "int16", (3, 3, 8, 8), 234, 288),
    TensorSpec("conv5.filters", 2088, 2304, "int16", (3, 3, 8, 16), 522, 576),
    TensorSpec("conv6.filters", 4392, 4608, "int16", (3, 3, 16, 16), 1098, 1152),
    TensorSpec("classifier.weights", 9000, 320, "int16", (16, 10), 2250, 80),
    TensorSpec("classifier.bias", 9320, 40, "int32", (10,), 2330, 10),
)

TOTAL_BYTES = 9360
TOTAL_WORDS = 2340

# Explicit hardware quantization. The conv shifts are the nearest power-of-two
# approximation of the corresponding int16 weight scale from the export text.
CONV_SHIFTS = {
    "conv1.filters": 15,
    "conv2.filters": 16,
    "conv3.filters": 16,
    "conv4.filters": 16,
    "conv5.filters": 16,
    "conv6.filters": 16,
}
INPUT_FRAC_BITS = 8
DENSE_BIAS_SHIFT = 11


def parse_scales(txt_path: Path) -> Dict[str, float]:
    scales: Dict[str, float] = {}
    header_re = re.compile(r"^#\s+(\S+)\s+.*\bscale=([0-9.eE+-]+)")
    for line in txt_path.read_text(encoding="utf-8").splitlines():
        match = header_re.match(line.strip())
        if match:
            scales[match.group(1)] = float(match.group(2))
    return scales


def load_params(bin_path: Path) -> Dict[str, np.ndarray]:
    blob = bin_path.read_bytes()
    if len(blob) != TOTAL_BYTES:
        raise ValueError(f"{bin_path} has {len(blob)} bytes, expected {TOTAL_BYTES}")

    params: Dict[str, np.ndarray] = {}
    for spec in TENSORS:
        raw = blob[spec.offset : spec.offset + spec.byte_count]
        dtype = "<i2" if spec.dtype == "int16" else "<i4"
        arr = np.frombuffer(raw, dtype=np.dtype(dtype)).reshape(spec.shape)
        params[spec.name] = arr.astype(np.int64)
    return params


def verify_layout(bin_path: Path, txt_path: Path) -> List[str]:
    params = load_params(bin_path)
    scales = parse_scales(txt_path)
    lines: List[str] = []
    lines.append(f"binary_size_bytes={bin_path.stat().st_size}")
    lines.append(f"total_words={TOTAL_WORDS}")
    for spec in TENSORS:
        arr = params[spec.name]
        expected_count = int(np.prod(spec.shape))
        if arr.size != expected_count:
            raise ValueError(f"{spec.name}: size {arr.size}, expected {expected_count}")
        if spec.byte_count != expected_count * (2 if spec.dtype == "int16" else 4):
            raise ValueError(f"{spec.name}: byte count mismatch")
        scale = scales.get(spec.name, float("nan"))
        nearest_shift = int(round(-math.log2(scale))) if scale > 0 else -1
        lines.append(
            f"{spec.name}: offset={spec.offset} bytes={spec.byte_count} "
            f"word_offset={spec.word_offset} len_words={spec.len_words} "
            f"shape={list(spec.shape)} dtype={spec.dtype} scale={scale:.17g} "
            f"nearest_pow2_shift={nearest_shift}"
        )
    return lines


def conv3_same(x: np.ndarray, w: np.ndarray, shift: int) -> np.ndarray:
    height, width, channels = x.shape
    _, _, cin, cout = w.shape
    if cin != channels:
        raise ValueError(f"conv channel mismatch: x has {channels}, weights expect {cin}")

    out = np.zeros((height, width, cout), dtype=np.int64)
    for y in range(height):
        for xx in range(width):
            for co in range(cout):
                acc = 0
                for ky in range(3):
                    iy = y + ky - 1
                    if iy < 0 or iy >= height:
                        continue
                    for kx in range(3):
                        ix = xx + kx - 1
                        if ix < 0 or ix >= width:
                            continue
                        for ci in range(channels):
                            acc += int(x[iy, ix, ci]) * int(w[ky, kx, ci, co])
                if acc < 0:
                    acc = 0
                acc >>= shift
                if acc > 32767:
                    acc = 32767
                out[y, xx, co] = acc
    return out


def maxpool2(x: np.ndarray) -> np.ndarray:
    height, width, channels = x.shape
    if (height & 1) or (width & 1):
        raise ValueError("maxpool2 expects even spatial dimensions")
    out = np.zeros((height // 2, width // 2, channels), dtype=np.int64)
    for y in range(height // 2):
        for xx in range(width // 2):
            patch = x[(2 * y) : (2 * y + 2), (2 * xx) : (2 * xx + 2), :]
            out[y, xx, :] = patch.max(axis=(0, 1))
    return out


def run_reference(params: Dict[str, np.ndarray], image_u8: np.ndarray) -> Tuple[np.ndarray, int, Dict[str, np.ndarray]]:
    image = np.asarray(image_u8, dtype=np.int64).reshape(28, 28, 1)
    image = np.clip(image, 0, 255)
    trace: Dict[str, np.ndarray] = {"input": image.copy()}

    x = conv3_same(image, params["conv1.filters"], CONV_SHIFTS["conv1.filters"])
    trace["conv1"] = x.copy()
    x = conv3_same(x, params["conv2.filters"], CONV_SHIFTS["conv2.filters"])
    trace["conv2"] = x.copy()
    x = maxpool2(x)
    trace["pool1"] = x.copy()

    x = conv3_same(x, params["conv3.filters"], CONV_SHIFTS["conv3.filters"])
    trace["conv3"] = x.copy()
    x = conv3_same(x, params["conv4.filters"], CONV_SHIFTS["conv4.filters"])
    trace["conv4"] = x.copy()
    x = maxpool2(x)
    trace["pool2"] = x.copy()

    x = conv3_same(x, params["conv5.filters"], CONV_SHIFTS["conv5.filters"])
    trace["conv5"] = x.copy()
    x = conv3_same(x, params["conv6.filters"], CONV_SHIFTS["conv6.filters"])
    trace["conv6"] = x.copy()

    gpool = x.max(axis=(0, 1)).astype(np.int64)
    trace["global_max"] = gpool.copy()

    weights = params["classifier.weights"]
    bias = params["classifier.bias"]
    logits = np.zeros(10, dtype=np.int64)
    for out_idx in range(10):
        acc = int(bias[out_idx]) >> DENSE_BIAS_SHIFT
        for in_idx in range(16):
            acc += int(gpool[in_idx]) * int(weights[in_idx, out_idx])
        logits[out_idx] = acc

    cls = int(np.argmax(logits))
    return logits, cls, trace


def read_u8_image_tokens(path: Path, max_images: int) -> List[np.ndarray]:
    if not path.exists():
        return []
    tokens = [int(tok) for tok in re.findall(r"-?\d+", path.read_text(encoding="utf-8", errors="ignore"))]
    images: List[np.ndarray] = []
    for idx in range(min(max_images, len(tokens) // 784)):
        arr = np.asarray(tokens[idx * 784 : (idx + 1) * 784], dtype=np.int64)
        images.append(np.clip(arr, 0, 255).astype(np.uint8))
    return images


def default_images(max_images: int) -> List[np.ndarray]:
    images: List[np.ndarray] = []
    candidates = [
        ROOT.parent / "final" / "data" / "expected" / "mnist10_images_i16.txt",
        ROOT.parent / "output_final" / "data" / "out" / "mnist10_images_i16.txt",
    ]
    for path in candidates:
        images.extend(read_u8_image_tokens(path, max_images=max_images - len(images)))
        if len(images) >= max_images:
            return images[:max_images]

    dump = ROOT.parent / "mnist_dump_mode2_vstroke.txt"
    images.extend(read_u8_image_tokens(dump, max_images=max_images - len(images)))
    if len(images) >= max_images:
        return images[:max_images]

    zero = np.zeros(784, dtype=np.uint8)
    diagonal = np.zeros((28, 28), dtype=np.uint8)
    np.fill_diagonal(diagonal, 255)
    full = np.full(784, 255, dtype=np.uint8)
    images.extend([zero, diagonal.reshape(-1), full])
    return images[:max_images]


def pack_image_words(image: np.ndarray) -> List[int]:
    vals = np.asarray(image, dtype=np.uint8).reshape(784)
    words: List[int] = []
    for idx in range(0, 784, 2):
        lo = int(vals[idx]) & 0xFF
        hi = int(vals[idx + 1]) & 0xFF
        words.append((hi << 16) | lo)
    return words


def params_to_words(blob: bytes) -> List[int]:
    words: List[int] = []
    for idx in range(0, len(blob), 4):
        b0, b1, b2, b3 = blob[idx : idx + 4]
        words.append(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24))
    return words


def write_hex_lines(path: Path, values: Iterable[int], width_bits: int) -> None:
    mask = (1 << width_bits) - 1
    hex_digits = (width_bits + 3) // 4
    with path.open("w", encoding="ascii", newline="\n") as f:
        for value in values:
            f.write(f"{int(value) & mask:0{hex_digits}X}\n")


def emit_verilog_include(path: Path, scales: Dict[str, float]) -> None:
    lines = [
        "`ifndef CNN_QUANT_PARAMS_VH",
        "`define CNN_QUANT_PARAMS_VH",
        "",
        "// Generated by scripts/cnn_lwdd_bitexact.py.",
        "// Input pixels are lower 8 bits, stored as unsigned int16 0..255.",
        f"`define CNN_INPUT_FRAC_BITS {INPUT_FRAC_BITS}",
        f"`define CNN_DENSE_BIAS_SHIFT {DENSE_BIAS_SHIFT}",
    ]
    for idx, name in enumerate(
        [
            "conv1.filters",
            "conv2.filters",
            "conv3.filters",
            "conv4.filters",
            "conv5.filters",
            "conv6.filters",
        ],
        start=1,
    ):
        scale = scales.get(name, 0.0)
        nearest_shift = int(round(-math.log2(scale))) if scale > 0 else CONV_SHIFTS[name]
        lines.append(
            f"`define CNN_CONV{idx}_SHIFT {CONV_SHIFTS[name]} "
            f"// scale={scale:.17g}, nearest_pow2_shift={nearest_shift}"
        )
    lines.extend(["", "`endif", ""])
    path.write_text("\n".join(lines), encoding="ascii")


def emit_outputs(bin_path: Path, txt_path: Path, max_images: int) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    SRC_CNN_DIR.mkdir(parents=True, exist_ok=True)

    params = load_params(bin_path)
    scales = parse_scales(txt_path)
    blob = bin_path.read_bytes()
    param_words = params_to_words(blob)
    if len(param_words) != TOTAL_WORDS:
        raise ValueError(f"expected {TOTAL_WORDS} parameter words, got {len(param_words)}")

    images = default_images(max_images=max_images)
    if not images:
        raise RuntimeError("no input images available")

    image_words: List[int] = []
    logits_flat: List[int] = []
    classes: List[int] = []
    summary: List[str] = []
    summary.extend(verify_layout(bin_path, txt_path))
    summary.append("")
    summary.append(
        "fixed_point=input_u8_as_int16 conv_acc=int64 relu shift saturate_u15 "
        f"conv_shifts={CONV_SHIFTS} dense_bias_shift={DENSE_BIAS_SHIFT}"
    )
    summary.append("")

    for sample_idx, image in enumerate(images):
        logits, cls, trace = run_reference(params, image)
        image_words.extend(pack_image_words(image))
        logits_flat.extend(int(v) for v in logits)
        classes.append(cls)
        maxima = " ".join(f"{k}_max={int(v.max())}" for k, v in trace.items() if k != "input")
        summary.append(
            f"sample={sample_idx} class={cls} logits="
            + " ".join(str(int(v)) for v in logits)
        )
        summary.append(f"sample={sample_idx} {maxima}")

    write_hex_lines(DATA_DIR / "lwdd_params_words.mem", param_words, 32)
    write_hex_lines(DATA_DIR / "cnn_tb_image_words.mem", image_words, 32)
    write_hex_lines(DATA_DIR / "cnn_tb_logits.mem", logits_flat, 64)
    write_hex_lines(DATA_DIR / "cnn_tb_classes.mem", classes, 4)
    (DATA_DIR / "cnn_tb_count.txt").write_text(f"{len(images)}\n", encoding="ascii")
    (DATA_DIR / "cnn_golden_summary.txt").write_text("\n".join(summary) + "\n", encoding="ascii")
    emit_verilog_include(SRC_CNN_DIR / "cnn_quant_params.vh", scales)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin", type=Path, default=DATA_DIR / "lwdd_params_int16_int32.bin")
    parser.add_argument("--txt", type=Path, default=DATA_DIR / "lwdd_params_int16_int32.txt")
    parser.add_argument("--max-images", type=int, default=2)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()

    if args.verify_only:
        for line in verify_layout(args.bin, args.txt):
            print(line)
        return

    emit_outputs(args.bin, args.txt, max_images=args.max_images)
    print(f"Generated CNN quant include and golden vectors in {ROOT}")


if __name__ == "__main__":
    main()
