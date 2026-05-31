from tensorflow import keras  # type: ignore
import matplotlib
matplotlib.use("TkAgg")
import matplotlib.pyplot as plt
import numpy as np
import random as rd
from typing import Optional
from types import SimpleNamespace

(x_train, y_train), (x_test, y_test) = keras.datasets.mnist.load_data()


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
    plt.show()


x_train = x_train.astype("float32") / 255.0
x_test = x_test.astype("float32") / 255.0
x_train = np.expand_dims(x_train, axis=-1)
x_test = np.expand_dims(x_test, axis=-1)


# Optional: use a smaller subset while debugging speed/progress
FAST_DEBUG = True
if FAST_DEBUG:
    x_train = x_train[:1000]
    y_train = y_train[:1000]
    x_test = x_test[:200]
    y_test = y_test[:200]


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

    def fit(self, x_train, y_train, epochs=1, batch_size=32, validation_split=0.1):
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
                    loss, acc = self.train_step(x_tr[idx], y_tr[idx])
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


model = build_lwdd_mnist(use_bias=False)
model.summary()
model.compile(
    optimizer='rmsprop',
    loss='hinge_margin',
    metrics=['accuracy'],
    learning_rate=1e-3,
    margin=1.0,
)

epochs = 20
batch_size = 256
history = model.fit(
    x_train, y_train,
    epochs=epochs,
    batch_size=batch_size,
    validation_split=0.1
)

history_dict = history.history
train_loss, val_loss = history_dict['loss'], history_dict['val_loss']
train_acc, val_acc = history_dict['accuracy'], history_dict['val_accuracy']

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(15, 5))
epoch_runs = [i + 1 for i in range(epochs)]

ax1.plot(epoch_runs, train_loss, label="Training loss", marker='o')
ax1.plot(epoch_runs, val_loss, label="Validation loss", marker='o')
ax1.set(title="Training loss vs Validation loss", xlabel="Epochs", ylabel="Loss")
ax1.legend()

ax2.plot(epoch_runs, train_acc, label="Training accuracy", marker='o')
ax2.plot(epoch_runs, val_acc, label="Validation accuracy", marker='o')
ax2.set(title="Training accuracy vs Validation accuracy", xlabel="Epochs", ylabel="accuracy")
ax2.legend()

plt.tight_layout()
plt.show()

score = model.evaluate(x_test, y_test)
print(f"Test Loss: {score[0]:.4f}\nTest Accuracy: {score[1]:.4f}")

y_scores = model.predict(x_test)
plot_data(x_test, y_test, y_scores)
