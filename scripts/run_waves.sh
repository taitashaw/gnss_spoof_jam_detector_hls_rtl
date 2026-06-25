#!/usr/bin/env bash
# run_waves.sh -- regenerate the mixed_attack VCD/WDB and render the PNG.
# Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
command -v xvlog >/dev/null 2>&1 || { echo "ERROR: xvlog/Vivado not on PATH (needed for waveform)"; exit 1; }
[[ -f "$REPO/vectors/mixed_attack/input_iq.txt" ]] || "$REPO/scripts/gen_gnss_vectors.py" --scenario mixed_attack >/dev/null
WORK="$(mktemp -d)"; cd "$WORK"
xvlog -sv -d SIM_ASSERT "$REPO"/rtl/gnss/gnss_top_pkg.sv "$REPO"/rtl/common/*.sv \
  "$REPO"/rtl/gnss/nco_mixer.sv "$REPO"/rtl/gnss/prn_lfsr_gen.sv "$REPO"/rtl/gnss/early_prompt_late_tap.sv \
  "$REPO"/rtl/gnss/gnss_metric_hls_model.sv "$REPO"/rtl/gnss/gnss_alert_packer.sv "$REPO"/rtl/gnss/gnss_top.sv \
  "$REPO"/tb/axis_bfm.sv "$REPO"/tb/gnss_scoreboard.sv "$REPO"/tb/tb_gnss_top.sv >/dev/null 2>&1 || { echo "compile failed"; exit 1; }
xelab tb_gnss_top -s wsim -d SIM_ASSERT --timescale 1ns/1ps -debug typical >/dev/null 2>&1 || { echo "elab failed"; exit 1; }
printf 'log_wave -recursive *\nrun all\nexit\n' > dump.tcl
xsim wsim -tclbatch dump.tcl -wdb "$WORK/mixed_attack.wdb" \
  --testplusarg INFILE="$REPO/vectors/mixed_attack/input_iq.txt" \
  --testplusarg OUTFILE=/tmp/waves_out.txt --testplusarg SCENARIO=mixed_attack \
  --testplusarg STALL_MODE=burst --testplusarg SEED=12648430 --testplusarg DUMPVCD=1 \
  --testplusarg VCDFILE="$REPO/docs/images/mixed_attack.vcd" 2>&1 | grep -E 'PASS|FAIL' | tail -1
python3 "$REPO/scripts/render_wave.py" "$REPO/docs/images/mixed_attack.vcd" "$REPO/docs/images/waveform_mixed_attack.png"
cd /; rm -rf "$WORK"
echo "waveform refreshed: docs/images/waveform_mixed_attack.png + mixed_attack.vcd"
