#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_DIR="$ROOT/03_SIM"
RTL_DIR="$ROOT/01_RTL"

cd "$SIM_DIR"

echo "=== Bit-true reference (Matrix(:,:,8)) ==="
python3 gen_top_vectors.py | tee top_vectors.tmp

iverilog -g2012 -o top_sim.vvp \
  "$RTL_DIR/cordic_pe.v" \
  "$RTL_DIR/du_delay.v" \
  "$RTL_DIR/top.v" \
  "$SIM_DIR/tb_top.v"

vvp top_sim.vvp
