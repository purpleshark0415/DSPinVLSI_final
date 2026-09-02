#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_DIR="$ROOT/03_SIM"
RTL_DIR="$ROOT/01_RTL"

cd "$SIM_DIR"

python3 gen_cordic_pe_vectors.py > vectors.tmp
# Refresh embedded golden values in tb if needed manually; script prints reference values.

iverilog -g2012 -o cordic_pe_sim.vvp \
  "$RTL_DIR/cordic_pe.v" \
  "$SIM_DIR/tb_cordic_pe.v"

vvp cordic_pe_sim.vvp
