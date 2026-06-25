#!/usr/bin/env bash
# run_hls.sh -- run the full Vitis HLS flow (csim + csynth + export).
# Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
#
# Detects the HLS driver available on this machine, in order:
#   1. classic `vitis_hls` on PATH        -> vitis_hls -f run_hls.tcl
#   2. `vitis-run` on PATH                -> vitis-run --mode hls --tcl run_hls.tcl
#   3. a Vitis install under common roots -> <root>/bin/vitis-run --mode hls ...
# If none is found, fails honestly (use `make selfcheck` / `make hls-csim`).
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PART="${1:-xczu7ev-ffvc1156-2-e}"
TCL="$REPO/hls/vitis_hls/run_hls.tcl"
cd "$REPO/hls/vitis_hls"

run_with() { echo "Running HLS via: $*"; "$@"; }

if command -v vitis_hls >/dev/null 2>&1; then
  run_with vitis_hls -f "$TCL"; exit $?
fi
if command -v vitis-run >/dev/null 2>&1; then
  run_with vitis-run --mode hls --tcl "$TCL"; exit $?
fi
# search common install locations for the vitis-run launcher
for vr in /tools/Xilinx/*/Vitis/bin/vitis-run /opt/Xilinx/*/Vitis/bin/vitis-run; do
  if [[ -x "$vr" ]]; then
    run_with "$vr" --mode hls --tcl "$TCL"; exit $?
  fi
done

echo "ERROR: no Vitis HLS driver found (vitis_hls / vitis-run)."
echo "       Install Vitis HLS 2022.2+ or run 'make selfcheck' / 'make hls-csim'."
exit 1
