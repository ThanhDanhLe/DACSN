from __future__ import annotations

from tensorflow import keras  # type: ignore
import matplotlib
matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import random as rd
import json
from pathlib import Path
from copy import deepcopy
from typing import Optional
from types import SimpleNamespace
import json
from pathlib import Path
from copy import deepcopy
from PIL import Image, ImageFilter, ImageEnhance
from PIL import Image, ImageFilter, ImageEnhance


# ============================================================
# CONFIG
# ============================================================

FAST_DEBUG = False  # True: train nhanh với subset train; test vẫn dùng tập test để render/evaluate. False: train đủ trên toàn bộ dữ liệu

OUT_DIR = Path("out_lwdd_numpy_ptq")
OUT_DIR.mkdir(parents=True, exist_ok=True)

BILINEAR = getattr(getattr(Image, "Resampling", Image), "BILINEAR")


# ============================================================
# LOAD MNIST
# ============================================================

(x_train, y_train), (x_test, y_test) = keras.datasets.mnist.load_data()

OUT_DIR = Path("out_lwdd_numpy_ptq_fast")
OUT_DIR.mkdir(parents=True, exist_ok=True)
BILINEAR = getattr(getattr(Image, "Resampling", Image), "BILINEAR")


def plot_data(x_data: np.ndarray, y_data: np.ndarray, y_scores: Optional[np.ndarray] = None) -> None:
    nrows, ncols = 4, 8
    fig, axes = plt.subplots(nrows, ncols, figsize=(16, 8))
    len_x = x_data.shape[0]

    for idx in range(nrows * ncols):
        ax = axes[idx // ncols, idx % ncols]
        img_idx = rd.randint(0, len_x - 1)

        ax.imshow(x_data[img_idx].squeeze(), cmap="gray")
        ax.axis("off")

        if y_scores is not None:
            predicted_idx = np.argmax(y_scores[img_idx])
            true_idx = y_data[img_idx]
            title_color = "green" if predicted_idx == true_idx else "red"
            ax.set_title(f"Pred: {predicted_idx}\nLabel: {true_idx}", color=title_color)
        else:
            ax.set_title(f"Label: {y_data[img_idx]}")

    plt.tight_layout()
    plt.close(fig)


x_train = x_train.astype("float32") / 255.0
x_test = x_test.astype("float32") / 255.0
x_train = np.expand_dims(x_train, axis=-1)
x_test = np.expand_dims(x_test, axis=-1)

if FAST_DEBUG:
    # Chỉ rút gọn TRAIN để debug nhanh.
    # TEST vẫn giữ nguyên để phần render/evaluate luôn chạy trên tập test.
    x_train = x_train[:1000]
    y_train = y_train[:1000]


# ============================================================
# CAMERA-LIKE AUGMENTATION
# ============================================================

def _to_uint8_image(x: np.ndarray) -> Image.Image:
    arr = np.asarray(x).squeeze()
    arr = np.clip(arr * 255.0, 0, 255).astype(np.uint8)
    return Image.fromarray(arr, mode="L")


def _from_uint8_image(img: Image.Image) -> np.ndarray:
    img = img.resize((28, 28), BILINEAR)
    arr = np.asarray(img, dtype=np.float32) / 255.0
    return arr.reshape(28, 28, 1).astype(np.float32)


def augment_image_np(x: np.ndarray) -> np.ndarray:
    """
    Augmentation kiểu camera, giữ input/output:
      shape = (28,28,1)
      range = [0,1]

    Gồm:
      shift
      rotate nhẹ
      zoom nhẹ
      brightness/contrast
      blur nhẹ
      threshold variation
    """
    img = _to_uint8_image(x)

    # shift
    dx = rd.randint(-2, 2)
    dy = rd.randint(-2, 2)
    shifted = Image.new("L", (28, 28), 0)
    shifted.paste(img, (dx, dy))
    img = shifted

    # rotate nhỏ
    if rd.random() < 0.70:
        angle = rd.uniform(-8.0, 8.0)
        img = img.rotate(angle, resample=BILINEAR, fillcolor=0)

    # zoom nhẹ
    if rd.random() < 0.60:
        scale = rd.uniform(0.88, 1.15)
        new_size = max(20, min(34, int(round(28 * scale))))

        resized = img.resize((new_size, new_size), BILINEAR)
        canvas = Image.new("L", (28, 28), 0)

        ox = (28 - new_size) // 2
        oy = (28 - new_size) // 2
        canvas.paste(resized, (ox, oy))
        img = canvas.crop((0, 0, 28, 28))

    # brightness / contrast
    if rd.random() < 0.70:
        img = ImageEnhance.Brightness(img).enhance(rd.uniform(0.65, 1.35))

    if rd.random() < 0.70:
        img = ImageEnhance.Contrast(img).enhance(rd.uniform(0.70, 1.50))

    # blur nhẹ
    if rd.random() < 0.25:
        img = img.filter(ImageFilter.GaussianBlur(radius=rd.uniform(0.25, 0.85)))

    # threshold variation
    if rd.random() < 0.25:
        th = rd.randint(60, 160)
        img = img.point(lambda p: 255 if p > th else 0)

    return _from_uint8_image(img)


# ============================================================
# ORIGINAL SOURCE STRUCTURE: LAYERS
# ============================================================

class Conv3x3:
    """
    3x3 convolution, channels-last, vectorized NumPy version.
    Input:  (H, W, C_in)
    Output:
      - padding='same'  -> (H, W, C_out)
      - padding='valid' -> (H-2, W-2, C_out)

    Speed note:
      Forward and filter-gradient use sliding_window_view + tensordot.
      Input-gradient keeps only a tiny 3x3 loop, not H/W/filter loops.
    """

    def __init__(self, in_channels, num_filters, padding="same", use_bias=False):
        if padding not in ("same", "valid"):
            raise ValueError("padding must be 'same' or 'valid'")

        self.in_channels = in_channels
        self.num_filters = num_filters
        self.padding = padding
        self.use_bias = use_bias

        scale = np.sqrt(2.0 / (3 * 3 * in_channels))
        self.filters = (np.random.randn(3, 3, in_channels, num_filters) * scale).astype(np.float32)
        self.biases = np.zeros(num_filters, dtype=np.float32) if use_bias else None

    def _pad_input(self, x: np.ndarray) -> np.ndarray:
        if self.padding == "same":
            return np.pad(x, ((1, 1), (1, 1), (0, 0)), mode="constant")
        return x

    def _windows3x3(self, x_padded: np.ndarray) -> np.ndarray:
        # NumPy returns shape (out_H, out_W, C, 3, 3) when sliding over axes (0,1).
        # Convert to (out_H, out_W, 3, 3, C) so it aligns with filters (3,3,C,F).
        win = np.lib.stride_tricks.sliding_window_view(
            x_padded,
            window_shape=(3, 3),
            axis=(0, 1),
        )
        return np.transpose(win, (0, 1, 3, 4, 2)).astype(np.float32, copy=False)

    def forward(self, x):
        if x.ndim != 3:
            raise ValueError("input must have shape (H, W, C)")
        if x.shape[2] != self.in_channels:
            raise ValueError(f"expected {self.in_channels} channels, got {x.shape[2]}")

        self.last_input = x.astype(np.float32, copy=False)
        self.last_input_padded = self._pad_input(self.last_input).astype(np.float32, copy=False)
        self.last_windows = self._windows3x3(self.last_input_padded)

        # windows: (out_H, out_W, 3, 3, Cin)
        # filters: (3, 3, Cin, Cout)
        # out:     (out_H, out_W, Cout)
        out = np.tensordot(
            self.last_windows,
            self.filters,
            axes=([2, 3, 4], [0, 1, 2]),
        ).astype(np.float32)

        if self.use_bias:
            out += self.biases.reshape(1, 1, -1)

        return out

    def backprop(self, d_L_d_out, learn_rate):
        d_out = np.asarray(d_L_d_out, dtype=np.float32)

        # Filter gradient:
        # windows: (out_H,out_W,3,3,Cin)
        # d_out:  (out_H,out_W,Cout)
        # result: (3,3,Cin,Cout)
        d_L_d_filters = np.tensordot(
            self.last_windows,
            d_out,
            axes=([0, 1], [0, 1]),
        ).astype(np.float32)

        d_L_d_biases = d_out.sum(axis=(0, 1)).astype(np.float32) if self.use_bias else None

        # Input gradient:
        # keep only 9 small kernel-position loops; the channel/filter math is vectorized.
        x_pad = self.last_input_padded
        d_L_d_input_padded = np.zeros_like(x_pad, dtype=np.float32)
        out_H, out_W, _ = d_out.shape

        for ky in range(3):
            for kx in range(3):
                # d_out: filter-gradient wrt output channel
                # filters[ky,kx,:,:]: (Cin,Cout)
                # result per spatial position: (Cin)
                d_patch = np.tensordot(
                    d_out,
                    self.filters[ky, kx, :, :],
                    axes=([2], [1]),
                ).astype(np.float32)
                d_L_d_input_padded[ky:ky + out_H, kx:kx + out_W, :] += d_patch

        self.filters -= learn_rate * d_L_d_filters

        if self.use_bias:
            self.biases -= learn_rate * d_L_d_biases

        if self.padding == "same":
            return d_L_d_input_padded[1:-1, 1:-1, :]

        return d_L_d_input_padded


class ReLU:
    def forward(self, x):
        self.mask = x > 0
        return x * self.mask

    def backprop(self, d_L_d_out, learn_rate=None):
        return d_L_d_out * self.mask


class MaxPool2:
    """2x2 max-pooling, vectorized NumPy version."""

    def forward(self, x):
        self.last_input = x
        H, W, C = x.shape
        out_H = H // 2
        out_W = W // 2

        trimmed = x[:out_H * 2, :out_W * 2, :].astype(np.float32, copy=False)

        # blocks:  (out_H, 2, out_W, 2, C)
        # blocks4: (out_H, out_W, C, 4)
        blocks = trimmed.reshape(out_H, 2, out_W, 2, C)
        blocks4 = blocks.transpose(0, 2, 4, 1, 3).reshape(out_H, out_W, C, 4)

        flat_idx = np.argmax(blocks4, axis=3)
        out = np.take_along_axis(blocks4, flat_idx[..., None], axis=3)[..., 0].astype(np.float32)

        self.input_shape = x.shape
        self.out_H = out_H
        self.out_W = out_W
        self.argmax_flat = flat_idx

        return out

    def backprop(self, d_L_d_out, learn_rate=None):
        H, W, C = self.input_shape
        out_H = self.out_H
        out_W = self.out_W

        d4 = np.zeros((out_H, out_W, C, 4), dtype=np.float32)

        np.put_along_axis(
            d4,
            self.argmax_flat[..., None],
            d_L_d_out[..., None].astype(np.float32),
            axis=3,
        )

        d_small = d4.reshape(out_H, out_W, C, 2, 2)
        d_small = d_small.transpose(0, 3, 1, 4, 2).reshape(out_H * 2, out_W * 2, C)

        full = np.zeros((H, W, C), dtype=np.float32)
        full[:out_H * 2, :out_W * 2, :] = d_small
        return full


class GlobalMaxPool:
    """Global max-pooling, vectorized NumPy version."""

    def forward(self, x):
        H, W, C = x.shape
        self.input_shape = x.shape

        flat = x.reshape(H * W, C)
        self.argmax_idx = np.argmax(flat, axis=0)
        out = flat[self.argmax_idx, np.arange(C)].astype(np.float32)

        return out

    def backprop(self, d_L_d_out, learn_rate=None):
        H, W, C = self.input_shape
        grad_flat = np.zeros((H * W, C), dtype=np.float32)

        grad_flat[self.argmax_idx, np.arange(C)] = np.asarray(d_L_d_out, dtype=np.float32).reshape(-1)

        return grad_flat.reshape(H, W, C)


class Dense:
    def __init__(self, input_len, nodes):
        scale = np.sqrt(2.0 / input_len)
        self.weights = (np.random.randn(input_len, nodes) * scale).astype(np.float32)
        self.biases = np.zeros(nodes, dtype=np.float32)

    def forward(self, x):
        self.last_input_shape = x.shape
        self.last_input = x.flatten()
        return self.last_input @ self.weights + self.biases

    def backprop(self, d_L_d_out, learn_rate):
        d_L_d_w = self.last_input[:, np.newaxis] @ d_L_d_out[np.newaxis, :]
        d_L_d_b = d_L_d_out
        d_L_d_input = self.weights @ d_L_d_out

        self.weights -= learn_rate * d_L_d_w
        self.biases -= learn_rate * d_L_d_b

        return d_L_d_input.reshape(self.last_input_shape)


class LWDDModel:
    def __init__(self, use_bias=False):
        self.layers = [
            ("conv1", Conv3x3(1, 4, padding="same", use_bias=use_bias)),
            ("relu1", ReLU()),
            ("conv2", Conv3x3(4, 4, padding="same", use_bias=use_bias)),
            ("relu2", ReLU()),
            ("pool1", MaxPool2()),
            ("conv3", Conv3x3(4, 8, padding="same", use_bias=use_bias)),
            ("relu3", ReLU()),
            ("conv4", Conv3x3(8, 8, padding="same", use_bias=use_bias)),
            ("relu4", ReLU()),
            ("pool2", MaxPool2()),
            ("conv5", Conv3x3(8, 16, padding="same", use_bias=use_bias)),
            ("relu5", ReLU()),
            ("conv6", Conv3x3(16, 16, padding="same", use_bias=use_bias)),
            ("relu6", ReLU()),
            ("global_max_pool", GlobalMaxPool()),
            ("classifier", Dense(16, 10)),
        ]
        self.learning_rate = 1e-3
        self.margin = 1.0
        self.loss_name = "hinge_margin"

    def summary(self):
        print("Model: lwdd_mnist_hinge")
        print("=" * 40)
        for i, (name, layer) in enumerate(self.layers, 1):
            print(f"{i:02d}. {name:<18} {layer.__class__.__name__}")
        print("=" * 40)
        print("Output head: Dense logits (no softmax layer)")
        print(f"Training loss: multi-class hinge, margin={self.margin}")

    def compile(self, optimizer='rmsprop', loss='hinge_margin', metrics=None, learning_rate=None, margin=1.0):
        if learning_rate is not None:
            self.learning_rate = float(learning_rate)
        elif isinstance(optimizer, (int, float)):
            self.learning_rate = float(optimizer)
        else:
            self.learning_rate = 1e-3

        self.margin = float(margin)
        self.loss_name = loss
        self.metrics = metrics or []

    def forward(self, x):
        for _, layer in self.layers:
            x = layer.forward(x)
        return x.astype(np.float32, copy=False)

    def backward(self, grad):
        for _, layer in reversed(self.layers):
            grad = layer.backprop(grad, self.learning_rate)
        return grad

    def _loss_and_grad_from_logits(self, logits, label):
        num_classes = logits.shape[0]
        correct_logit = logits[label]

        grad = np.zeros_like(logits, dtype=np.float32)
        loss = 0.0

        for cls in range(num_classes):
            if cls == label:
                continue
            delta = self.margin - correct_logit + logits[cls]
            if delta > 0:
                loss += delta
                grad[cls] += 1.0
                grad[label] -= 1.0

        if num_classes > 1:
            norm = float(num_classes - 1)
            loss /= norm
            grad /= norm

        return float(loss), grad

    def train_step(self, x, label):
        logits = self.forward(x)
        loss, grad = self._loss_and_grad_from_logits(logits, label)
        self.backward(grad)
        acc = int(np.argmax(logits) == label)
        return loss, acc

    def fit(
        self,
        x_train,
        y_train,
        epochs=1,
        batch_size=32,
        validation_split=0.1,
        augment=False,
        augment_prob=1.0,
    ):
        n = len(x_train)
        split_idx = int(n * (1 - validation_split))
        x_tr, y_tr = x_train[:split_idx], y_train[:split_idx]
        x_val, y_val = x_train[split_idx:], y_train[split_idx:]

        history = {'loss': [], 'val_loss': [], 'accuracy': [], 'val_accuracy': []}

        for epoch in range(epochs):
            indices = np.random.permutation(len(x_tr))
            train_loss = 0.0
            train_correct = 0

            for start in range(0, len(indices), batch_size):
                batch_idx = indices[start:start + batch_size]

                batch_loss = 0.0
                batch_correct = 0

                for idx in batch_idx:
                    x_in = x_tr[idx]
                    if augment and rd.random() < augment_prob:
                        x_in = augment_image_np(x_in)

                    loss, acc = self.train_step(x_in, y_tr[idx])
                    train_loss += loss
                    train_correct += acc
                    batch_loss += loss
                    batch_correct += acc

                done = min(start + batch_size, len(indices))
                print(
                    f"[Epoch {epoch+1}/{epochs}] "
                    f"{done}/{len(indices)} "
                    f"- batch_loss: {batch_loss / len(batch_idx):.4f} "
                    f"- batch_acc: {batch_correct / len(batch_idx):.4f}",
                    flush=True
                )

            train_loss /= len(x_tr)
            train_acc = train_correct / len(x_tr)
            val_loss, val_acc = self.evaluate(x_val, y_val)

            history['loss'].append(train_loss)
            history['val_loss'].append(val_loss)
            history['accuracy'].append(train_acc)
            history['val_accuracy'].append(val_acc)

            print(
                f"Epoch {epoch + 1}/{epochs} - "
                f"loss: {train_loss:.4f} - accuracy: {train_acc:.4f} - "
                f"val_loss: {val_loss:.4f} - val_accuracy: {val_acc:.4f}",
                flush=True
            )

        return SimpleNamespace(history=history)

    def evaluate(self, x_data, y_data):
        total_loss = 0.0
        total_correct = 0

        for x, y in zip(x_data, y_data):
            logits = self.forward(x)
            loss, _ = self._loss_and_grad_from_logits(logits, y)
            total_loss += loss
            total_correct += int(np.argmax(logits) == y)

        avg_loss = total_loss / len(x_data)
        avg_acc = total_correct / len(x_data)
        return avg_loss, avg_acc

    def predict(self, x_data):
        logits_all = []
        for x in x_data:
            logits_all.append(self.forward(x))
        return np.array(logits_all, dtype=np.float32)


def build_lwdd_mnist(use_bias=False):
    return LWDDModel(use_bias=use_bias)


# ============================================================
# POST-TRAIN QUANTIZATION + EXPORT
# ============================================================

def quantize_symmetric(arr: np.ndarray, bits: int = 16):
    arr = np.asarray(arr, dtype=np.float32)

    qmax = (2 ** (bits - 1)) - 1
    qmin = -(2 ** (bits - 1))

    max_abs = float(np.max(np.abs(arr))) if arr.size else 0.0

    if max_abs == 0:
        scale = 1.0
        q = np.zeros_like(arr, dtype=np.int16 if bits == 16 else np.int32)
    else:
        scale = max_abs / qmax
        q = np.round(arr / scale)
        q = np.clip(q, qmin, qmax)

    if bits == 16:
        return q.astype(np.int16), float(scale)

    if bits == 32:
        return q.astype(np.int32), float(scale)

    raise ValueError("Only int16/int32 supported")


def dequantize(q: np.ndarray, scale: float):
    return np.asarray(q, dtype=np.float32) * float(scale)


def get_trainable_layers(model: LWDDModel):
    trainable = []

    for name, layer in model.layers:
        if isinstance(layer, Conv3x3):
            trainable.append((name, layer, "conv"))
        elif isinstance(layer, Dense):
            trainable.append((name, layer, "dense"))

    return trainable


def quantize_model_post_train(model: LWDDModel):
    qpack = {
        "format": "LWDD_NUMPY_PTQ_V1",
        "weight_dtype": "int16",
        "bias_dtype": "int32",
        "layers": [],
    }

    for name, layer, kind in get_trainable_layers(model):
        entry = {
            "name": name,
            "kind": kind,
        }

        if kind == "conv":
            qw, sw = quantize_symmetric(layer.filters, bits=16)

            entry["filters_q"] = qw
            entry["filters_scale"] = sw
            entry["filters_shape"] = list(layer.filters.shape)

            if layer.use_bias and layer.biases is not None:
                qb, sb = quantize_symmetric(layer.biases, bits=32)

                entry["bias_q"] = qb
                entry["bias_scale"] = sb
                entry["bias_shape"] = list(layer.biases.shape)
            else:
                entry["bias_q"] = None
                entry["bias_scale"] = None
                entry["bias_shape"] = None

        elif kind == "dense":
            qw, sw = quantize_symmetric(layer.weights, bits=16)
            qb, sb = quantize_symmetric(layer.biases, bits=32)

            entry["weights_q"] = qw
            entry["weights_scale"] = sw
            entry["weights_shape"] = list(layer.weights.shape)

            entry["bias_q"] = qb
            entry["bias_scale"] = sb
            entry["bias_shape"] = list(layer.biases.shape)

        qpack["layers"].append(entry)

    return qpack


def clone_quantized_to_float_model(model: LWDDModel, qpack: dict):
    """
    Tạo model mới cùng cấu trúc, nhưng weights đã qua:
      float -> int quant -> dequant float

    Cách này dùng để đo accuracy drop sau post-train quantization.
    """
    qmodel = deepcopy(model)
    q_layers = {entry["name"]: entry for entry in qpack["layers"]}

    for name, layer, kind in get_trainable_layers(qmodel):
        entry = q_layers[name]

        if kind == "conv":
            layer.filters = dequantize(entry["filters_q"], entry["filters_scale"]).astype(np.float32)

            if layer.use_bias and layer.biases is not None and entry["bias_q"] is not None:
                layer.biases = dequantize(entry["bias_q"], entry["bias_scale"]).astype(np.float32)

        elif kind == "dense":
            layer.weights = dequantize(entry["weights_q"], entry["weights_scale"]).astype(np.float32)
            layer.biases = dequantize(entry["bias_q"], entry["bias_scale"]).astype(np.float32)

    return qmodel


def predict_labels(model: LWDDModel, x_data: np.ndarray):
    logits = model.predict(x_data)
    preds = np.argmax(logits, axis=1)
    return preds.astype(np.int64), logits.astype(np.float32)


def evaluate_preds(preds: np.ndarray, labels: np.ndarray):
    return float(np.mean(np.asarray(preds) == np.asarray(labels)))


def save_failure_cases(
    out_dir: str | Path,
    x_data: np.ndarray,
    y_data: np.ndarray,
    float_preds: np.ndarray,
    quant_preds: np.ndarray,
    float_logits: np.ndarray,
    quant_logits: np.ndarray,
    max_each: int | None = None,
):
    out_dir = Path(out_dir)
    root = out_dir / "failure_cases"
    root.mkdir(parents=True, exist_ok=True)

    buckets = {
        "float_correct_ptq_wrong": [],
        "float_wrong_ptq_correct": [],
        "both_wrong": [],
    }

    for i, (y, pf, pq) in enumerate(zip(y_data, float_preds, quant_preds)):
        y = int(y)
        pf = int(pf)
        pq = int(pq)

        if pf == y and pq != y:
            buckets["float_correct_ptq_wrong"].append(i)
        elif pf != y and pq == y:
            buckets["float_wrong_ptq_correct"].append(i)
        elif pf != y and pq != y:
            buckets["both_wrong"].append(i)

    summary = {}

    for bucket_name, indices in buckets.items():
        folder = root / bucket_name
        folder.mkdir(parents=True, exist_ok=True)

        selected = indices if max_each is None else indices[:max_each]

        summary[bucket_name] = {
            "total": len(indices),
            "saved": len(selected),
        }

        metadata = []

        for k, idx in enumerate(selected):
            y = int(y_data[idx])
            pf = int(float_preds[idx])
            pq = int(quant_preds[idx])

            fig, ax = plt.subplots(figsize=(2.8, 3.8))
            ax.imshow(x_data[idx].squeeze(), cmap="gray")
            ax.set_xticks([])
            ax.set_yticks([])
            ax.text(
                0.5,
                -0.18,
                f"Tag: {y}\nFloat: {pf}\nPTQ: {pq}",
                transform=ax.transAxes,
                ha="center",
                va="top",
                fontsize=9,
            )
            fig.subplots_adjust(bottom=0.28)

            out_png = folder / f"{k:05d}_idx{idx}_y{y}_f{pf}_q{pq}.png"
            fig.savefig(out_png, dpi=160, bbox_inches="tight")
            plt.close(fig)

            metadata.append(
                {
                    "index": int(idx),
                    "tag": y,
                    "float_pred": pf,
                    "ptq_pred": pq,
                    "float_logits": [float(v) for v in float_logits[idx]],
                    "quant_logits": [float(v) for v in quant_logits[idx]],
                    "png": str(out_png),
                }
            )

        with (folder / "metadata.json").open("w", encoding="utf-8") as f:
            json.dump(metadata, f, indent=2)

    with (root / "summary.json").open("w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)

    print(f"[FAILURE CASES] saved to {root}")

    return summary


def render_float_ptq_mistakes_grid(
    out_dir: str | Path,
    x_data: np.ndarray,
    y_data: np.ndarray,
    float_preds: np.ndarray,
    ptq_preds: np.ndarray,
    float_logits: Optional[np.ndarray] = None,
    ptq_logits: Optional[np.ndarray] = None,
    max_images: int = 40,
    ncols: int = 5,
):
    """
    Render ONLY the first max_images test samples where at least one model is wrong.
    Each image always has exactly 3 lines below it:
      Tag / Float / PTQ
    """
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    y_arr = np.asarray(y_data).astype(np.int64)
    float_arr = np.asarray(float_preds).astype(np.int64)
    ptq_arr = np.asarray(ptq_preds).astype(np.int64)

    wrong_mask = (float_arr != y_arr) | (ptq_arr != y_arr)
    wrong_indices = np.where(wrong_mask)[0]
    selected = wrong_indices[:max_images]

    metadata = []
    for idx in selected:
        y = int(y_arr[idx])
        pf = int(float_arr[idx])
        pq = int(ptq_arr[idx])

        if pf != y and pq != y:
            case = "both_wrong"
        elif pf != y:
            case = "float_wrong_ptq_correct"
        else:
            case = "float_correct_ptq_wrong"

        item = {
            "index": int(idx),
            "tag": y,
            "float_pred": pf,
            "ptq_pred": pq,
            "case": case,
        }
        if float_logits is not None:
            item["float_logits"] = [float(v) for v in float_logits[idx]]
        if ptq_logits is not None:
            item["ptq_logits"] = [float(v) for v in ptq_logits[idx]]
        metadata.append(item)

    meta_path = out_dir / "float_ptq_mistakes_metadata.json"
    with meta_path.open("w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2)

    if len(selected) == 0:
        print("[MISTAKE GRID] No mistake found: both float and PTQ are correct on all test samples.")
        return {
            "total_mistakes_in_test": int(len(wrong_indices)),
            "rendered_images": 0,
            "saved_grid": None,
            "metadata": str(meta_path),
        }

    ncols = max(1, int(ncols))
    nrows = int(np.ceil(len(selected) / ncols))

    fig, axes = plt.subplots(nrows, ncols, figsize=(2.6 * ncols, 3.6 * nrows))
    axes = np.atleast_1d(axes).reshape(-1)

    for ax in axes:
        ax.axis("off")

    for ax_i, idx in enumerate(selected):
        ax = axes[ax_i]
        y = int(y_arr[idx])
        pf = int(float_arr[idx])
        pq = int(ptq_arr[idx])

        ax.imshow(x_data[idx].squeeze(), cmap="gray")
        ax.set_xticks([])
        ax.set_yticks([])
        ax.text(
            0.5,
            -0.18,
            f"Tag: {y}\nFloat: {pf}\nPTQ: {pq}",
            transform=ax.transAxes,
            ha="center",
            va="top",
            fontsize=9,
        )

    fig.subplots_adjust(hspace=0.95, wspace=0.28, bottom=0.05, top=0.97)

    grid_path = out_dir / "float_ptq_mistakes_grid_40.png"
    fig.savefig(grid_path, dpi=180, bbox_inches="tight")
    plt.close(fig)

    print(f"[MISTAKE GRID] rendered {len(selected)} / {len(wrong_indices)} wrong test samples to {grid_path}")

    return {
        "total_mistakes_in_test": int(len(wrong_indices)),
        "rendered_images": int(len(selected)),
        "saved_grid": str(grid_path),
        "metadata": str(meta_path),
    }


def export_quantized_params(qpack: dict, out_dir: str | Path):
    out_dir = Path(out_dir)
    export_dir = out_dir / "fpga_export"
    export_dir.mkdir(parents=True, exist_ok=True)

    bin_path = export_dir / "lwdd_params_int16_int32.bin"
    txt_path = export_dir / "lwdd_params_int16_int32.txt"
    map_path = export_dir / "memory_map.json"

    blob = bytearray()

    memory_map = {
        "format": qpack["format"],
        "endian": "little",
        "weight_dtype": "int16",
        "bias_dtype": "int32",
        "tensors": [],
    }

    def align4():
        while len(blob) % 4 != 0:
            blob.append(0)

    def append_tensor(name: str, arr: np.ndarray, dtype: str, scale: float):
        align4()
        offset = len(blob)

        if dtype == "int16":
            arr_le = np.asarray(arr, dtype="<i2")
        elif dtype == "int32":
            arr_le = np.asarray(arr, dtype="<i4")
        else:
            raise ValueError(dtype)

        raw = arr_le.tobytes(order="C")
        blob.extend(raw)
        align4()

        memory_map["tensors"].append(
            {
                "name": name,
                "offset": int(offset),
                "bytes": int(len(raw)),
                "shape": list(arr.shape),
                "dtype": dtype,
                "scale": float(scale),
                "alignment": 4,
            }
        )

    with txt_path.open("w", encoding="utf-8") as ftxt:
        for entry in qpack["layers"]:
            name = entry["name"]
            kind = entry["kind"]

            if kind == "conv":
                append_tensor(f"{name}.filters", entry["filters_q"], "int16", entry["filters_scale"])

                ftxt.write(
                    f"# {name}.filters "
                    f"shape={entry['filters_shape']} "
                    f"dtype=int16 "
                    f"scale={entry['filters_scale']}\n"
                )

                flat = entry["filters_q"].reshape(-1)

                for i, v in enumerate(flat):
                    ftxt.write(str(int(v)))
                    ftxt.write("\n" if (i + 1) % 16 == 0 else " ")

                ftxt.write("\n\n")

                if entry["bias_q"] is not None:
                    append_tensor(f"{name}.bias", entry["bias_q"], "int32", entry["bias_scale"])

                    ftxt.write(
                        f"# {name}.bias "
                        f"shape={entry['bias_shape']} "
                        f"dtype=int32 "
                        f"scale={entry['bias_scale']}\n"
                    )

                    flat = entry["bias_q"].reshape(-1)

                    for i, v in enumerate(flat):
                        ftxt.write(str(int(v)))
                        ftxt.write("\n" if (i + 1) % 16 == 0 else " ")

                    ftxt.write("\n\n")

            elif kind == "dense":
                append_tensor(f"{name}.weights", entry["weights_q"], "int16", entry["weights_scale"])
                append_tensor(f"{name}.bias", entry["bias_q"], "int32", entry["bias_scale"])

                ftxt.write(
                    f"# {name}.weights "
                    f"shape={entry['weights_shape']} "
                    f"dtype=int16 "
                    f"scale={entry['weights_scale']}\n"
                )

                flat = entry["weights_q"].reshape(-1)

                for i, v in enumerate(flat):
                    ftxt.write(str(int(v)))
                    ftxt.write("\n" if (i + 1) % 16 == 0 else " ")

                ftxt.write("\n\n")

                ftxt.write(
                    f"# {name}.bias "
                    f"shape={entry['bias_shape']} "
                    f"dtype=int32 "
                    f"scale={entry['bias_scale']}\n"
                )

                flat = entry["bias_q"].reshape(-1)

                for i, v in enumerate(flat):
                    ftxt.write(str(int(v)))
                    ftxt.write("\n" if (i + 1) % 16 == 0 else " ")

                ftxt.write("\n\n")

    bin_path.write_bytes(bytes(blob))
    memory_map["total_bytes"] = len(blob)

    with map_path.open("w", encoding="utf-8") as f:
        json.dump(memory_map, f, indent=2)

    print(f"[EXPORT] bin: {bin_path}")
    print(f"[EXPORT] txt: {txt_path}")
    print(f"[EXPORT] map: {map_path}")

    return {
        "bin": str(bin_path),
        "txt": str(txt_path),
        "map": str(map_path),
        "total_bytes": len(blob),
    }


def plot_float_vs_quant(float_acc: float, quant_acc: float, out_dir: str | Path):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    plt.figure(figsize=(6, 4))
    plt.bar(["float", "post_train_quant"], [float_acc, quant_acc])
    plt.ylim(0, 1)
    plt.ylabel("accuracy")
    plt.title("Float vs Post-Training Quantized Accuracy")

    plt.text(0, float_acc + 0.01, f"{float_acc * 100:.2f}%", ha="center")
    plt.text(1, quant_acc + 0.01, f"{quant_acc * 100:.2f}%", ha="center")

    plt.tight_layout()
    plt.savefig(out_dir / "float_vs_quant_accuracy.png", dpi=160)
    plt.close()


def run_post_train_quant_pipeline(model: LWDDModel, x_test, y_test, out_dir="out_lwdd_numpy_ptq"):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    float_preds, float_logits = predict_labels(model, x_test)
    float_acc = evaluate_preds(float_preds, y_test)

    qpack = quantize_model_post_train(model)
    qmodel = clone_quantized_to_float_model(model, qpack)

    quant_preds, quant_logits = predict_labels(qmodel, x_test)
    quant_acc = evaluate_preds(quant_preds, y_test)

    print("=" * 60)
    print("POST-TRAIN QUANTIZATION RESULT")
    print("=" * 60)
    print(f"Float accuracy : {float_acc * 100:.2f}%")
    print(f"Quant accuracy : {quant_acc * 100:.2f}%")
    print(f"Accuracy drop  : {(float_acc - quant_acc) * 100:.2f}%")
    print("=" * 60)

    plot_float_vs_quant(float_acc, quant_acc, out_dir)

    failure_summary = save_failure_cases(
        out_dir=out_dir,
        x_data=x_test,
        y_data=y_test,
        float_preds=float_preds,
        quant_preds=quant_preds,
        float_logits=float_logits,
        quant_logits=quant_logits,
        max_each=40,
    )

    mistake_grid_summary = render_float_ptq_mistakes_grid(
        out_dir=out_dir,
        x_data=x_test,
        y_data=y_test,
        float_preds=float_preds,
        ptq_preds=quant_preds,
        float_logits=float_logits,
        ptq_logits=quant_logits,
        max_images=40,
        ncols=5,
    )

    export_info = export_quantized_params(qpack, out_dir)

    summary = {
        "float_accuracy": float(float_acc),
        "quant_accuracy": float(quant_acc),
        "accuracy_drop": float(float_acc - quant_acc),
        "failure_summary": failure_summary,
        "mistake_grid_summary": mistake_grid_summary,
        "export": export_info,
    }

    with (out_dir / "summary.json").open("w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)

    return qmodel, summary


# ============================================================
# MAIN TRAINING - GIỮ STYLE SOURCE GỐC
# ============================================================

model = build_lwdd_mnist(use_bias=False)

model.summary()

model.compile(
    optimizer="rmsprop",
    loss="hinge_margin",
    metrics=["accuracy"],
    learning_rate=1e-3,
    margin=1.0,
)

epochs = 20
batch_size = 256

history = model.fit(
    x_train,
    y_train,
    epochs=epochs,
    batch_size=batch_size,
    validation_split=0.1,
    augment=True,
)

history_dict = history.history
train_loss = history_dict["loss"]
val_loss = history_dict["val_loss"]
train_acc = history_dict["accuracy"]
val_acc = history_dict["val_accuracy"]

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(15, 5))
epoch_runs = [i + 1 for i in range(epochs)]

ax1.plot(epoch_runs, train_loss, label="Training loss", marker="o")
ax1.plot(epoch_runs, val_loss, label="Validation loss", marker="o")
ax1.set(title="Training loss vs Validation loss", xlabel="Epochs", ylabel="Loss")
ax1.legend()

ax2.plot(epoch_runs, train_acc, label="Training accuracy", marker="o")
ax2.plot(epoch_runs, val_acc, label="Validation accuracy", marker="o")
ax2.set(title="Training accuracy vs Validation accuracy", xlabel="Epochs", ylabel="Accuracy")
ax2.legend()

plt.tight_layout()
plt.savefig(OUT_DIR / "training_curves.png", dpi=160)
plt.show()

score = model.evaluate(x_test, y_test)
print(f"Test Loss: {score[0]:.4f}\nTest Accuracy: {score[1]:.4f}")

# Không render random toàn bộ test set nữa.
# Chỉ render các ảnh mà Float hoặc PTQ sai trong run_post_train_quant_pipeline().
qmodel, qsummary = run_post_train_quant_pipeline(
    model,
    x_test,
    y_test,
    out_dir=OUT_DIR,
)

# Không render random toàn bộ PTQ test set.
