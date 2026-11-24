# DSD Lab 3: MLP Classifier for MNIST

Digital System Design (Projecto de Sistemas Digitais), MEEC 2026/27, lab project 3.
Target: Basys 3 board (Artix-7 xc7a35tcpg236-1), Vivado 2025.2.
Team of three: Isam Abbasi (122334), Simão Gomes Silva (110486), Simão Manuel Miranda Silveira (110049).

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
  classification (again and again, without a reset in between). The 7-segment display shows
  the image number (leftmost digit) and the result (rightmost digit). `LD0` lights when a
  classification is done.
- A testbench that classifies all 16 images, compares `h`, `o` and `result` against the
  software model (`materials/SW-model-2026116.zip`), counts correct classifications and covers extreme
  cases (max/min accumulations, ReLU of negatives, argmax ties).
- A report (11 pages max): datapath and FSM diagrams, FPGA resources, clock period and max
  frequency, latency per image, MAC/s and images/s, critical path. Open resources we did not
  write (course memories, SW model, memory generator) must be referenced in the report.

## Files

Course materials, as given, are in `materials/`:

- `lab3-psd26s1-20261116.pdf`: assignment (latest version; `lab3-psd26s1-20271107.pdf` is an
  older draft that still describes 10 images)
- `IMem.vhd`, `WMem0.vhd`, `WMem1.vhd`: memories from the course page
- `SW-model-2026116.zip`: Python reference model, the 16 test images and the weights

Planned layout of our own files (same conventions as Lab 2):

```
src/       VHDL of the design (one entity per file)
sim/       testbenches, wave configs, generated expected-value packages
scripts/   Python tools (memory generator, expected values) and Vivado Tcl
board/     Basys 3 top level and constraints (.xdc)
report/    LaTeX source, figures
```

## Starting point: what we reuse from Lab 2 (version B)

Lab 2 version B (`datapath.vhd`, `control.vhd`) already solves the same kind of problem on a
smaller scale, so the new design should be a wider version of it, not a new idea:

| Lab 2 version B | Reuse in Lab 3 |
|---|---|
| Datapath: 2 multipliers, `r1`/`r2` product registers, `r3` pair sum, 22-bit `acc`, ReLU on `acc(21)` | Same pipeline, but with up to 112 lanes (see below); `acc` stays 22 bits |
| `first` signal: `acc_op = 0` when a new row starts | Same trick, so the accumulator needs no separate clear |
| Control: small FSM (`S_IDLE`, `S_RUN`, `S_DRAIN`, `S_DONE`) plus counters (`ph`, `wcnt`, `ocnt`) outside the FSM | Same structure; counters now run over WM0 rows (0..895) |
| Flags `v`, `f`, `l` that travel in a flip-flop chain next to the data | Same; they generate `hValid`, `first`, and the layer-1 write time |
| Address is advanced one cycle before its data is needed, hiding the synchronous BRAM read | Same, for IM, WM0 and WM1 |

What is new in Lab 3: pixels are 4 bits unsigned (not 8-bit signed), 112 operands arrive per read
instead of 4, there is a layer 1, an argmax, a `start`/`img` interface, and a board top level.

## Proposed architecture

```
 IM --(112 pixels)--+                           +--> hValid/hAddr/hOut (to testbench)
                    v                           |
 WM0 -(112 weights)-> [ Layer-0 engine ] -- h[m] +--> [ Layer-1 unit ] -- o[0..9] --> [ argmax ] --> result
                          ^   (A)                          ^  (B)                      (B)
                          |                                |
                          +-------- FSM + counters (B) ----+-- WM1 (10 weights, column m)
```

**Bit widths** (worst cases, computed from the formats; re-check with a script before fixing the VHDL):

| Value | Range | Bits |
|---|---|---|
| Product pixel x w0 | -1920 .. 1905 | 12, signed |
| Sum of the 112 products of one row | -215 040 .. 213 360 | 19, signed |
| `acc` (784 products) | -1 505 280 .. 1 493 520 | 22, signed |
| `h[m]` after ReLU | 0 .. 1 493 520 | 21, unsigned (this is the size of `hOut`) |
| `w1 * h` | -191 170 560 .. 189 677 040 | 29, signed |
| `(w1 * h) >> 5` | -5 974 080 .. 5 927 407 | 24, signed |
| `o[j]` | -764 682 240 .. 758 708 096 | 31, signed |

**Performance ceiling.** One memory row is read per cycle, and each neuron needs 7 rows
(784 / 112). So layer 0 cannot take fewer than `128 x 7 = 896` cycles, whatever the number of
multipliers. Layer 1 (10 products per `h[m]`) fits in the time layer 0 spends on one neuron, so
it is hidden by the overlap. Expect about 900 to 950 cycles per image once the pipeline fill and
the argmax are added (to be measured). The layer-0 engine can be built with a smaller number of lanes (56 lanes = 14 cycles per
neuron, 28 lanes = 28 cycles per neuron) if 112 multipliers do not meet timing or area; the
number of lanes should be a generic.

**Choices to make early (they affect everyone):**

- *Lanes:* 112 (one row per cycle) or fewer. Needs a quick synthesis experiment (member A).
- *Pipelining:* a 7-level adder tree of 12 to 19 bits will not fit in 10 ns after a LUT multiplier.
  Lab 2 already needed 9.78 ns for BRAM, multiplexer and one 8x8 multiplier. Register the
  products first, then every 2 or 3 tree levels.
- *Layer 1 multipliers:* 10 in parallel (one per output, each 8 bits x 21 bits, one DSP48E1 each,
  90 are available), because WM1 delivers all 10 weights in one read. Alternative: 2 shared multipliers.
- *`h` storage:* not needed. Each `h[m]` is consumed by layer 1 as soon as it is produced, so only
  the 10 `o` accumulators (10 x 31 bits, registers) are kept. `h[m]` is also sent to `hOut` for the testbench.
- *Argmax:* sequential (one comparator, 9 cycles, strict `>` so the first maximum wins ties) or a
  small pipelined tree (fewer cycles, more LUTs). Cost is a few cycles out of about 900.
- **Division by 32:** the assignment writes `(w1*h)/32` on each product, which in C truncates
  toward zero, but the Python model defaults to `shift` (`>> 5`, rounds toward minus infinity).
  They give different `o` values for negative products. The testbench compares `o`, so we must
  confirm which mode the course testbench uses (model option `shift`, `trunc` or `sum`) before
  writing the layer-1 unit. `shift` is the cheapest in hardware.

## Work division

Three tracks with clear interfaces, so that everybody can work in parallel. Fill in the owner column.

| Track | Owner | What |
|---|---|---|
| **A. Layer-0 engine** | ____ | Entity `l0_engine`: address counters for IM and WM0, lane multipliers, adder tree, `acc`, ReLU, flag chain, outputs `hValid`, `hAddr`, `hOut`. Reuses Lab 2 B. |
| **B. Layer 1, argmax and the MLP top** | ____ | Entities `l1_unit`, `argmax` and `mlp`: WM1 addressing, 10 multiply-shift-accumulate units, argmax, the FSM (`start`, `img`, `done`, `result`, restart without reset), and the integration of A's engine. |
| **C. Verification, board and tools** | ____ | Memory generator with extreme-case sets, testbench, expected-value packages from the SW model, board top (debounce, 7-segment, XDC), Vivado Tcl, post-implementation timing simulation, hardware demo. |

### Track A: layer-0 engine

- Write `l0_engine` with a `LANES` generic. Datapath and control stay separate entities, as the assignment requires.
- Row counter 0..895 for WM0 (a counter, no multiplier for `7*m`), IM address `8*img + r` with `r = 0..6`.
- Run synthesis for 28, 56 and 112 lanes and report LUT, DSP and the worst setup slack, so the team can pick the final value.
- Unit testbench: three neurons with known results, including negative `acc` and the extremes
  (all pixels 15 with all weights -128, and with all weights 127).
- Handover to B: `hValid`, `hAddr`, `hOut` (see the interface contract).

### Track B: layer 1, argmax, top

- `l1_unit`: reads WM1 row `m`, multiplies by `h[m]`, applies the division mode decided above, accumulates into 10 registers. The `o` registers are cleared at the start of each image.
- `argmax`: compares `o[0..9]`, first maximum wins; unit testbench with ties and with all-negative `o`.
- `mlp` top and FSM: `IDLE`, `RUN`, `DRAIN`, `ARGMAX`, `DONE` (to be refined). `start` while running is ignored; a new `start` after `done` runs again without reset. `img` is captured at `start`.
- Integrates A's engine and C's testbench early, with a one-lane version if A is not ready.

### Track C: verification, board, tools

- `scripts/`: extend the course memory generator (or write a small one) to create sets with extreme cases: maximum accumulation, minimum accumulation, negative `acc` (ReLU gives 0), ties in the argmax, `o` at its extremes.
- Python script that runs the SW model on every image and writes `h`, `o` and `result` into a VHDL package for the testbench (the same approach used in Lab 2).
- Testbench `mlp_tb`: classifies the 16 images, checks `h` on every `hValid`, `o` and `result`, counts correct classifications, prints the latency in cycles and ns, and tests a second `start` without reset and a reset in the middle of a run.
- Board top: synchronise and debounce `BTNC` and `BTNU`, one-cycle `start` pulse, multiplexed 7-segment display driven by a counter enable (not a divided clock: the assignment asks for one global clock), `LD0 = done`, the `.xdc` (reuse the Lab 2 clock constraint).
- Runs the Vivado flow: utilization, timing summary, power, post-implementation timing simulation, bitstream, and the demo checklist with all 16 images.

### Shared work

- **Day 1 (all three):** agree the interface contract below, the bit widths, the division mode and the repository layout. Nobody codes before this.
- **Integration (all three):** behavioural simulation of the full design, then fixing timing.
- **Report (11 pages):** each owner writes the section for their track (A: layer-0 datapath and critical path; B: FSM, layer 1, argmax; C: verification, resources, power, demo), plus references to the course materials. One person (C) assembles the LaTeX and checks the page limit. Reuse the Lab 2 template and TikZ styles.

### Interface contract (to confirm on day 1)

| Signal | From -> to | Meaning |
|---|---|---|
| `start` (1 cycle), `img(3:0)` | B -> A | Begin layer 0 for this image |
| `hValid` (1 cycle per neuron) | A -> B, testbench | `h[m]` is ready |
| `hAddr(6:0)`, `hOut(20:0)` | A -> B, testbench | `m` and `h[m]` (unsigned), valid with `hValid` |
| `hPre`, `hPreAddr(6:0)` | A -> B | Same as `hValid`/`hAddr` but one cycle earlier, so B can present WM1 address `m` in time for the synchronous read |
| `l0Done` | A -> B | Last `h` (m = 127) has been sent |
| `o(0..9)`, `oValid` | B (`l1_unit`) -> B (`argmax`) | Final `o` values, 31 bits signed each |
| `done`, `result(3:0)` | B -> board, testbench | Classification complete |

Timing rule: every memory address is generated one cycle before the data is used (as in Lab 2),
and every unit documents its latency in cycles in a comment at the top of the file.

## Plan and milestones

No dates are fixed here; fill in the deadlines from the course schedule.

| Phase | Goal | Done when |
|---|---|---|
| 0. Kick-off | Interface contract, widths, division mode, repository | This README is updated and everyone agrees |
| 1. Blocks | A, B and C finish their entities and unit testbenches | Each unit testbench passes in behavioural simulation |
| 2. Integration | `mlp` runs one image end to end | One image matches the SW model for `h`, `o`, `result` |
| 3. Verification | All 16 images and the extreme sets pass | `mlp_tb` reports 16 of 16 and all extreme cases correct |
| 4. Implementation | Timing met at the chosen clock, post-implementation timing simulation passes | Timing summary with WNS >= 0 and hold met; no latches or gated clocks; no strange warnings |
| 5. Board | Demo on the Basys 3 for all 16 images | Checklist signed by all three |
| 6. Report | 11 pages, all required numbers | Latency, MAC/s, images/s, resources, critical path, references |

## Risks and open questions

- **Division mode** (see above): must be settled before writing the layer-1 unit.
- **Number of images:** the assignment says 16; the header of the given `WMem0.vhd` lists only `mnist_input0.pgm` to `mnist_input8.pgm`
  in its command line. Check that `IMem.vhd` really contains 16 images and what the board test should use.
- **Timing:** Lab 2's critical path was BRAM, multiplexer and a LUT multiplier at 9.78 ns. With 112 lanes the tree and the BRAM fan-out are bigger, so plan for registers after the products from the start.
- **Area:** 112 LUT multipliers plus the tree should fit in 20 800 LUTs, but measure it early (phase 1) before committing.
- **Vivado surprises seen in Lab 2:** Vivado may map multipliers to LUTs instead of DSPs, insert replica registers, and add enable-gating cells inside the BRAM macros. Explain such items in the report instead of leaving them as unexplained warnings.
- **Restart without reset:** every counter, flag and `o` register must return to its initial value when a new `start` arrives; test this explicitly.
