#!/usr/bin/env python3
"""Bit-true golden vectors for qrd_top — matches 04_PYTHON/01_bit_true.ipynb cell 5."""

import json
import os
import sys

import numpy as np
import scipy.io

sys.path.insert(0, os.path.dirname(__file__))
from gen_cordic_pe_vectors import (  # noqa: E402
    DATA_FRAC_BITS,
    INT_BITS,
    S_FRAC_BITS,
    STAGES,
    TOTAL_BITS,
    to_fixed,
    wrap_signed,
)

ITERATIONS = 7
PATTERN_IDX = 7  # Matrix(:,:,8) — 1-based index 8, 0-based 7
NOTEBOOK_PATH = os.path.join(
    os.path.dirname(__file__), "..", "04_PYTHON", "01_bit_true.ipynb"
)
MAT_PATH = os.path.join(
    os.path.dirname(__file__), "..", "04_PYTHON", "Final11Pattern.mat"
)
TESTBED_DIR = os.path.join(os.path.dirname(__file__), "..", "00_TESTBED")


def _load_notebook_cell5_api():
    """Exec cell-5 integer HW model (single source of truth)."""
    with open(NOTEBOOK_PATH, encoding="utf-8") as f:
        nb = json.load(f)
    src4 = "".join(nb["cells"][4]["source"])
    src5 = "".join(nb["cells"][5]["source"])

    api = {"np": np, "STAGES": STAGES, "ITERATIONS": ITERATIONS}

    start_csd = src4.find("def get_scaling_factor_csd")
    end_csd = src4.find("def truncate")
    if start_csd < 0 or end_csd < 0:
        raise RuntimeError("Could not locate get_scaling_factor_csd in cell 4")
    exec(src4[start_csd:end_csd], api)  # noqa: S102

    start_trunc = src4.find("def truncate")
    end_trunc = src4.find("def round_half_up")
    exec(src4[start_trunc:end_trunc], api)  # noqa: S102

    start5 = src5.find("FRAC_BITS = ")
    mid5 = src5.find("# 4. 主程式")
    end5 = src5.find('\nprint("=" * 72)', mid5)
    if start5 < 0 or mid5 < 0 or end5 < 0:
        raise RuntimeError("Could not locate cell 5 integer model in notebook")
    exec(src5[start5:mid5], api)  # noqa: S102
    exec(src5[mid5:end5], api)  # noqa: S102
    return api


_NB = _load_notebook_cell5_api()
truncate = _NB["truncate"]
get_scaling_factor_csd = _NB["get_scaling_factor_csd"]
set_wordlength = _NB["set_wordlength"]
to_int18 = _NB["to_int18"]
float_mat_to_int18 = _NB["float_mat_to_int18"]
run_int18_eigen_solver = _NB["run_int18_eigen_solver"]
systolic_iteration_int18 = _NB["systolic_iteration_int18"]
cordic_vectoring_int18 = _NB["cordic_vectoring_int18"]
cordic_rotation_int18 = _NB["cordic_rotation_int18"]


def qrd_phase_int18(t, stages, csd_array, s_frac_bits):
    """QRD only (Phase 1) — upper-triangle R after vectoring + column rotations."""
    r = t.copy()

    r[0, 0], r[1, 0], d1 = cordic_vectoring_int18(
        r[0, 0], r[1, 0], stages, csd_array, s_frac_bits
    )
    for j in range(1, 3):
        r[0, j], r[1, j] = cordic_rotation_int18(
            r[0, j], r[1, j], d1, csd_array, s_frac_bits
        )

    r[0, 0], r[2, 0], d2 = cordic_vectoring_int18(
        r[0, 0], r[2, 0], stages, csd_array, s_frac_bits
    )
    for j in range(1, 3):
        r[0, j], r[2, j] = cordic_rotation_int18(
            r[0, j], r[2, j], d2, csd_array, s_frac_bits
        )

    r[1, 1], r[2, 1], d3 = cordic_vectoring_int18(
        r[1, 1], r[2, 1], stages, csd_array, s_frac_bits
    )
    for j in range(2, 3):
        r[1, j], r[2, j] = cordic_rotation_int18(
            r[1, j], r[2, j], d3, csd_array, s_frac_bits
        )

    r[1, 0] = r[2, 0] = r[2, 1] = 0
    return r


def run_eigen_int18(mat_float, frac_bits=DATA_FRAC_BITS):
    """7-iteration eigen-solver — notebook cell 5 integer model."""
    set_wordlength(frac_bits, INT_BITS)
    csd_array, _, _ = get_scaling_factor_csd(STAGES, S_FRAC_BITS)
    _NB["csd_array"] = csd_array
    a_int = float_mat_to_int18(mat_float, frac_bits)
    eig_int, u_int, _, _ = run_int18_eigen_solver(a_int, frac_bits)
    eigvals = np.array(
        [wrap_signed(v) / (2 ** frac_bits) for v in eig_int], dtype=float
    )
    u_float = np.array(
        [
            [wrap_signed(u_int[r, c]) / (2 ** frac_bits) for c in range(3)]
            for r in range(3)
        ],
        dtype=float,
    )
    return a_int, u_int, eig_int, u_float


def float_to_fixed_int(val, frac_bits=DATA_FRAC_BITS):
    """Map truncated-float Q-value to signed integer."""
    return to_fixed(truncate(val, frac_bits))


def fmt_fixed(val):
    if val < 0:
        return f"-{TOTAL_BITS}'sd{-val}"
    return f"{TOTAL_BITS}'sd{val}"


def write_testbed_files(a_int, eig_int, u_int, iter_goldens=None):
    """Write 00_TESTBED/input.txt and golden_output.txt."""
    os.makedirs(TESTBED_DIR, exist_ok=True)

    input_path = os.path.join(TESTBED_DIR, "input.txt")
    with open(input_path, "w", encoding="utf-8") as f:
        for col in range(3):
            f.write(
                f"{int(a_int[0, col])} "
                f"{int(a_int[1, col])} "
                f"{int(a_int[2, col])}\n"
            )

    out_path = os.path.join(TESTBED_DIR, "golden_output.txt")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(f"{eig_int[0]} {eig_int[1]} {eig_int[2]}\n")
        # RTL ST_DONE streams U columns (not rows)
        for col in range(3):
            f.write(
                f"{int(u_int[0, col])} "
                f"{int(u_int[1, col])} "
                f"{int(u_int[2, col])}\n"
            )

    if iter_goldens is not None:
        iter_path = os.path.join(TESTBED_DIR, "golden_iter.txt")
        with open(iter_path, "w", encoding="utf-8") as f:
            for block in iter_goldens:
                f.write(block)


def main():
    data = scipy.io.loadmat(MAT_PATH)
    mat = data["Matrix"][:, :, PATTERN_IDX]

    print(f"// Bit-true golden for Matrix(:,:,8) — pattern index {PATTERN_IDX}")
    print("// Model: 04_PYTHON/01_bit_true.ipynb cell 5 (integer, round-half-up)")
    print(f"// Source: {MAT_PATH}")
    print(
        f"// STAGES={STAGES} DATA_FRAC_BITS={DATA_FRAC_BITS} INT_BITS={INT_BITS} "
        f"TOTAL_BITS={TOTAL_BITS} S_FRAC_BITS={S_FRAC_BITS} ITERATIONS={ITERATIONS}"
    )
    print()

    a_int, u_int, eig_int, eigvals_f = run_eigen_int18(mat, DATA_FRAC_BITS)

    print("// Input matrix (float from .mat)")
    for i in range(3):
        row = " ".join(f"{mat[i, j]:12.8f}" for j in range(3))
        print(f"//   [{row}]")
    print()

    print("// Quantized input columns (InData_row1/2/3 per InValid cycle)")
    for col in range(3):
        c0, c1, c2 = int(a_int[0, col]), int(a_int[1, col]), int(a_int[2, col])
        print(f"in_col[{col}] = '{{{fmt_fixed(c0)}, {fmt_fixed(c1)}, {fmt_fixed(c2)}}};")
    print()

    print("// Expected OutValid sequence (4 cycles)")
    print(f"golden_eig = '{{{fmt_fixed(eig_int[0])}, {fmt_fixed(eig_int[1])}, {fmt_fixed(eig_int[2])}}};")
    for col in range(3):
        u0, u1, u2 = int(u_int[0, col]), int(u_int[1, col]), int(u_int[2, col])
        print(f"golden_u_col[{col}] = '{{{fmt_fixed(u0)}, {fmt_fixed(u1)}, {fmt_fixed(u2)}}};")
    print()

    print("// Float interpretation (debug)")
    print(f"// eigenvalues: {list(eigvals_f)}")
    for row in range(3):
        print(
            f"// U row {row}: "
            f"{[u_int[row, c] / (2**DATA_FRAC_BITS) for c in range(3)]}"
        )

    ref_vals = np.linalg.eigh(mat)[0]
    golden_desc = ref_vals[np.argsort(ref_vals)[::-1]]
    rmse = np.sqrt(np.mean((golden_desc - eigvals_f) ** 2))
    print()
    print(f"// np.linalg.eigh (desc): {list(golden_desc)}")
    print(f"// eigenvalue RMSE vs eigh (desc): {rmse:.6e}")

    write_testbed_files(a_int, list(eig_int), u_int)
    print("// Wrote 00_TESTBED/input.txt, golden_output.txt")


if __name__ == "__main__":
    main()
