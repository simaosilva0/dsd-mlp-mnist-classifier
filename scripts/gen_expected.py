"""
Piece 0: expected values for the Lab 3 testbench.

Runs the course software model (materials/SW-model-2026116/mlp_model.py) on the 16 test
images and writes sim/mlp_expected_pkg.vhd with, for every image:
    H_EXP(img)(m)   h[m] after ReLU            (m = 0..127)
    O_EXP(img)(j)   o[j] of layer 1            (j = 0..9)
    RESULT_EXP(img) digit predicted by the model (argmax, first maximum)
    TRUE_DIGIT(img) the digit actually drawn (labels below, read by eye)

Before writing, it also checks that the course memory files (IMem.vhd, WMem0.vhd,
WMem1.vhd) hold exactly the same images and weights as the model's input files, in the
order the assignment describes (row addresses 8*img + k/112, 7*m + k/112 and m).

Usage (from the repository root):
    python scripts/gen_expected.py                 # division mode 'shift' (model default)
    python scripts/gen_expected.py --mode trunc    # or 'sum'; see mlp_model.py
    python scripts/gen_expected.py --no-check      # skip the memory-file check
"""

import argparse
import re
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parent.parent
MODEL_DIR = REPO / "materials" / "SW-model-2026116"
MEM_DIR = REPO / "materials"
OUT_FILE = REPO / "sim" / "mlp_expected_pkg.vhd"

# Reuse the professor's model instead of copying it: same PGM reader, same layer 1.
sys.path.insert(0, str(MODEL_DIR))
import mlp_model  # noqa: E402  (its main() only runs from the command line)

NUM_IMAGES = 16
N_IN, N_HID, N_OUT = 784, 128, 10
ROW = 112                       # values per memory row (one read)
ROWS_PER_VEC = N_IN // ROW      # 7

# True digit of each image. The .pgm files have no labels: these were read by eye from the
# ASCII art this script prints. If you disagree with one, fix it here and rerun.
TRUE_DIGIT = [6, 9, 7, 2, 9, 4, 4, 2, 7, 0, 1, 3, 5, 8, 0, 6]


# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------
def load_model_inputs():
    w0 = np.loadtxt(MODEL_DIR / "w0.txt", dtype=np.int64).reshape(N_HID, N_IN)
    w1 = np.loadtxt(MODEL_DIR / "w1.txt", dtype=np.int64).reshape(N_OUT, N_HID)
    images = [mlp_model.load_pgm_p2(str(MODEL_DIR / f"mnist_input{i}.pgm")).reshape(-1)
              for i in range(NUM_IMAGES)]
    return w0, w1, images


def run_model(w0, w1, image, mode):
    acc = w0 @ image                      # layer 0, before ReLU
    h = np.maximum(0, acc)                # ReLU
    o = mlp_model.layer1(w1, h, mode)     # layer 1 with the chosen division by 32
    result = int(np.argmax(o))            # first maximum, as in the pseudocode
    return acc, h, o, result


# ---------------------------------------------------------------------------
# Memory files (check that they match the model's inputs)
# ---------------------------------------------------------------------------
def read_bram_rows(path, width):
    """Rows of every bank of a BRAM_SINGLE_MACRO memory file.

    Returns {bank: {row: value}}. Each INIT_xx holds 256 bits = 256/width rows, row 0 on
    the right (least significant bits). Rows that are not listed are 0.
    """
    rows_per_init = 256 // width
    mask = (1 << width) - 1
    banks, bank = {}, None
    for line in path.read_text().splitlines():
        m = re.match(r"\s*BANK(\d+)\s*:\s*BRAM_SINGLE_MACRO", line)
        if m:
            bank = int(m.group(1))
            banks[bank] = {}
            continue
        m = re.match(r'\s*INIT_([0-9A-Fa-f]{2})\s*=>\s*X"([0-9A-Fa-f]{64})"', line)
        if m and bank is not None:
            base = int(m.group(1), 16) * rows_per_init
            value = int(m.group(2), 16)
            for i in range(rows_per_init):
                banks[bank][base + i] = (value >> (width * i)) & mask
    return banks


def field(word, index, bits, signed):
    v = (word >> (bits * index)) & ((1 << bits) - 1)
    if signed and v >= 1 << (bits - 1):
        v -= 1 << bits
    return v


def check_memories(w0, w1, images):
    errors = []

    # IM: 7 banks x 64 bits, row 8*img + r = Input[112r .. 112r+111], 16 pixels per bank.
    im = read_bram_rows(MEM_DIR / "IMem.vhd", 64)
    for img in range(NUM_IMAGES):
        for r in range(ROWS_PER_VEC + 1):            # +1: the blank row must be all zeros
            for b in range(7):
                word = im[b].get(8 * img + r, 0)
                for p in range(16):
                    got = field(word, p, 4, signed=False)
                    exp = int(images[img][ROW * r + 16 * b + p]) if r < ROWS_PER_VEC else 0
                    if got != exp:
                        errors.append(f"IM img {img} row {r} bank {b} pixel {p}: {got} != {exp}")

    # WM0: 28 banks x 32 bits, row 7*m + r = w0[m][112r .. 112r+111], 4 weights per bank.
    wm0 = read_bram_rows(MEM_DIR / "WMem0.vhd", 32)
    for m in range(N_HID):
        for r in range(ROWS_PER_VEC):
            for b in range(28):
                word = wm0[b].get(7 * m + r, 0)
                for q in range(4):
                    got = field(word, q, 8, signed=True)
                    exp = int(w0[m][ROW * r + 4 * b + q])
                    if got != exp:
                        errors.append(f"WM0 m {m} row {r} bank {b} weight {q}: {got} != {exp}")

    # WM1: 128 rows x 80 bits, row m = w1[9][m] .. w1[0][m], w1[j][m] in bits 8j+7..8j.
    wm1 = {}
    for line in (MEM_DIR / "WMem1.vhd").read_text().splitlines():
        mm = re.match(r'\s*(\d+)\s*=>\s*X"([0-9A-Fa-f]{20})"', line)
        if mm:
            wm1[int(mm.group(1))] = int(mm.group(2), 16)
    for m in range(N_HID):
        for j in range(N_OUT):
            got = field(wm1.get(m, 0), j, 8, signed=True)
            if got != int(w1[j][m]):
                errors.append(f"WM1 row {m} j {j}: {got} != {int(w1[j][m])}")

    return errors


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
def vhdl_list(values, per_line, indent):
    lines = []
    for i in range(0, len(values), per_line):
        lines.append(indent + ", ".join(f"{int(v):>8}" for v in values[i:i + per_line]))
    return ",\n".join(lines)


def write_package(mode, hs, os_, results):
    pad = "      "
    h_rows = ",\n".join(f"    {i:2} => (\n{vhdl_list(h, 8, pad)})" for i, h in enumerate(hs))
    o_rows = ",\n".join(f"    {i:2} => ({', '.join(f'{int(v):>11}' for v in o)})"
                        for i, o in enumerate(os_))
    text = f"""-- Generated by scripts/gen_expected.py. Do not edit by hand: change the script and rerun.
-- Expected values of the MLP for the 16 images of IM, computed by the course software model
-- (materials/SW-model-2026116/mlp_model.py), division by 32 in mode '{mode}'.
library ieee;
use ieee.std_logic_1164.all;

package mlp_expected_pkg is

  constant DIV_MODE   : string  := "{mode}";
  constant NUM_IMAGES : natural := {NUM_IMAGES};

  type h_vec_t     is array (0 to {N_HID - 1}) of natural;   -- h[m], 0 .. 1 493 520 (21 bits)
  type h_tab_t     is array (0 to {NUM_IMAGES - 1}) of h_vec_t;
  type o_vec_t     is array (0 to {N_OUT - 1}) of integer;     -- o[j], 31-bit signed
  type o_tab_t     is array (0 to {NUM_IMAGES - 1}) of o_vec_t;
  type digit_vec_t is array (0 to {NUM_IMAGES - 1}) of natural;

  -- H_EXP(img)(m)
  constant H_EXP : h_tab_t := (
{h_rows});

  -- O_EXP(img)(j)
  constant O_EXP : o_tab_t := (
{o_rows});

  -- digit predicted by the model (what the circuit must output)
  constant RESULT_EXP : digit_vec_t := ({", ".join(str(r) for r in results)});

  -- digit actually drawn in each image (read by eye), for "number of correct classifications"
  constant TRUE_DIGIT : digit_vec_t := ({", ".join(str(d) for d in TRUE_DIGIT)});

end package mlp_expected_pkg;
"""
    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_FILE, "w", newline="\n") as f:
        f.write(text)


def print_images(images, results):
    for start in range(0, NUM_IMAGES, 4):
        group = range(start, min(start + 4, NUM_IMAGES))
        print("   ".join(f"img {i:2}: drawn {TRUE_DIGIT[i]}, model {results[i]}".ljust(28)
                         for i in group))
        for y in range(28):
            print("   ".join("".join("#" if images[i][28 * y + x] else "."
                                     for x in range(28)) for i in group))
        print()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    parser.add_argument("--mode", choices=["shift", "trunc", "sum"], default=mlp_model.DIV_MODE,
                        help="division by 32 in layer 1 (default: the model's, '%(default)s')")
    parser.add_argument("--no-check", action="store_true",
                        help="do not compare the memory files with the model inputs")
    args = parser.parse_args()

    w0, w1, images = load_model_inputs()

    if not args.no_check:
        errors = check_memories(w0, w1, images)
        if errors:
            print(f"ERROR: the memory files do not match the model inputs ({len(errors)} differences):")
            for e in errors[:20]:
                print("  " + e)
            print("Package NOT written.")
            sys.exit(1)
        print("Memory files match the model inputs (IM, WM0, WM1).\n")

    hs, os_, results = [], [], []
    print(f"Division mode: {args.mode}\n")
    print("img  drawn  model  ok   acc min    acc max   h=0     o min        o max     tie")
    for i, image in enumerate(images):
        acc, h, o, result = run_model(w0, w1, image, args.mode)
        hs.append(h)
        os_.append(o)
        results.append(result)
        tie = int(np.sum(o == o.max())) > 1
        print(f"{i:3}  {TRUE_DIGIT[i]:5}  {result:5}  {'yes' if result == TRUE_DIGIT[i] else 'NO':3}"
              f"  {int(acc.min()):9}  {int(acc.max()):9}  {int(np.sum(acc < 0)):4}"
              f"  {int(o.min()):11}  {int(o.max()):11}  {'YES' if tie else ''}")
    correct = sum(r == d for r, d in zip(results, TRUE_DIGIT))
    print(f"\nModel classifies {correct} of {NUM_IMAGES} images correctly.\n")

    print_images(images, results)

    write_package(args.mode, hs, os_, results)
    print(f"Written: {OUT_FILE.relative_to(REPO)}")


if __name__ == "__main__":
    main()
