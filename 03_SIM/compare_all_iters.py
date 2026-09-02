#!/usr/bin/env python3
"""Run RTL sim and compare all 7 iteration QR/ROT checkpoints vs bit-true."""

import re
import subprocess
import sys
from pathlib import Path

SIM_DIR = Path(__file__).resolve().parent
ROOT = SIM_DIR.parent
RTL = ROOT / "01_RTL"

M_KEYS = ["M_11", "M_12", "M_13", "M_22", "M_23", "M_33"]


def load_goldens():
    out = subprocess.check_output(
        [sys.executable, str(SIM_DIR / "gen_iter_goldens.py")],
        text=True,
    )
    gold = {"QR": {}, "ROT": {}}
    u_gold = {}
    for line in out.splitlines():
        m = re.match(r"QR iter(\d+) (M_\d+) = (-?\d+)", line)
        if m:
            it, key, val = int(m.group(1)), m.group(2), int(m.group(3))
            gold["QR"].setdefault(it, {})[key] = val
            continue
        m = re.match(r"ROT iter(\d+) (M_\d+) = (-?\d+)", line)
        if m:
            it, key, val = int(m.group(1)), m.group(2), int(m.group(3))
            gold["ROT"].setdefault(it, {})[key] = val
            continue
        m = re.match(r"ROT iter(\d+) U(\d) = (-?\d+) (-?\d+) (-?\d+)", line)
        if m:
            it, row = int(m.group(1)), int(m.group(2))
            u_gold.setdefault(it, {})[row] = [int(m.group(3)), int(m.group(4)), int(m.group(5))]
    return gold, u_gold


def run_rtl():
    subprocess.run(
        [
            "iverilog", "-g2012", "-o", str(SIM_DIR / "all_iters.vvp"),
            str(RTL / "cordic_pe.v"),
            str(RTL / "du_delay.v"),
            str(RTL / "top.v"),
            str(SIM_DIR / "tb_all_iters_debug.v"),
        ],
        check=True,
    )
    return subprocess.check_output(
        ["vvp", str(SIM_DIR / "all_iters.vvp")], text=True, cwd=SIM_DIR
    )


def parse_rtl(out):
    rtl = {"QR": {}, "ROT": {}}
    u_rtl = {}
    for line in out.splitlines():
        m = re.match(
            r"RTL (QR|ROT) iter=(\d+) cyc=\d+ \| M (-?\d+) (-?\d+) (-?\d+) (-?\d+) (-?\d+) (-?\d+)",
            line,
        )
        if m:
            phase, it = m.group(1), int(m.group(2))
            vals = [int(x) for x in m.groups()[2:]]
            rtl[phase][it] = dict(zip(M_KEYS, vals))
            continue
        m = re.match(
            r"RTL U iter=(\d+) \| (-?\d+) (-?\d+) (-?\d+) \| (-?\d+) (-?\d+) (-?\d+) \| (-?\d+) (-?\d+) (-?\d+)",
            line,
        )
        if m:
            it = int(m.group(1))
            nums = [int(x) for x in m.groups()[1:]]
            u_rtl[it] = {i: nums[i * 3 : i * 3 + 3] for i in range(3)}
    return rtl, u_rtl


def cmp_m(label, it, got, exp, tol=0):
    fails = []
    max_abs = 0
    for k in M_KEYS:
        g, e = got.get(k), exp.get(k)
        if g is None or e is None:
            fails.append((k, e, g, None))
            continue
        d = abs(g - e)
        max_abs = max(max_abs, d)
        if d > tol:
            fails.append((k, e, g, g - e))
    if not fails:
        return True, max_abs
    return False, max_abs


def cmp_u(it, got, exp, tol=0):
    fails = []
    max_abs = 0
    for row in range(3):
        for col in range(3):
            g, e = got[row][col], exp[row][col]
            d = abs(g - e)
            max_abs = max(max_abs, d)
            if d > tol:
                fails.append((row, col, e, g, g - e))
    if not fails:
        return True, max_abs
    return False, max_abs


def print_m_table(phase, it, rtl_m, gold_m):
    print(f"  [{phase}] M_regs (upper triangle / symmetric 6-register layout)")
    print(f"  {'entry':<8} {'golden':>10} {'RTL':>10} {'diff':>10} {'match':>6}")
    print(f"  {'-'*8} {'-'*10} {'-'*10} {'-'*10} {'-'*6}")
    for k in M_KEYS:
        e = gold_m.get(k)
        g = rtl_m.get(k)
        d = (g - e) if e is not None and g is not None else None
        ok = "OK" if d == 0 else ""
        print(f"  {k:<8} {e:>10} {g:>10} {d:>10} {ok:>6}")


def print_u_table(it, rtl_u, gold_u):
    print(f"  [ROT] U_buf (3x3 dense)")
    print(f"  {'entry':<10} {'golden':>10} {'RTL':>10} {'diff':>10} {'match':>6}")
    print(f"  {'-'*10} {'-'*10} {'-'*10} {'-'*10} {'-'*6}")
    for row in range(3):
        for col in range(3):
            e = gold_u[row][col]
            g = rtl_u[row][col]
            d = g - e
            ok = "OK" if d == 0 else ""
            print(f"  U[{row}][{col}]   {e:>10} {g:>10} {d:>10} {ok:>6}")


def print_full_report(gold, u_gold, rtl, u_rtl):
    print("=" * 72)
    print("FULL RTL vs GOLDEN — all 7 iterations (Matrix(:,:,8), notebook cell 4)")
    print("=" * 72)
    for it in range(7):
        print(f"\n{'#' * 72}")
        print(f"# ITERATION {it}")
        print(f"{'#' * 72}")
        print_m_table("QR", it, rtl["QR"].get(it, {}), gold["QR"].get(it, {}))
        print()
        print_m_table("ROT T", it, rtl["ROT"].get(it, {}), gold["ROT"].get(it, {}))
        print()
        print_u_table(it, u_rtl.get(it, {}), u_gold.get(it, {}))


def main():
    gold, u_gold = load_goldens()
    sim_out = run_rtl()
    rtl, u_rtl = parse_rtl(sim_out)

    print_full_report(gold, u_gold, rtl, u_rtl)

    print(f"\n{'=' * 72}")
    print("SUMMARY (max |diff| per checkpoint)")
    print(f"{'iter':>4}  {'QR':>6}  {'ROT_T':>6}  {'ROT_U':>6}")
    exact = 0
    for it in range(7):
        qr_ok, qr_max = cmp_m("QR", it, rtl["QR"].get(it, {}), gold["QR"].get(it, {}))
        rot_ok, rot_max = cmp_m("ROT", it, rtl["ROT"].get(it, {}), gold["ROT"].get(it, {}))
        u_ok, u_max = cmp_u(it, u_rtl.get(it, {}), u_gold.get(it, {}))
        exact += qr_ok + rot_ok + u_ok
        print(f"{it:4d}  {qr_max:6d}  {rot_max:6d}  {u_max:6d}")
    print(f"\nExact-match checkpoints: {exact}/21")
    sys.exit(0 if exact == 21 else 1)


if __name__ == "__main__":
    main()
