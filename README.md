# Light ABFT on an FPGA Systolic Array

Reproduction and evaluation of **F. Libano, P. Rech and J. Brunhaver, "Efficient Error Detection for Matrix Multiplication With Systolic Arrays on FPGAs," IEEE Transactions on Computers, vol. 72, no. 8, pp. 2390–2403, 2023** ([DOI: 10.1109/TC.2023.3248282](https://doi.org/10.1109/TC.2023.3248282)), implemented on an **EDGE Artix-7 (XC7A35T-1FTG256)** FPGA board.

**Team:** Naseeb (S20240020315) · S K Dhanvitha (S20240020328)

## The idea in one paragraph

A radiation hit can flip a bit in an FPGA's configuration memory and silently break the circuit until it is reprogrammed. In a systolic array, one broken processing element usually corrupts a whole row or column of the result. **Light ABFT** detects such errors with a single extra multiplier: the sum of all outputs must equal `L = SV_A · SV_B`, a number computed from the column sums of A and the row sums of B. If they differ, an error occurred.

## Main results

| Metric | Ours | Paper |
|---|---|---|
| Light ABFT detection rate | **100%** (7,329 corrupted runs) | 97.4% |
| False detections | 8.60% (2.89% excluding checker faults) | 2.39% |
| Line errors (partial + full) | 95.4% | 70.0% |
| Checker cost, 4×4 (LUTs / FFs / DSPs) | Light 62 / 86 / 1 vs Traditional 382 / 254 / 11 | 1 vs 2N+1 multipliers |
| CNN overhead VGG16 / ResNet18 / ResNet50 | 0.36% / 0.78% / 0.69% | 0.35% / 0.81% / 0.71% |
| Timing / power (board design) | Met at 50 MHz (≈87 MHz max), 0.089 W | – |

The full report with every graph and comparison is in [`docs/Light_ABFT_Project_Report.pdf`](docs/Light_ABFT_Project_Report.pdf).

## Repository layout

```
rtl/board/      4x4 board design: pe.v, systolic_4x4.v, light_abft.v, trad_abft.v, abft_core.v, top.v
rtl/scaling/    N x N version + tb_scale.v, scale_ooc.xdc, run_scaling.tcl (Experiment 5)
sim/            tb_top.v (functional test), tb_campaign.v (fault campaign, Experiment 1)
constraints/    edge_artix7.xdc (EDGE Artix-7 pins, 50 MHz clock)
python/         exp2_blocking_model.py, exp3_cnn_overhead.py, exp4_lenet_pvf.py, requirements.txt
results/        CSV data, figures, Vivado screenshots, board photo
docs/           project report (PDF), video script
```

## How to reproduce

### 1. Board design (Vivado 2024.2)
1. Create an RTL project for part **xc7a35tftg256-1**.
2. Add `rtl/board/*.v` as design sources (top = `top`), `sim/*.v` as simulation sources, `constraints/edge_artix7.xdc` as constraints.
3. Simulation: set `tb_top` as simulation top → Run Behavioral Simulation → type `run all` → expect `ALL TESTS PASSED`.
4. Run Synthesis → Implementation → Generate Bitstream → Hardware Manager → Program Device.
5. On the board: center button = reset, top button = start, SW0–SW3 = data, SW7 = fault.
   - SW7 down: LED0 + LED1 (done, OK).
   - SW7 up: LED0 + LED2 + LED3 + LED6 (both checkers detect the fault; column 2 is faulty).

### 2. Fault campaign (Experiment 1)
Set `tb_campaign` as simulation top → Run Behavioral Simulation → `run all`. The summary prints in the Tcl Console; every run is saved to `fault_campaign.csv` in `<project>.sim/sim_1/behav/xsim/`.

### 3. Scaling (Experiment 5)
New project with `rtl/scaling/*`. Simulate `tb_scale.v` (edit `parameter N` = 2, 4, 8). Then set `scale_top` as top and run `source run_scaling.tcl` in the Tcl Console.

### 4. Python experiments (2, 3, 4)
```
cd python
python -m pip install -r requirements.txt
python exp2_blocking_model.py
python exp3_cnn_overhead.py
python exp4_lenet_pvf.py        # first run downloads MNIST and trains LeNet
```

## Credits

- Base paper: Libano, Rech and Brunhaver (IEEE TC, 2023). The authors' original generator: https://github.com/lllibano/LABFT (used as a reference; the RTL here was written separately in simplified form).
- Traditional ABFT: K.-H. Huang and J. A. Abraham, IEEE Transactions on Computers, 1984.
