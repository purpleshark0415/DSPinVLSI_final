#!/usr/bin/env python3
"""Bit-true golden M_regs + U after each QR and ROT (7 iterations)."""

import os
import sys

import numpy as np
import scipy.io

sys.path.insert(0, os.path.dirname(__file__))
from gen_cordic_pe_vectors import DATA_FRAC_BITS, INT_BITS, STAGES, S_FRAC_BITS, to_fixed
from gen_top_vectors import (
    ITERATIONS,
    PATTERN_IDX,
    float_mat_to_int18,
    get_scaling_factor_csd,
    qrd_phase_int18,
    set_wordlength,
    systolic_iteration_int18,
    truncate,
    write_testbed_files,
)

MAT_PATH = os.path.join(
    os.path.dirname(__file__), "..", "04_PYTHON", "Final11Pattern.mat"
)


def m_regs_from_r(r):
    return {
        "M_11": int(r[0, 0]),
        "M_12": int(r[0, 1]),
        "M_13": int(r[0, 2]),
        "M_22": int(r[1, 1]),
        "M_23": int(r[1, 2]),
        "M_33": int(r[2, 2]),
    }


def m_regs_from_t(t):
    return {
        "M_11": int(t[0, 0]),
        "M_12": int(t[0, 1]),
        "M_13": int(t[0, 2]),
        "M_22": int(t[1, 1]),
        "M_23": int(t[1, 2]),
        "M_33": int(t[2, 2]),
    }


def u_rows(u):
    return [[int(u[i, j]) for j in range(3)] for i in range(3)]


def m_regs_line(m):
    return f"{m['M_11']} {m['M_12']} {m['M_13']} {m['M_22']} {m['M_23']} {m['M_33']}\n"


def main():
    set_wordlength(DATA_FRAC_BITS, INT_BITS)
    csd = get_scaling_factor_csd(STAGES, S_FRAC_BITS)[0]
    mat = scipy.io.loadmat(MAT_PATH)["Matrix"][:, :, PATTERN_IDX]
    a_int = float_mat_to_int18(mat, DATA_FRAC_BITS)

    fix_one = 1 << DATA_FRAC_BITS
    t = a_int.copy()
    u = np.zeros((3, 3), dtype=int)
    u[0, 0] = fix_one
    u[1, 1] = fix_one
    u[2, 2] = fix_one
    iter_blocks = []

    print(
        f"// Bit-true per-iteration goldens — Matrix(:,:,8), {ITERATIONS} iterations"
    )
    print("// Model: systolic_iteration_int18 (notebook cell 4)")
    for it in range(ITERATIONS):
        r = qrd_phase_int18(t, STAGES, csd, S_FRAC_BITS)
        rm = m_regs_from_r(r)
        print(f"// --- iter {it} QR (R) ---")
        for k, v in rm.items():
            print(f"QR iter{it} {k} = {v}")
        iter_blocks.append(m_regs_line(rm))

        t, u = systolic_iteration_int18(t, u, STAGES, csd, S_FRAC_BITS)
        tm = m_regs_from_t(t)
        ur = u_rows(u)
        print(f"// --- iter {it} ROT (T, U) ---")
        for k, v in tm.items():
            print(f"ROT iter{it} {k} = {v}")
        iter_blocks.append(m_regs_line(tm))
        for i, row in enumerate(ur):
            print(f"ROT iter{it} U{i} = {row[0]} {row[1]} {row[2]}")
            iter_blocks.append(f"{row[0]} {row[1]} {row[2]}\n")

    eig_int = [int(t[i, i]) for i in range(3)]
    write_testbed_files(a_int, eig_int, u, iter_blocks)
    print("// Wrote 00_TESTBED/golden_iter.txt, golden_output.txt, input.txt")


if __name__ == "__main__":
    main()
