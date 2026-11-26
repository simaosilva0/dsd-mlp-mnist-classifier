# DSD Lab 3: MLP Classifier for MNIST

Digital System Design (Projecto de Sistemas Digitais), MEEC 2026/27, lab project 3.
Target: Basys 3 board (Artix-7 xc7a35tcpg236-1), Vivado 2025.2.
Team of three: Isam Abbasi (122334), Simão Gomes Silva (110486), Simão Manuel Miranda Silveira (110049).

## Start here (2-minute read)

**What we're building.** A circuit on the Basys 3 that looks at a 28x28 picture of a handwritten
digit and says which digit it is (0 to 9). You pick one of 16 stored pictures with the switches,
press the middle button, and the display shows the picture number on the left and the answer on
the right.

**How it works, in plain words.**
1. **Layer 0:** for each of 128 "hidden neurons", multiply all 784 pixels by 784 weights and add
   everything up. If the total is negative, use 0 instead (that's "ReLU"). That gives 128 numbers, `h`.
2. **Layer 1:** for each digit 0..9, multiply the 128 `h` values by 128 weights, divide by 32
   and add them up. That gives 10 scores, `o`.
3. **Answer:** the digit with the biggest score wins (the first one, if there's a tie).

**Why it's fast.** The weight memory hands us 112 weights per clock tick, so we do 112
multiplications at once. One picture takes about 900 ticks, about 9 microseconds.

**What's already decided.** The design is one "brain" file (`control.vhd`, decides *when*
things happen) and one "muscle" file (`datapath.vhd`, does the maths). The professor requires
this split. We start from our Lab 2 code, which already works this way.

**What to do now.**
1. Set up Vivado: see [Setting up the Vivado project](#setting-up-the-vivado-project).
2. Read the [work plan](#work-plan-in-pieces) and put your name on a piece.

**The only open question:** how to "divide by 32" for negative numbers. We ask the professor
(see [Open decisions](#open-decisions)).

Words you don't know (FSMD, BRAM, lane, CDFG, WNS...)? See the [glossary](#glossary) at the end.

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
`h[m]` goes into the 10 layer-1 accumulators as soon as it is computed. The unroll by 4 describes
the algorithm, not a hardware limit: unlike Lab 2, the PDF sets no limit on multipliers, the
memories return 112 values per read, and the second objective is the highest performance. So our
datapath processes a whole memory row (112 products) per cycle. The overlap is kept exactly as in
the pseudocode.

## Given memories

All banks of a memory share one address, so a single read returns a whole row.

| Memory | Banks x rows x bits | One read | Row address |
|---|---|---|---|
| `IMem` (IM) | 7 x 128 x 64 | 112 pixels | `8*img + k/112` |
| `WMem0` (WM0) | 28 x 1024 x 32 (896 used) | 112 weights of `w0` | `7*m + k/112` |
| `WMem1` (WM1) | 1 x 128 x 80, distributed RAM | 10 weights, column `m` of `w1` | `m` |

IM holds 16 images (7 rows of pixels and 1 blank row each). How to store `h` and `o` is up to us.

## What the assignment asks for (checklist, from the Lab 3 PDF)

Priorities, as stated in the PDF: **(1) a functionally correct circuit demonstrated on the board;
(2) the highest performance possible** on the Artix-7 of the Basys 3.

Circuit (PDF, "Circuit Design"):

- [ ] **FSMD**: an FSM controller and a datapath unit, **in separate VHDL entities**, that execute
  the whole algorithm (layer 0, layer 1, argmax) and classify one selected image.
- [ ] Optimise performance by **overlapping layer 0 and layer 1** and/or **pipelining**.
- [ ] All computations in **appropriate representations, without loss of accuracy**. Calculate and
  justify the **minimum number of bits** of products, partial sums and accumulators.
- [ ] **Scheduling** of the operations, with the corresponding **CDFG** drawn.
- [ ] Use **IM, WM0 and WM1 as given**. Decide and **justify how `h` and `o` are stored** (registers or
  memory) and **how argmax() is computed**.
- [ ] MLP interface: inputs `clk`, `reset` (synchronous, active high), `start`, `img` (4 bits);
  outputs `done`, `result` (4 bits); for the testbench, `hValid`, `hAddr` (7 bits), `hOut`
  (width of our choice) for **each new `h[m]`**.
- [ ] One global clock: the 100 MHz board clock, or a **slower** clock derived from it if the
  critical path needs it. All registers positive-edge-triggered.

Board (PDF, Figure 5):

- [ ] A top-level entity connects the MLP to the board. `SW3..SW0` = `img`; `BTNU` = `reset`;
  `BTNC` = `start`. **Each BTNC press runs a new classification of the selected image, with no
  reset in between.**
- [ ] 7-segment display: the selected image on the **leftmost** digit (AN3), `result` on the
  **rightmost** digit (AN0).
- [ ] `LD0` = `done`, lit **only when the classification of an image has been completed**.
- [ ] Demo: each of the 16 images selected with the switches and classified with BTNC, one after
  the other.

Verification (PDF, page 6):

- [ ] A testbench for the MLP circuit that classifies the **16 images**, **compares `h`, `o` and
  `result` with the software model** (`materials/SW-model-2026116/mlp_model.py`) and **reports the
  number of correct classifications**.
- [ ] **Extreme cases**: maximum and minimum accumulations, ReLU of negative values, ties in
  argmax(), etc.
- [ ] Performance evaluated with **Post-Implementation Timing Simulation**.
- [ ] Circuit mapped to the FPGA and tested on the board.

Report (11 pages max, readable font):

- [ ] Block diagram of the architecture and of the datapath, with the **number and size of
  registers, multiplexers and operators**.
- [ ] FSM state diagram; CDFG and schedule.
- [ ] FPGA resources used; clock period used and maximum operating frequency.
- [ ] Performance in **MAC/s and images/s**; **latency of one image**; the **critical path**.
- [ ] Every open resource we did not fully write (course memories, SW model, memory generator,
  Lab 2 base, any board/display code) acknowledged and referenced.

## Files

Course materials, as given, are in `materials/`:

- `lab3-psd26s1-20261116.pdf`: assignment (latest version; `lab3-psd26s1-20271107.pdf` is an
  older draft that still describes 10 images)
- `IMem.vhd`, `WMem0.vhd`, `WMem1.vhd`: memories from the course page
- `SW-model-2026116/`: Python reference model (`mlp_model.py`), the 16 test images (`.pgm`) and the
  weights (`w0.txt`, `w1.txt`)
- Not in the repo yet: the course memory generator `gen_mem.py` (named in the headers of the memory
  files). Piece 3 needs it, from the course page, to generate the extreme-case memories.

Current state: `src/` (`circuito`, `control`, `datapath`) and `sim/circuito_tb.vhd` are the
Lab 2 version B files, copied as the starting point; piece 1 rewrites them (`circuito` becomes
`mlp`, `circuito_tb` becomes `mlp_tb`). `board/basys3.xdc`
has the Basys 3 pins for the board top (clock, BTNU, BTNC, SW3..SW0, LD0, 7-segment display).
Create the Vivado project by hand in `vivado/` (ignored by git); do not
commit Vivado project files.

Planned layout of our own files (same conventions as Lab 2):

```
src/       VHDL of the design (one entity per file)
sim/       testbenches, wave configs, generated expected-value packages
scripts/   Python tools (expected values, extreme-case memories)
board/     Basys 3 top level and constraints (.xdc)
report/    LaTeX source, figures
```

## Setting up the Vivado project

The Vivado project is not in git: each of us creates it once, locally, linked to the repo files.
Vivado 2025.2.

1. **Create Project** → Next. Name `project_lab3`, location `<repo>/vivado` (this folder is
   ignored by git). RTL Project, tick *Do not specify sources at this time*.
   Part: `xc7a35tcpg236-1`. Finish.
2. **Add Sources → design sources → Add Files:** everything in `src/`, plus
   `materials/IMem.vhd`, `materials/WMem0.vhd`, `materials/WMem1.vhd`.
   **Untick "Copy sources into project"**, so that edits go to the files git tracks.
3. **Add Sources → simulation sources:** the testbench(es) in `sim/`, copy unticked.
4. **Add Sources → constraints:** `board/basys3.xdc`, copy unticked. Only enable it when the board
   top is the top module (right-click → Disable File while simulating or synthesising `mlp` alone).
5. **Set as Top:** `mlp` (or the board top for the bitstream); simulation top: the testbench.
   Simulation run time: about 200 us for the 16 images.
6. After `git pull`, new files in `src/` or `sim/` must be added to the project by hand
   (Add Sources again); edited files are picked up automatically.

Note: until the Lab 2 files are rewritten, `circuito.vhd` still refers to the Lab 2 memories
(`IMemB`, `WMemA`, `OMemC`) and `circuito_tb.vhd` to `mem_data_pkg`, so Vivado will show them as
missing. That is expected.

## Starting point: what we reuse from Lab 2 (version B)

Lab 2 version B (`src/datapath.vhd`, `src/control.vhd`, `src/circuito.vhd`, `sim/circuito_tb.vhd`)
already solves the same kind of problem on a smaller scale. Lab 3 is a wider version of it, with
the same FSMD split:

| Lab 2 version B | In Lab 3 |
|---|---|
| `control`: one small FSM (`S_IDLE`, `S_RUN`, `S_DRAIN`, `S_DONE`) plus counters outside the FSM | Still **the only** controller. The counters now walk the 896 WM0 rows, the 7 rows of each neuron and the argmax |
| `datapath`: products, pair sum, 22-bit `acc`, ReLU on `acc(21)` | Same pipeline with 112 lanes and an adder tree, plus layer 1, the `o` registers and the argmax; `acc` stays 22 bits |
| `first`: `acc_op = 0` when a new row starts | Same trick: the accumulator needs no clear state between neurons |
| Flags `v`, `f`, `l` shifted next to the data | Same; they produce `hValid`/`hAddr`, `first`, the layer-1 update and the end of the run |
| Address one cycle before its data is needed (synchronous BRAM read) | Same, for IM, WM0 and WM1 |
| `circuito`: wires control, datapath and memories | Becomes `mlp` with the PDF's ports |
| `circuito_tb`: compares against a generated package | Becomes `mlp_tb`, same pattern, with `h`, `o` and `result` |

New in Lab 3: 4-bit unsigned pixels (Lab 2: 8-bit signed), 112 operands per read (Lab 2: 4),
layer 1, argmax, the `start`/`img`/`done` interface with restart, and the board top level.

## Architecture (FSMD)

### Entities

The PDF asks for **one FSM controller and one datapath unit in separate entities**. All control
decisions are in `control`; `datapath` has no FSM, only registers and operators driven by
`control`. Large datapath blocks (lanes, adder tree, layer-1 MACs, argmax) may be separate entities
*instantiated inside* `datapath`; it is still one datapath unit.

```
board_top            (board/board_top.vhd)  debounce BTNU/BTNC, 1-cycle start pulse, 7-segment, LD0
 └─ mlp              (src/mlp.vhd)          ports exactly as the PDF; wiring only
     ├─ control      (src/control.vhd)      the FSM, counters, flag chain: addresses, enables,
     │                                      hValid, hAddr, done
     ├─ datapath     (src/datapath.vhd)     layer 0: 112 multipliers, adder tree, acc, ReLU, h register (hOut)
     │                                      layer 1: 10 x (w1 * h >> 5) + o[j]
     │                                      argmax:  result register
     ├─ IMem         (materials/, as given) 112 pixels per read,  address 8*img + r = img & r(2:0)
     ├─ WMem0        (materials/, as given) 112 weights per read, address 7*m + r (a counter 0..895)
     └─ WMem1        (materials/, as given) 10 weights per read,  address m
```

`mlp` ports (PDF): `clk`, `reset` (sync, active high), `start`, `img(3:0)` in; `done`,
`result(3:0)`, `hValid`, `hAddr(6:0)`, `hOut(20:0)` out.

### Schedule (what the CDFG and the timing diagram in the report show)

- **Layer 0, one WM0 row per cycle.** Each cycle, `control` presents IM row `img & r` and WM0 row
  `7*m + r` (`r = 0..6`). One cycle later the 112 pixels and 112 weights reach the datapath: 112
  products → adder tree → row sum (19 bits) → `acc` (22 bits). The 7 row sums of a neuron go into
  `acc`; `first` restarts it at `r = 0`.
- **ReLU and `h[m]`.** When the 7th row sum of neuron `m` is in `acc`, ReLU loads the `h` register
  (21 bits), and `control` pulses `hValid` with `hAddr = m`. At the same edge `acc` starts neuron
  `m+1` (no lost cycle, as in Lab 2).
- **Layer 1, overlapped with layer 0** (the overlap the PDF asks for). WM1 row `m` is read one
  cycle before `h[m]` is ready. Then the 10 products `w1[j][m] * h[m]` are formed in parallel,
  shifted by 5 (division mode, see below) and added into `o[j]`, while layer 0 is already
  computing neuron `m+1`. Layer 1 needs 1 to 2 cycles per neuron; a neuron takes 7, so layer 1
  never stalls layer 0.
- **Argmax.** After the last `o` update (`h[127]`), a sequential scan of `o[1..9]` against the
  current maximum, strict `>`, so the first maximum wins a tie (9 cycles). Then `result` is
  registered and `done` = 1.
- **FSM:** `IDLE → RUN → DRAIN → ARGMAX → DONE`. `start` in `IDLE` or `DONE` latches `img`, clears
  `o` and `done`, and enters `RUN`; `start` during a run is ignored. `RUN` lasts 896 cycles (one row
  per cycle); `DRAIN` waits for the pipeline and the last layer-1 update.

### Number representation (minimum bits, no loss of precision)

| Value | Range | Bits |
|---|---|---|
| Pixel `Input[k]` | 0 .. 15 | 4, unsigned (zero-extended to 5 bits signed before multiplying) |
| Weights `w0`, `w1` | -128 .. 127 | 8, signed |
| Product pixel x w0 | -1920 .. 1905 | 12, signed |
| Sum of the 112 products of one row | -215 040 .. 213 360 | 19, signed |
| `acc` (784 products) | -1 505 280 .. 1 493 520 | 22, signed |
| `h[m]` after ReLU | 0 .. 1 493 520 | 21, unsigned (= `hOut`) |
| `w1 * h` | -191 170 560 .. 189 677 040 | 29, signed |
| `(w1 * h) >> 5` | -5 974 080 .. 5 927 407 | 24, signed |
| `o[j]` (128 terms) | -764 682 240 .. 758 708 096 | 31, signed |

Intermediate levels of the adder tree grow by 1 bit per level: 12, 13, 14, 15, 16, 17, 18 → 19.

### Storage and argmax (the decisions the PDF asks us to justify)

- **`h`: one 21-bit register, no memory.** Each `h[m]` is used by layer 1 right after it is
  produced and is never needed again, and the next one arrives 7 cycles later. It also drives
  `hOut`.
- **`o`: ten 31-bit registers (310 FFs), no memory.** All ten are updated in the same cycle, which
  a single-port memory could not do; they are cleared on each accepted `start`.
- **Argmax: sequential, one comparator, 9 cycles.** Costs 9 of about 910 cycles (1 %), with one
  31-bit comparator and a 10:1 mux on registers that already exist. A comparator tree would save
  about 5 cycles for 9 comparators; if we use one, each comparator must keep the lower index on
  equality.

### Performance target

- WM0 gives one row per cycle and an image needs 896 rows, so **896 cycles is the floor** for
  any number of multipliers. With pipeline fill, the last layer-1 update and the argmax: about
  **910 cycles**.
- The PDF allows 100 MHz or a slower clock, never faster: target **10 ns → about 9.1 us per
  image, about 110 000 images/s**.
- Work per image: 128 x 784 + 10 x 128 = **101 632 MAC**, so about **11 GMAC/s** at 910 cycles and 10 ns.
- If 112 lanes miss timing or area, fall back to 56 lanes (14 cycles per neuron, about 1 800
  cycles); `LANES` is a generic.

### Open decisions

- **Division by 32 (ask the professor first).** The PDF writes `(w1*h)/32` per product (C:
  truncation toward zero); the Python model defaults to `shift` (`>> 5`, toward minus infinity).
  They give different `o` for negative products, and the testbench compares `o`. Until there is
  an answer we use `shift`, the model default and the cheapest (drop 5 bits); `trunc` adds 31 to
  negative products before the shift. `sum` (one `>> 5` at the end, 36-bit accumulator) is exact
  but not the per-product formula in the PDF.
- **Pipeline depth of layer 0** (register after the products, then every 2 or 3 tree levels; a
  register on the memory data if needed). Fixed by the timing results of piece 5. Each stage costs
  1 cycle out of about 910.
- **Layer-1 multipliers:** 10 in parallel (one DSP48E1 each, 90 available) by default; 2 shared
  would also fit in 7 cycles but needs a mux and a sequencer.

## Work plan, in pieces

Each piece is small, ends with something we can simulate in Vivado, and maps to items of the PDF
checklist above. Do them in order; pieces 4 and 6 can run in parallel with the others.

| # | Piece | Owner | Target date |
|---|---|---|---|
| 0 | Expected values from the SW model (done: memories match the model; model gets 14/16, images 2 and 7 wrong) | Isam | 26-11 |
| 1 | Layer 0: `control` + `datapath` + `mlp`, checks every `h[m]` | ____ | 03-12 |
| 2 | Layer 1, argmax, `done`/`result`: all 16 images | ____ | 07-12 |
| 3 | Restart and extreme cases | ____ | 10-12 |
| 4 | Board top and demo | ____ | 12-12 |
| 5 | Implementation, timing, post-implementation timing simulation | ____ | 14-12 |
| 6 | Report | all | 23-12 |

### Piece 0: expected values

> **In short:** a Python script that writes down the correct answers (`h`, `o`, digit) for all 16 pictures, so the testbench can check our circuit against them. Small and easy: a good first task.

- `scripts/gen_expected.py` uses the course model's own functions
  (`materials/SW-model-2026116/mlp_model.py`), runs it on the 16 images and writes
  `sim/mlp_expected_pkg.vhd` with `H_EXP(img)(m)`, `O_EXP(img)(j)`, `RESULT_EXP(img)` and
  `TRUE_DIGIT(img)`.
- It first checks that `IMem.vhd`, `WMem0.vhd` and `WMem1.vhd` hold the same images and weights
  as the model's files, in the order the PDF describes. If they don't, it stops and says where.
- It prints a table per image (predicted digit, true digit, accumulator range, how many `h` are 0,
  `o` range, argmax ties) and the 16 images as ASCII art.
- **Run it** (needs Python 3 with numpy), from the repo root:
  ```
  python scripts/gen_expected.py              # division mode 'shift' (the model's default)
  python scripts/gen_expected.py --mode trunc # if the professor says so ('trunc' or 'sum')
  ```
- **True digits:** the `.pgm` files have no labels, so the script has a `TRUE_DIGIT` list read
  by eye: `6 9 7 2 9 4 4 2 7 0 1 3 5 8 0 6` for images 0..15. Check them against the ASCII art. The
  testbench will report both "matches the model" (circuit correct) and "matches the true digit"
  (the PDF's "number of correct classifications").
- Done when: the script says the memories match, and `H_EXP(0)`, `O_EXP(0)`, `RESULT_EXP(0)` (and image 5)
  are the same as the output of
  `python materials/SW-model-2026116/mlp_model.py materials/SW-model-2026116/mnist_input0.pgm materials/SW-model-2026116/w0.txt materials/SW-model-2026116/w1.txt`.
  The generated package is committed, so nobody else needs Python.
- PDF: "compares h, o and result with a software model ... and reports the number of correct
  classifications".

### Piece 1: layer 0

> **In short:** the big one. Make the circuit compute the 128 `h` values and prove every one is right in simulation. Everything else builds on this.

- Rewrite `src/control.vhd` (FSM `IDLE/RUN/DRAIN/DONE` for now, row counter 0..895, `r`, `m`,
  flag chain, `hValid`/`hAddr`), `src/datapath.vhd` (112 lanes, adder tree, `acc`, ReLU, `h`
  register) and `src/mlp.vhd` (replaces `circuito.vhd`; memories from `materials/`).
- `sim/mlp_tb.vhd` (from `circuito_tb.vhd`): one `start` on image 0, checks every `h[m]` on
  `hValid` against piece 0, and the order of `hAddr`; then all 16 images.
- First synthesis: LUT/DSP use and timing for 112 lanes, to confirm the lane count early.
- Done when: all 128 `h` of all 16 images match.
- PDF: FSMD, number representation, layer 0, `hValid`/`hAddr`/`hOut`.

### Piece 2: layer 1, argmax, done/result

> **In short:** add the 10 scores and pick the winning digit. Done when the simulation says 16 of 16 pictures are correct.

- Datapath: WM1 data, 10 multiply-shift-accumulate, `o` registers, argmax, `result` register.
  Control: WM1 address, layer-1 update flag, `ARGMAX` state, `done`.
- `mlp_tb`: checks `o[0..9]` and `result` for the 16 images and prints the number of correct
  classifications and the latency in cycles.
- Done when: 16/16 `h`, `o` and `result` match.
- PDF: overlap of layers, `h`/`o` storage, argmax, testbench report.

### Piece 3: restart and extreme cases

> **In short:** try to break it: press start twice, reset in the middle, use huge or negative numbers, make two digits tie. The professor explicitly asks for these tests.

- Testbench: a second `start` without reset (same and different `img`), `start` during a run
  (ignored), `reset` in the middle of a run, `done` low while running.
- Extreme memory sets (needs `gen_mem.py` from the course page): maximum accumulation (pixels 15,
  weights 127), minimum (pixels 15, weights -128) → ReLU of negatives, ties in argmax, `o` at its
  extremes. Expected values from piece 0's script.
- Done when: all sets pass.
- PDF: "extreme cases", "each time BTNC is pressed ... without the need for a reset".

### Piece 4: board top

> **In short:** the part you can touch: buttons, switches, the display and the LED. Can be done in parallel by someone not working on pieces 1 and 2.

- `board/board_top.vhd`: synchronise and debounce BTNU and BTNC, one-cycle `start` pulse on each
  BTNC press, 7-segment multiplexing with a counter enable (no divided clock: one global clock),
  `img` on AN3, `result` on AN0, `LD0 = done`. Constraints in `board/basys3.xdc`.
- Can be written in parallel, against the `mlp` ports.
- Done when: the 16 images classify correctly on the board, one after the other.
- PDF: board interface, demonstration.

### Piece 5: implementation and timing

> **In short:** make sure the real chip is fast enough at 100 MHz, and measure the numbers the report needs.

- Implementation at 10 ns: WNS/WHS, critical path, resources (LUT, FF, DSP, BRAM). If timing fails,
  add pipeline registers in layer 0 (or, last resort, a slower derived clock).
- Post-implementation timing simulation of `mlp_tb` with all 16 images.
- Done when: timing met, the timing simulation passes, and the numbers for the report are
  recorded (clock period, Fmax, latency, MAC/s, images/s, critical path, resources).
- PDF: performance, timing simulation, FPGA resources.

### Piece 6: report (11 pages)

> **In short:** write it up. Max 11 pages. Everyone writes the part they built.

- Architecture and datapath block diagrams with the number and size of registers, muxes and
  operators; FSM state diagram; CDFG and schedule; number representation; `h`/`o`/argmax
  justification; verification; resources; clock and Fmax; latency, MAC/s, images/s; critical
  path; references (course memories, SW model, memory generator, Lab 2, any borrowed code).
- Diagrams can start as soon as piece 1 is done.

### Interface between `control` and `datapath`

To be fixed in piece 1 and kept up to date here:

| Signal | Direction | Meaning |
|---|---|---|
| `ld_p`, `ld_t`, `ld_acc` | control → datapath | stage enables of layer 0 (valid flags) |
| `first` | control → datapath | `acc ← row sum` (new neuron) instead of `acc + row sum` |
| `ld_h` | control → datapath | load the `h` register with ReLU(`acc`) |
| `ld_o`, `clr_o` | control → datapath | add the 10 layer-1 terms into `o`; clear `o` on `start` |
| `amax_first`, `amax_step`, `amax_sel(3:0)` | control → datapath | argmax scan |
| `ld_result` | control → datapath | register the argmax index |

Rule: every memory address is generated one cycle before its data is used, and each entity
documents its latency in cycles in a comment at the top.

## Deadlines

- Testing lab (board demo): **17-12-2026 16:00**
- Report delivery: **23-12-2026 23:59**

## Risks

- **Division mode**: settle it with the professor before piece 2.
- **Timing**: 112 lanes means a 7-level adder tree and wide fan-out from 35 BRAMs. The given
  BRAMs have no output register (about 2.5 ns clock-to-out), so plan the registers after the
  products from the start.
- **Area**: 112 LUT multipliers (4 x 8 bits) plus the tree should fit in 20 800 LUTs; measure in
  piece 1.
- **Vivado surprises seen in Lab 2**: multipliers mapped to LUTs instead of DSPs, replica
  registers, enable-gating cells inside the BRAM macros. Explain them in the report instead of
  leaving unexplained warnings.
- **Restart without reset**: every counter, flag and `o` register must return to its initial
  value on a new `start`; piece 3 tests it.

## Glossary

| Word | Meaning |
|---|---|
| **FSMD** | "Finite State Machine with Datapath": the design is split into a controller (the FSM, decides *when*) and a datapath (does the maths). |
| **FSM** | A circuit that is always in one "state" (IDLE, RUN, ...) and moves between them on clock ticks. |
| **BRAM** | Block RAM: memory blocks inside the FPGA. Our IM and WM0 are made of them. You give an address, and the data arrives **one clock tick later**. |
| **Distributed RAM** | Memory built from ordinary logic (LUTs) instead of BRAM. WM1 is one. |
| **Lane** | One multiplier and its pixel/weight pair. 112 lanes = 112 multiplications per tick. |
| **Adder tree** | Adding 112 numbers by pairs: 112 → 56 → 28 → ... → 1, in 7 levels. |
| **Accumulator (`acc`)** | A register that keeps a running total: `acc = acc + new value` every tick. |
| **ReLU** | "If negative, make it 0." |
| **argmax** | "Which position holds the biggest value?" Here: which digit has the highest score. |
| **Pipeline** | Splitting work into steps with registers in between, so a new item can start every tick while older items finish (like a laundry line). |
| **Register / FF** | A storage cell that updates only on the clock tick (rising edge). |
| **Signed / unsigned** | Signed numbers can be negative (two's complement); unsigned can't. Pixels are unsigned, weights are signed. |
| **DSP / DSP48E1** | Ready-made fast multiplier blocks in the FPGA (90 on ours). |
| **LUT** | The basic logic cell of the FPGA (about 20 800 on ours). |
| **CDFG** | Control/Data Flow Graph: a drawing of which operations depend on which. The report needs one. |
| **Testbench (tb)** | A VHDL file that drives the circuit in simulation and checks its outputs. |
| **Behavioural simulation** | Simulating the VHDL as written: checks the logic, not the timing. |
| **Post-implementation timing simulation** | Simulating the real placed-and-routed circuit with real delays. The PDF requires it. |
| **WNS / slack** | How much time is left over on the slowest path at our clock. Must be ≥ 0, or the chip is too slow at that clock. |
| **Critical path** | The slowest path between two registers. It sets the maximum clock speed. |
| **Latency** | How many ticks (or how long) one picture takes from `start` to `done`. |
| **MAC** | One multiply-and-add. One picture needs 101 632 of them. |
| **Debounce** | Cleaning up a button press: a real button "bounces" and would look like many presses. |
