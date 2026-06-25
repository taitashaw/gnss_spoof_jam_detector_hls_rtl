#!/usr/bin/env bash
# run_hls_csim.sh -- C-simulation of the HLS kernel vs the golden reference.
# Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
#
# Compiles the SYNTHESIZABLE kernel (hls/src/gnss_metric_hls.cpp, real ap_int /
# ap_axiu / hls::stream) together with its testbench using g++ against the Vitis
# HLS headers, then runs it. This is the same C-level check Vitis HLS csim_design
# performs -- it validates the kernel logic without needing the full tool. It
# does NOT perform synthesis or produce timing/resource numbers (run `make hls`
# with Vitis HLS for that).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"

# locate ap_int.h from a Vitis/Vivado install or $HLS_INCLUDE
CAND="${HLS_INCLUDE:-}"
if [[ -z "$CAND" ]]; then
  for d in /tools/Xilinx/*/Vitis/include /opt/Xilinx/*/Vitis/include \
           /tools/Xilinx/*/Vivado/include /opt/Xilinx/*/Vivado/include; do
    [[ -f "$d/ap_int.h" ]] && { CAND="$d"; break; }
  done
fi
if [[ -z "$CAND" || ! -f "$CAND/ap_int.h" ]]; then
  echo "ERROR: could not find ap_int.h (Vitis HLS headers)."
  echo "       Set HLS_INCLUDE=/path/to/Vitis/include and retry, or run 'make selfcheck'."
  exit 1
fi
echo "Using HLS headers: $CAND"
mkdir -p "$REPO/build"
g++ -O1 -std=c++14 -I "$REPO/hls/include" -I "$CAND" \
    "$REPO/hls/src/gnss_metric_hls.cpp" "$REPO/hls/tb/tb_gnss_metric_hls.cpp" \
    -o "$REPO/build/hls_csim" 2>/dev/null || { echo "ERROR: HLS csim compile failed"; exit 1; }
"$REPO/build/hls_csim" "$REPO"
