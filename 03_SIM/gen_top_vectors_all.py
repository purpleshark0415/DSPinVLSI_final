#!/usr/bin/env python3
"""Generate 11-pattern vectors for qrd_top (Matrix(:,:,1..11)).

Outputs (in 00_TESTBED):
  - input_all.txt          : 11 patterns * 3 lines (each line is one column: r1 r2 r3)
  - golden_output_all.txt  : 11 patterns * 4 lines (eig, then U col0/1/2)
"""

import os
import sys

import numpy as np
import scipy.io

THIS_DIR = os.path.dirname(__file__)
sys.path.insert(0, THIS_DIR)

from gen_top_vectors import MAT_PATH, TESTBED_DIR, run_eigen_int18  # noqa: E402

NUM_PATTERNS = 11


def main():
    data = scipy.io.loadmat(MAT_PATH)
    mats = data["Matrix"]

    if mats.ndim != 3 or mats.shape[0] != 3 or mats.shape[1] != 3:
        raise RuntimeError(f"Unexpected Matrix shape: {mats.shape}")
    if mats.shape[2] < NUM_PATTERNS:
        raise RuntimeError(f"Matrix has only {mats.shape[2]} patterns, expected >= {NUM_PATTERNS}")

    os.makedirs(TESTBED_DIR, exist_ok=True)
    input_path = os.path.join(TESTBED_DIR, "input_all.txt")
    golden_path = os.path.join(TESTBED_DIR, "golden_output_all.txt")

    with open(input_path, "w", encoding="utf-8") as fin, open(golden_path, "w", encoding="utf-8") as fg:
        for pat in range(NUM_PATTERNS):
            mat = mats[:, :, pat]
            a_int, u_int, eig_int, _u_float = run_eigen_int18(mat)

            # input: 3 columns
            for col in range(3):
                fin.write(f"{int(a_int[0, col])} {int(a_int[1, col])} {int(a_int[2, col])}\n")

            # golden: eig, then U columns (RTL order)
            fg.write(f"{int(eig_int[0])} {int(eig_int[1])} {int(eig_int[2])}\n")
            for col in range(3):
                fg.write(f"{int(u_int[0, col])} {int(u_int[1, col])} {int(u_int[2, col])}\n")

    print(f"Wrote: {input_path}")
    print(f"Wrote: {golden_path}")


if __name__ == "__main__":
    main()

