"""
Experiment 3 - Light ABFT arithmetic overhead in real CNNs (paper Section 6.2)

Each convolution is turned into a matrix multiplication with im2col:
    A (i x j) = image patches,  i = H_out * W_out,  j = C_in * K * K
    B (j x k) = filter weights,  k = C_out
Unhardened MxM cost = i*j*k multiplications + i*j*k additions.
Light ABFT cost (paper Table 3, Light ABFT "Total / Algorithmic"):
    ADD = i*k + j*i + j*k + j + 1,   MUL = j
Overhead = Light ABFT ops / MxM ops, summed over all convolutional layers.
Paper reports 0.35 % (VGG16), 0.81 % (ResNet18), 0.71 % (ResNet50).

Run:  python exp3_cnn_overhead.py
"""
import csv

def conv(layers, name, h_out, c_in, c_out, k):
    layers.append((name, h_out * h_out, c_in * k * k, c_out))

def vgg16():
    L, cfg, c_in, h = [], [(64, 2), (128, 2), (256, 3), (512, 3), (512, 3)], 3, 224
    for stage, (c_out, n) in enumerate(cfg):
        for r in range(n):
            conv(L, f"conv{stage+1}_{r+1}", h, c_in, c_out, 3)
            c_in = c_out
        h //= 2
    return L

def resnet18():
    L = []
    conv(L, "conv1", 112, 3, 64, 7)
    h, c_in = 56, 64
    for stage, c_out in enumerate([64, 128, 256, 512]):
        for blk in range(2):
            stride2 = (stage > 0 and blk == 0)
            ho = h // 2 if stride2 else h
            conv(L, f"l{stage+1}.{blk}.conv1", ho, c_in, c_out, 3)
            conv(L, f"l{stage+1}.{blk}.conv2", ho, c_out, c_out, 3)
            if stride2:
                conv(L, f"l{stage+1}.{blk}.down", ho, c_in, c_out, 1)
            c_in, h = c_out, ho
    return L

def resnet50():
    L = []
    conv(L, "conv1", 112, 3, 64, 7)
    h, c_in = 56, 64
    for stage, (mid, n) in enumerate([(64, 3), (128, 4), (256, 6), (512, 3)]):
        out = mid * 4
        for blk in range(n):
            stride2 = (stage > 0 and blk == 0)
            ho = h // 2 if stride2 else h
            conv(L, f"l{stage+1}.{blk}.conv1", h, c_in, mid, 1)   # stride in 3x3 (torchvision v1.5)
            conv(L, f"l{stage+1}.{blk}.conv2", ho, mid, mid, 3)
            conv(L, f"l{stage+1}.{blk}.conv3", ho, mid, out, 1)
            if blk == 0:
                conv(L, f"l{stage+1}.{blk}.down", ho, c_in, out, 1)
            c_in, h = out, ho
    return L

def overhead(layers):
    mxm = abft = 0
    rows = []
    for name, i, j, k in layers:
        m = 2 * i * j * k
        a = (i * k + j * i + j * k + j + 1) + j
        mxm += m; abft += a
        rows.append((name, i, j, k, m, a, 100.0 * a / m))
    return rows, 100.0 * abft / mxm

paper = {"VGG16": 0.35, "ResNet18": 0.81, "ResNet50": 0.71}
with open("exp3_cnn_overhead.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["network", "layer", "i", "j", "k", "mxm_ops", "light_abft_ops", "overhead_percent"])
    print(f"{'Network':10s} {'Conv layers':>11s} {'Our overhead':>13s} {'Paper':>7s}")
    for net, fn in [("VGG16", vgg16), ("ResNet18", resnet18), ("ResNet50", resnet50)]:
        rows, tot = overhead(fn())
        for r in rows:
            w.writerow([net, *r[:6], f"{r[6]:.4f}"])
        print(f"{net:10s} {len(rows):11d} {tot:12.2f} % {paper[net]:6.2f} %")
print("Per-layer details written to exp3_cnn_overhead.csv")
