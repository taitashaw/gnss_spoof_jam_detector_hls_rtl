#!/usr/bin/env bash
# ============================================================================
# run_xsim.sh -- compile + run the GNSS XSim scenario matrix (Vivado XSim)
# Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
#
# Bash orchestrator used by `make xsim`. Uses xvlog/xelab/xsim directly (the
# validated non-project flow). Source ORDER is kept in sync with
# vivado/compile_order.tcl. Writes results/<scenario>/actual_metrics.txt for
# scripts/check_gnss_results.py; backpressure uses a fixed seed (reproducible).
# ============================================================================
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SEED=12648430   # 0xC0FFEE
WORK="$(mktemp -d)"
cd "$WORK"

echo "== compile (xvlog -d SIM_ASSERT) =="
xvlog -sv -d SIM_ASSERT \
  "$REPO/rtl/gnss/gnss_top_pkg.sv" \
  "$REPO/rtl/common/axis_skid_buffer.sv" \
  "$REPO/rtl/common/axis_register_slice.sv" \
  "$REPO/rtl/common/axis_packet_counter.sv" \
  "$REPO/rtl/common/axis_latency_counter.sv" \
  "$REPO/rtl/common/axis_protocol_checker.sv" \
  "$REPO/rtl/common/simple_reg_bank.sv" \
  "$REPO/rtl/gnss/nco_mixer.sv" \
  "$REPO/rtl/gnss/prn_lfsr_gen.sv" \
  "$REPO/rtl/gnss/early_prompt_late_tap.sv" \
  "$REPO/rtl/gnss/gnss_metric_hls_model.sv" \
  "$REPO/rtl/gnss/gnss_alert_packer.sv" \
  "$REPO/rtl/gnss/gnss_top.sv" \
  "$REPO/tb/axis_bfm.sv" \
  "$REPO/tb/gnss_scoreboard.sv" \
  "$REPO/tb/tb_gnss_top.sv" \
  "$REPO/tb/tb_axis_skid_buffer.sv" \
  "$REPO/tb/tb_nco_mixer.sv" \
  "$REPO/tb/tb_prn_lfsr_gen.sv" || { echo "xvlog FAILED"; exit 1; }

echo "== elaborate tb_gnss_top =="
xelab tb_gnss_top -s gnss_sim -d SIM_ASSERT --timescale 1ns/1ps >/dev/null 2>&1 \
  || { echo "xelab FAILED"; exit 1; }

# Section-12 test matrix: scenario:stall_mode
MATRIX=(
  "clean:none" "clean:random" "wideband_jam:none" "tone_jam:random"
  "delayed_spoof:random" "doppler_shift:burst" "cn0_drop:none"
  "mixed_attack:random" "backpressure:random"
)

fail=0
for item in "${MATRIX[@]}"; do
  scen="${item%%:*}"; mode="${item##*:}"
  infile="$REPO/vectors/$scen/input_iq.txt"
  outdir="$REPO/results/$scen"; mkdir -p "$outdir"
  outfile="$outdir/actual_metrics.txt"
  if [[ ! -f "$infile" ]]; then echo "SKIP $scen (no vectors -- run 'make vectors')"; continue; fi
  out="$(xsim gnss_sim -R \
      --testplusarg INFILE="$infile" \
      --testplusarg OUTFILE="$outfile" \
      --testplusarg SCENARIO="$scen" \
      --testplusarg STALL_MODE="$mode" \
      --testplusarg SEED="$SEED" 2>&1)"
  res="$(echo "$out" | grep -E 'PASS|FAIL' | tail -1)"
  echo "  [$scen/$mode] $res"
  echo "$res" | grep -q PASS || fail=1
done

echo "== unit testbenches =="
for ut in tb_axis_skid_buffer tb_nco_mixer tb_prn_lfsr_gen; do
  xelab "$ut" -s "${ut}_s" --timescale 1ns/1ps >/dev/null 2>&1 || { echo "  $ut elab FAILED"; fail=1; continue; }
  res="$(xsim "${ut}_s" -R 2>&1 | grep -E 'PASS|FAIL' | tail -1)"
  echo "  $res"
  echo "$res" | grep -q PASS || fail=1
done

cd /; rm -rf "$WORK"
echo ""
if [[ $fail -eq 0 ]]; then
  echo "XSim matrix complete. Validate metrics with: make check"
else
  echo "XSim matrix had FAILURES."; exit 1
fi
