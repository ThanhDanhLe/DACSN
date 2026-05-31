#!/usr/bin/env python3
from __future__ import annotations

import argparse
import queue
import re
import threading
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

import numpy as np
import serial
import tkinter as tk
from PIL import Image, ImageDraw, ImageTk

# Put this file in the same folder as predict_fpga_capture_dump.py
# This reuses DEFAULT_PARAMS, DEFAULT_MAP, decode_model(), and dsp.forward().
import predict_fpga_capture_dump as base


# ============================================================
# UART dump parser
# ============================================================

def parse_value(text: str) -> int:
    return int(text.strip(), 0)


def parse_capture_lines(lines: Sequence[str]) -> List[int]:
    """
    Expected UART frame:

    BEGIN_CAPTURE
    threshold=100
    roi=448
    block=16
    addr,value
    0,0x00
    ...
    783,0x00
    END_CAPTURE
    """
    values: List[Optional[int]] = [None] * 784

    pixel_re = re.compile(
        r"^\s*(\d+|0x[0-9a-fA-F]+)\s*,\s*(0x[0-9a-fA-F]+|\d+)\s*$"
    )

    in_capture = False
    saw_begin = False
    saw_end = False

    for raw in lines:
        line = raw.strip()
        if not line:
            continue

        if line == "BEGIN_CAPTURE":
            in_capture = True
            saw_begin = True
            continue

        if line == "END_CAPTURE":
            in_capture = False
            saw_end = True
            continue

        if not in_capture:
            continue

        if line.lower() == "addr,value":
            continue

        if (
            line.startswith("threshold=")
            or line.startswith("roi=")
            or line.startswith("block=")
        ):
            continue

        match = pixel_re.match(line)
        if not match:
            continue

        addr = parse_value(match.group(1))
        value = parse_value(match.group(2))

        if 0 <= addr < 784:
            values[addr] = value & 0xFF

    if not saw_begin:
        raise ValueError("missing BEGIN_CAPTURE")

    if not saw_end:
        raise ValueError("missing END_CAPTURE")

    missing = [idx for idx, value in enumerate(values) if value is None]
    if missing:
        raise ValueError(
            f"missing {len(missing)} pixel addresses, first missing={missing[:10]}"
        )

    return [int(v) for v in values if v is not None]


# ============================================================
# Image/stat helpers
# ============================================================

def bbox(values: Sequence[int]) -> Tuple[int, int, int, int]:
    arr = np.asarray(values, dtype=np.uint8).reshape(28, 28)
    ys, xs = np.nonzero(arr)

    if len(xs) == 0:
        return 0, 0, 0, 0

    return int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())


def render_mnist(
    values: Sequence[int],
    scale: int = 12,
    black_on_white: bool = True,
) -> Image.Image:
    arr = np.asarray(values, dtype=np.uint8).reshape(28, 28)

    # Model input is normally bright stroke on black background.
    # For human viewing, default display is black digit on white background.
    if black_on_white:
        arr = 255 - arr

    img = Image.fromarray(arr, mode="L")
    img = img.resize((28 * scale, 28 * scale), Image.Resampling.NEAREST)
    return img.convert("RGB")


# ============================================================
# Seven-segment renderer
# ============================================================

SEGMENTS = {
    0: "abcdef",
    1: "bc",
    2: "abdeg",
    3: "abcdg",
    4: "bcfg",
    5: "acdfg",
    6: "acdefg",
    7: "abc",
    8: "abcdefg",
    9: "abcdfg",
}


def render_seven_segment_digit(
    digit: int,
    width: int = 260,
    height: int = 360,
) -> Image.Image:
    bg = (10, 10, 10)
    off = (40, 40, 40)
    on = (255, 224, 0)
    white = (235, 235, 235)

    img = Image.new("RGB", (width, height), bg)
    draw = ImageDraw.Draw(img)

    t = 32
    x0 = 45
    x1 = width - 45
    y0 = 60
    ym = 175
    y1 = 302

    rects = {
        "a": (x0 + t // 2, y0, x1 - t // 2, y0 + t),
        "g": (x0 + t // 2, ym - t // 2, x1 - t // 2, ym + t // 2),
        "d": (x0 + t // 2, y1 - t, x1 - t // 2, y1),
        "f": (x0, y0 + t // 2, x0 + t, ym - t // 2),
        "b": (x1 - t, y0 + t // 2, x1, ym - t // 2),
        "e": (x0, ym + t // 2, x0 + t, y1 - t // 2),
        "c": (x1 - t, ym + t // 2, x1, y1 - t // 2),
    }

    active = SEGMENTS.get(int(digit), "g")

    for name, xy in rects.items():
        draw.rounded_rectangle(
            xy,
            radius=8,
            fill=(on if name in active else off),
        )

    draw.text((18, 16), "PREDICTED", fill=white)
    draw.text((18, height - 36), f"class = {digit}", fill=white)

    return img


# ============================================================
# Dashboard renderer
# ============================================================

def make_dashboard(
    values: Sequence[int],
    logits: Sequence[int],
    pred: int,
    black_on_white: bool,
    capture_index: int,
) -> Image.Image:
    W, H = 920, 500
    bg = (22, 22, 22)
    fg = (235, 235, 235)
    dim = (180, 180, 180)

    canvas = Image.new("RGB", (W, H), bg)
    draw = ImageDraw.Draw(canvas)

    mnist_img = render_mnist(values, scale=12, black_on_white=black_on_white)
    seg_img = render_seven_segment_digit(pred)

    x_mnist, y_mnist = 34, 72
    x_seg, y_seg = 585, 50

    draw.text(
        (34, 22),
        f"Capture #{capture_index} - Reconstructed 28x28 MNIST input",
        fill=fg,
    )

    draw.rectangle(
        (
            x_mnist - 3,
            y_mnist - 3,
            x_mnist + mnist_img.width + 2,
            y_mnist + mnist_img.height + 2,
        ),
        outline=(190, 190, 190),
        width=2,
    )

    canvas.paste(mnist_img, (x_mnist, y_mnist))
    canvas.paste(seg_img, (x_seg, y_seg))

    pixel_sum = int(sum(values))
    nonzero_count = int(sum(1 for value in values if value != 0))
    min_pixel = int(min(values))
    max_pixel = int(max(values))
    bx = bbox(values)

    info_lines = [
        f"predicted_class = {pred}",
        f"pixel_sum       = {pixel_sum}",
        f"nonzero_count   = {nonzero_count}",
        f"bbox            = x[{bx[0]}..{bx[1]}], y[{bx[2]}..{bx[3]}]",
        f"min/max pixel   = {min_pixel}/{max_pixel}",
    ]

    info_x, info_y = 34, 425
    for i, line in enumerate(info_lines):
        draw.text((info_x, info_y + i * 16), line, fill=fg)

    logits_text = "logits = " + ",".join(str(int(v)) for v in logits)
    draw.text((360, 425), logits_text[:82], fill=dim)

    return canvas


# ============================================================
# Live GUI app
# ============================================================

class LiveUARTPredictApp:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.events: queue.Queue = queue.Queue()
        self.stop_event = threading.Event()
        self.photo = None
        self.capture_count = 0

        print("[INFO] Loading NN params...")
        self.decoded, self.dims = base.decode_model(
            args.params.resolve(),
            args.map.resolve(),
        )
        print("[INFO] Model loaded.")
        print(f"[INFO] Opening UART {args.port} @ {args.baud} 8N1")
        print("[INFO] Waiting for BEGIN_CAPTURE ...")

        self.root = tk.Tk()
        self.root.title("Tang Nano 4K - Live 28x28 Capture + Python Prediction")

        self.image_label = tk.Label(self.root)
        self.image_label.pack(padx=8, pady=8)

        self.status_var = tk.StringVar(value="Waiting for FPGA capture ...")
        self.status_label = tk.Label(
            self.root,
            textvariable=self.status_var,
            font=("Consolas", 12),
        )
        self.status_label.pack(padx=8, pady=(0, 8))

        self.thread = threading.Thread(target=self.serial_worker, daemon=True)
        self.thread.start()

        self.root.protocol("WM_DELETE_WINDOW", self.on_close)
        self.root.after(100, self.poll_events)

    def serial_worker(self) -> None:
        try:
            with serial.Serial(self.args.port, self.args.baud, timeout=1.0) as ser:
                in_capture = False
                lines: List[str] = []

                while not self.stop_event.is_set():
                    raw = ser.readline()
                    if not raw:
                        continue

                    line = raw.decode("utf-8", errors="replace").strip()

                    if self.args.echo:
                        print(line)

                    if line == "BEGIN_CAPTURE":
                        in_capture = True
                        lines = [line]
                        self.events.put(("status", "Receiving capture ..."))
                        continue

                    if in_capture:
                        lines.append(line)

                        if line == "END_CAPTURE":
                            try:
                                values = parse_capture_lines(lines)

                                _z1, _a1, _z2, _a2, _z3, final, pred = base.dsp.forward(
                                    values,
                                    self.decoded,
                                    self.dims,
                                )

                                self.capture_count += 1

                                dashboard = make_dashboard(
                                    values=values,
                                    logits=final,
                                    pred=int(pred),
                                    black_on_white=self.args.black_on_white,
                                    capture_index=self.capture_count,
                                )

                                self.events.put(
                                    ("image", dashboard, int(pred), self.capture_count)
                                )

                            except Exception as exc:
                                self.events.put(
                                    ("error", f"Capture parse/inference error: {exc}")
                                )

                            in_capture = False
                            lines = []

        except Exception as exc:
            self.events.put(("error", f"Serial error: {exc}"))

    def poll_events(self) -> None:
        try:
            while True:
                event = self.events.get_nowait()

                if event[0] == "status":
                    self.status_var.set(event[1])

                elif event[0] == "error":
                    self.status_var.set(event[1])
                    print("[ERROR]", event[1])

                elif event[0] == "image":
                    _, dashboard, pred, cap_idx = event
                    self.photo = ImageTk.PhotoImage(dashboard)
                    self.image_label.configure(image=self.photo)
                    self.status_var.set(f"Capture #{cap_idx}: predicted_class = {pred}")

        except queue.Empty:
            pass

        if not self.stop_event.is_set():
            self.root.after(100, self.poll_events)

    def on_close(self) -> None:
        self.stop_event.set()
        self.root.destroy()

    def run(self) -> None:
        self.root.mainloop()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Live UART FPGA 784-pixel capture -> 28x28 image + seven-seg prediction GUI."
    )

    parser.add_argument("--port", required=True, help="ESP32 COM port, example: COM5")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--params", type=Path, default=base.DEFAULT_PARAMS)
    parser.add_argument("--map", type=Path, default=base.DEFAULT_MAP)
    parser.add_argument("--echo", action="store_true", help="Print raw UART lines")
    parser.add_argument(
        "--raw-mnist-color",
        action="store_true",
        help="Show raw model input color: bright stroke on black background.",
    )

    args = parser.parse_args()

    # Default display: black digit on white background for human viewing.
    args.black_on_white = not args.raw_mnist_color

    app = LiveUARTPredictApp(args)
    app.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())