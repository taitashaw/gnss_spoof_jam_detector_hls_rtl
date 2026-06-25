#!/usr/bin/env bash
# clean.sh -- remove build + simulation artifacts (keeps committed sources).
# Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
rm -f  build/gnss_ref_sim
rm -rf results/*/ results/plots results/summary.md
rm -rf vectors/*/input_iq.txt vectors/*/tapped_stream.txt \
       vectors/*/expected_metrics.json vectors/*/metadata.json
# Xilinx junk
rm -rf xsim.dir .Xil *.jou *.pb *.wdb *.log vitis_hls.log \
       hls/vitis_hls/gnss_metric_hls_prj gnss_metric_hls_prj
echo "clean: removed build/results/vector artifacts."
