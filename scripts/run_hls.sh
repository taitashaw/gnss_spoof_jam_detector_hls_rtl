#!/usr/bin/env bash
# run_hls.sh -- thin wrapper to run the full Vitis HLS flow (csim+csynth+export).
# Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
# Invoked by `make hls` (which already checks vitis_hls is on PATH).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PART="${1:-xczu7ev-ffvc1156-2-e}"
if ! command -v vitis_hls >/dev/null 2>&1; then
  echo "ERROR: vitis_hls not on PATH. Install Vitis HLS 2022.2+."
  echo "       (For a C-simulation-only check without the full tool, use: make hls-csim)"
  exit 1
fi
cd "$REPO/hls/vitis_hls"
echo "Running Vitis HLS (PART=$PART) ..."
vitis_hls -f run_hls.tcl
echo "HLS reports: hls/vitis_hls/gnss_metric_hls_prj/sol1/syn/report/"
