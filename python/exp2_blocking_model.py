"""
Experiment 2 - Light ABFT overhead vs block size (paper Section 6.2, Eq. 9-15, Figs 9-10)

Hardening cost of one BxB block (paper Table 3, square case, comparison = 1 op):
    Light ABFT : H(B) = (3B^2 + B + 1) ADD + B MUL        -> H(4) = 53 ADD + 4 MUL (paper example)
    Traditional: H(B) = (6B^2 + 3B) ADD + (2B^2 + B) MUL   (for comparison)
Failure-free execution cost (Eq. 14):
    F(M,B,R) = ((M/B)^3 + 1/R) * (B^3 + H(B))
Arithmetic overhead = F / M^3 - 1   (plotted in %, like Figs 9 and 10)

Run:  python exp2_blocking_model.py
Creates exp2_fig9_M256.png, exp2_fig10_M4096.png, exp2_blocking.csv
"""
import csv
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

def h_light(b): return (3*b*b + b + 1) + b
def h_trad(b):  return (6*b*b + 3*b) + (2*b*b + b)

def overhead(M, B, R, h):
    F = ((M / B) ** 3 + 1.0 / R) * (B ** 3 + h(B))
    return 100.0 * (F / M ** 3 - 1.0)

assert h_light(4) == 53 + 4 and h_light(2) == 15 + 2, "Table 3 check failed"

R_values = [1, 10, 100, 1000]
rows = []
for M, fname, fig in [(256, "exp2_fig9_M256.png", "Fig. 9"), (4096, "exp2_fig10_M4096.png", "Fig. 10")]:
    Bs = [2 ** p for p in range(0, M.bit_length())]
    plt.figure(figsize=(7, 4.5))
    for R, col in zip(R_values, ["red", "green", "blue", "black"]):
        ys = [overhead(M, B, R, h_light) for B in Bs]
        plt.plot(range(len(Bs)), ys, "o-", color=col, label=f"Light ABFT, R={R}")
        best = min(range(len(Bs)), key=lambda n: ys[n])
        print(f"M={M:5d} R={R:5d}: best block B={Bs[best]:5d}, overhead={ys[best]:.3f} %")
        for B, y in zip(Bs, ys):
            rows.append([M, R, B, f"{y:.5f}", f"{overhead(M, B, R, h_trad):.5f}"])
    yt = [overhead(M, B, 1000, h_trad) for B in Bs]
    plt.plot(range(len(Bs)), yt, "x--", color="gray", label="Traditional ABFT, R=1000")
    plt.yscale("log")
    plt.xticks(range(len(Bs)), [f"$2^{{{p}}}$" for p in range(len(Bs))])
    plt.xlabel("Block size (B)"); plt.ylabel("Arithmetic overhead (%)")
    plt.title(f"Light ABFT overhead, M={M} (reproduces paper {fig})")
    plt.grid(True, which="both", alpha=0.3); plt.legend(fontsize=8)
    plt.tight_layout(); plt.savefig(fname, dpi=150); plt.close()

with open("exp2_blocking.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["M", "R", "B", "light_overhead_percent", "traditional_overhead_percent"])
    w.writerows(rows)
print("Saved exp2_fig9_M256.png, exp2_fig10_M4096.png and exp2_blocking.csv")
