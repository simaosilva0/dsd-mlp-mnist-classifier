# DSD Lab 3: MLP Classifier for MNIST

Digital System Design (Projecto de Sistemas Digitais), MEEC 2026/27, lab project 3.
Target: Basys 3 board (Artix-7 xc7a35tcpg236-1), Vivado 2025.2.

## The problem

Classify a handwritten digit (0 to 9) from the MNIST dataset in hardware, using a small
two-layer multilayer perceptron (MLP):

```
Input (28x28 = 784 pixels) -> layer 0: 128 neurons, ReLU -> layer 1: 10 outputs -> argmax
```

```
h[m]   = ReLU( sum_{k=0..783} w0[m][k] * Input[k] )      m = 0..127   (layer 0)
o[j]   = sum_{m=0..127} (w1[j][m] * h[m]) / 32            j = 0..9     (layer 1)
result = argmax(o[0..9])                                   first maximum wins a tie
```

Data formats:

| Data | Size | Format |
|---|---|---|
| Pixels `Input` | 784 | 4-bit unsigned (0..15) |
| Weights `w0` | 128 x 784 | 8-bit two's complement |
| Weights `w1` | 10 x 128 | 8-bit two's complement |
| `h`, `o` | 128, 10 | as many bits as needed for no loss of precision |

The reference algorithm unrolls the layer-0 inner loop by 4 and overlaps the two layers: each
`h[m]` goes into the 10 layer-1 accumulators as soon as it is computed.

## Given memories

All banks of a memory share one address, so a single read returns a whole row.

| Memory | Banks x rows x bits | One read | Row address |
|---|---|---|---|
| `IMem` (IM) | 7 x 128 x 64 | 112 pixels | `8*img + k/112` |
| `WMem0` (WM0) | 28 x 1024 x 32 (896 used) | 112 weights of `w0` | `7*m + k/112` |
| `WMem1` (WM1) | 1 x 128 x 80, distributed RAM | 10 weights, column `m` of `w1` | `m` |

IM holds 16 images (7 rows of pixels and 1 blank row each). How to store `h` and `o` is up to us.

## What we have to build

- An FSMD (FSM controller and datapath as separate entities) that classifies the selected image,
  aiming for the best performance on the FPGA (pipelining, layer overlap).
- MLP interface: inputs `clk`, `reset` (synchronous, active high), `start`, `img` (4 bits);
  outputs `done`, `result` (4 bits), plus `hValid`, `hAddr` (7 bits) and `hOut` so the
  testbench can check each `h[m]`.
- A board top level: `SW3..SW0` select the image, `BTNU` resets, `BTNC` starts a new
  classification. The 7-segment display shows the image number (leftmost digit) and the result
  (rightmost digit). `LD0` lights when a classification is done.
- A testbench that classifies all 16 images, compares `h`, `o` and `result` against the
  software model (`SW-model-2026116.zip`), counts correct classifications and covers extreme
  cases (max/min accumulations, ReLU of negatives, argmax ties).
- A report (11 pages max): datapath and FSM diagrams, FPGA resources, clock period and max
  frequency, latency per image, MAC/s and images/s, critical path.

## Files

- `lab3-psd26s1-20261116.pdf`: assignment (latest version)
- `IMem.vhd`, `WMem0.vhd`, `WMem1.vhd`: memories from the course page
- `SW-model-2026116.zip`: Python reference model, the 16 test images and the weights
