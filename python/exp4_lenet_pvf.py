"""
Experiment 4 - Application-level fault propagation in LeNet (paper Sections 4.2 and 5, Fig. 5)

What it does (same method as the paper):
  1. Trains LeNet on MNIST with PyTorch (first run only) and saves the weights.
  2. Runs LeNet inference in NumPy, doing every conv / fully-connected layer as a
     matrix multiplication (im2col), split into N x N output blocks like a systolic array.
  3. Injects a PERSISTENT error pattern (single, partial line, full line, full matrix)
     into every block of the target layer and of every later layer
     (a stuck fault in the array corrupts every later multiplication).
  4. Measures the Program Vulnerability Factor (PVF):
        tolerable error = output scores changed, predicted digit unchanged
        critical error  = predicted digit changed
     for array sizes N = 4, 16, 64, 256 and target layers 1-5
     (1-3 convolutional, 4-5 fully connected), like the paper's Fig. 5.

Usage:
  python exp4_lenet_pvf.py                 # 200 faults per bar (a few minutes)
  python exp4_lenet_pvf.py --faults 1000   # paper setting (+-~3% error), slower
  python exp4_lenet_pvf.py --selftest      # random weights, no PyTorch needed (checks the code runs)

Outputs: exp4_lenet_pvf.csv, exp4_lenet_pvf.png, lenet_mnist.npz (trained weights + 1000 test images)
"""
import argparse, csv, os, time
import numpy as np

PATTERNS = ["Single", "Partial line", "Full line", "Full matrix"]
LAYERS = ["conv1", "conv2", "conv3", "fc1", "fc2"]

# ----------------------------------------------------------------------------- training
def train_and_save(path):
    import torch, torch.nn as nn, torch.nn.functional as F
    from torchvision import datasets, transforms

    class LeNet(nn.Module):
        def __init__(self):
            super().__init__()
            self.conv1 = nn.Conv2d(1, 6, 5, padding=2)
            self.conv2 = nn.Conv2d(6, 16, 5)
            self.conv3 = nn.Conv2d(16, 120, 5)
            self.fc1 = nn.Linear(120, 84)
            self.fc2 = nn.Linear(84, 10)
        def forward(self, x):
            x = F.max_pool2d(F.relu(self.conv1(x)), 2)
            x = F.max_pool2d(F.relu(self.conv2(x)), 2)
            x = F.relu(self.conv3(x)).flatten(1)
            x = F.relu(self.fc1(x))
            return self.fc2(x)

    torch.manual_seed(0)
    tf = transforms.ToTensor()
    train = datasets.MNIST("data", train=True, download=True, transform=tf)
    test = datasets.MNIST("data", train=False, download=True, transform=tf)
    tl = torch.utils.data.DataLoader(train, batch_size=64, shuffle=True)
    model = LeNet()
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    for epoch in range(3):
        model.train()
        for x, y in tl:
            opt.zero_grad()
            F.cross_entropy(model(x), y).backward()
            opt.step()
        print(f"  epoch {epoch+1}/3 done")
    model.eval()
    with torch.no_grad():
        xt = test.data.float().unsqueeze(1) / 255.0
        acc = (model(xt).argmax(1) == test.targets).float().mean().item()
    print(f"  PyTorch test accuracy: {100*acc:.2f} %")
    w = {k: v.detach().numpy() for k, v in model.state_dict().items()}
    np.savez(path, **{k.replace(".", "_"): v for k, v in w.items()},
             images=(test.data[:1000].numpy() / 255.0).astype(np.float32),
             labels=test.targets[:1000].numpy())

# ----------------------------------------------------------------------------- numpy LeNet
def im2col(x, k, pad):
    """x: (C,H,W) -> patches (H_out*W_out, C*k*k), same ordering as PyTorch weights."""
    if pad:
        x = np.pad(x, ((0, 0), (pad, pad), (pad, pad)))
    win = np.lib.stride_tricks.sliding_window_view(x, (k, k), axis=(1, 2))   # C,Ho,Wo,k,k
    c, ho, wo = win.shape[:3]
    return win.transpose(1, 2, 0, 3, 4).reshape(ho * wo, c * k * k), ho, wo

def maxpool2(x):
    c, h, w = x.shape
    return x.reshape(c, h // 2, 2, w // 2, 2).max(axis=(2, 4))

class Fault:
    """A persistent error pattern inside an N x N block, applied from layer `start` onwards."""
    def __init__(self, n, pattern, start, rng):
        self.n, self.start, self.rng = n, start, rng
        if pattern == "Single":
            pos = [(rng.integers(n), rng.integers(n))]
        elif pattern in ("Partial line", "Full line"):
            line, horizontal = rng.integers(n), rng.random() < 0.5
            if pattern == "Full line":
                idx = np.arange(n)
            else:
                count = rng.integers(2, n) if n > 2 else 2
                idx = rng.choice(n, size=count, replace=False)
            pos = [(line, j) if horizontal else (j, line) for j in idx]
        else:  # Full matrix
            pos = [(r, c) for r in range(n) for c in range(n)]
        self.r = np.array([p[0] for p in pos]); self.c = np.array([p[1] for p in pos])

    def apply(self, C, layer):
        if layer < self.start:
            return C
        rows, cols = C.shape
        n = self.n
        br, bc = np.meshgrid(np.arange(0, rows, n), np.arange(0, cols, n), indexing="ij")
        R = (br.reshape(-1, 1) + self.r.reshape(1, -1)).ravel()
        K = (bc.reshape(-1, 1) + self.c.reshape(1, -1)).ravel()
        keep = (R < rows) & (K < cols)          # positions outside the real matrix are masked
        if not keep.any():
            return C
        m = np.abs(C).max() + 1e-6
        C = C.copy()
        C[R[keep], K[keep]] = self.rng.uniform(-m, m, size=keep.sum())
        return C

def forward(w, img, fault=None):
    def mxm(A, B, layer):
        C = A @ B
        return fault.apply(C, layer) if fault else C
    x = img.reshape(1, 28, 28)
    for layer, (name, pad) in enumerate([("conv1", 2), ("conv2", 0), ("conv3", 0)]):
        W, b = w[f"{name}_weight"], w[f"{name}_bias"]
        A, ho, wo = im2col(x, W.shape[2], pad)
        C = mxm(A, W.reshape(W.shape[0], -1).T, layer)
        x = np.maximum(C.T.reshape(W.shape[0], ho, wo) + b[:, None, None], 0)
        if layer < 2:
            x = maxpool2(x)
    v = x.reshape(1, -1)
    v = np.maximum(mxm(v, w["fc1_weight"].T, 3) + w["fc1_bias"], 0)
    return (mxm(v, w["fc2_weight"].T, 4) + w["fc2_bias"]).ravel()

# ----------------------------------------------------------------------------- experiment
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--faults", type=int, default=200, help="faults per bar (paper: 1000)")
    ap.add_argument("--sizes", type=int, nargs="+", default=[4, 16, 64, 256])
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    rng = np.random.default_rng(args.seed)

    if args.selftest:
        print("SELFTEST: random weights and images (results are meaningless)")
        g = np.random.default_rng(0)
        w = {"conv1_weight": g.normal(0, .3, (6, 1, 5, 5)), "conv1_bias": g.normal(0, .1, 6),
             "conv2_weight": g.normal(0, .1, (16, 6, 5, 5)), "conv2_bias": g.normal(0, .1, 16),
             "conv3_weight": g.normal(0, .05, (120, 16, 5, 5)), "conv3_bias": g.normal(0, .1, 120),
             "fc1_weight": g.normal(0, .1, (84, 120)), "fc1_bias": g.normal(0, .1, 84),
             "fc2_weight": g.normal(0, .1, (10, 84)), "fc2_bias": g.normal(0, .1, 10)}
        images, labels = g.random((50, 28, 28)), g.integers(0, 10, 50)
    else:
        path = "lenet_mnist.npz"
        if not os.path.exists(path):
            print("Training LeNet on MNIST (first run only, downloads ~11 MB)...")
            train_and_save(path)
        d = np.load(path)
        w = {k: d[k].astype(np.float64) for k in d.files if k not in ("images", "labels")}
        images, labels = d["images"].astype(np.float64), d["labels"]

    golden = np.array([forward(w, im) for im in images])
    acc = (golden.argmax(1) == labels).mean()
    print(f"NumPy LeNet accuracy on {len(images)} test images: {100*acc:.2f} %")

    rows, t0 = [], time.time()
    for n in args.sizes:
        for pattern in PATTERNS:
            for layer in range(5):
                tol = crit = 0
                for _ in range(args.faults):
                    k = rng.integers(len(images))
                    out = forward(w, images[k], Fault(n, pattern, layer, rng))
                    if np.max(np.abs(out - golden[k])) > 1e-6:
                        if out.argmax() != golden[k].argmax():
                            crit += 1
                        else:
                            tol += 1
                f = args.faults
                rows.append([n, pattern, layer + 1, LAYERS[layer], f,
                             round(100 * tol / f, 2), round(100 * crit / f, 2), round(100 * (tol + crit) / f, 2)])
            print(f"N={n:3d} {pattern:12s} done  ({time.time()-t0:.0f} s)")

    with open("exp4_lenet_pvf.csv", "w", newline="") as fh:
        wr = csv.writer(fh)
        wr.writerow(["array_size_N", "pattern", "target_layer", "layer_name", "faults",
                     "tolerable_percent", "critical_percent", "pvf_percent"])
        wr.writerows(rows)

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    fig, axes = plt.subplots(1, len(args.sizes), figsize=(4 * len(args.sizes), 3.8), sharey=True)
    axes = np.atleast_1d(axes)
    for ax, n in zip(axes, args.sizes):
        sub = [r for r in rows if r[0] == n]
        xs = np.arange(len(sub)) + np.repeat(np.arange(len(PATTERNS)), 5)
        ax.bar(xs, [r[5] for r in sub], color="tab:blue", label="Tolerable")
        ax.bar(xs, [r[6] for r in sub], bottom=[r[5] for r in sub], color="tab:red", label="Critical")
        ax.set_xticks(xs); ax.set_xticklabels([str(r[2]) for r in sub], fontsize=7)
        for p, name in enumerate(PATTERNS):
            ax.text(p * 6 + 2, -14, name, ha="center", fontsize=8)
        ax.set_title(f"{n}x{n} array"); ax.set_ylim(0, 100)
    axes[0].set_ylabel("Program Vulnerability Factor (%)")
    axes[0].legend(fontsize=8)
    fig.suptitle("LeNet PVF under persistent MxM error patterns (reproduces paper Fig. 5); bars = target layer 1-5")
    fig.tight_layout(); fig.savefig("exp4_lenet_pvf.png", dpi=150)
    print("Saved exp4_lenet_pvf.csv and exp4_lenet_pvf.png")

if __name__ == "__main__":
    main()
