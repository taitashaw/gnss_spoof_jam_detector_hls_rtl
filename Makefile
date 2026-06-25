# ============================================================================
# gnss_spoof_jam_detector_hls_rtl -- top-level Makefile
# Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
#
# Lead with `make selfcheck` -- it runs on plain Linux with only python3 + g++
# and is the authoritative "does it work" gate. The tool-dependent targets
# (`make hls`, `make xsim`) fail honestly when the Xilinx tools are absent.
# ============================================================================

PYTHON      ?= python3
SCRIPTS     := scripts
RESULTS     := results
SCENARIOS   := clean wideband_jam tone_jam delayed_spoof doppler_shift cn0_drop mixed_attack backpressure

# Single place to change the target part (also used by the TCL scripts).
PART        ?= xczu7ev-ffvc1156-2-e

.DEFAULT_GOAL := help

.PHONY: help vectors selfcheck refsim check summary plots hls hls-csim xsim all clean

help:
	@echo "GNSS Spoof/Jam Detector -- make targets"
	@echo ""
	@echo "  make selfcheck   Python+g++ only. Vectors -> golden sim -> check -> summary."
	@echo "                   THE primary gate; needs NO Xilinx tools."
	@echo "  make vectors     Generate all 8 scenario vectors (+ tapped_stream)."
	@echo "  make refsim      Run the C golden model over all scenarios."
	@echo "  make check       Validate results against expected ranges + exact flags."
	@echo "  make summary     Write results/summary.md."
	@echo "  make plots       Optional matplotlib plots -> results/plots/*.png."
	@echo "  make hls         Vitis HLS C-sim + synth + export (needs vitis_hls on PATH)."
	@echo "  make hls-csim    HLS kernel C-sim vs golden via g++ + Vitis headers"
	@echo "                   (validates the synthesizable source; no synthesis)."
	@echo "  make xsim        XSim cycle sim for all scenarios (needs Vivado/xvlog)."
	@echo "  make all         selfcheck, then hls + xsim if their tools are present."
	@echo "  make clean       Remove build/ and results/ artifacts."
	@echo ""
	@echo "  PART=$(PART)  (override on the command line to retarget)"

# ---- Python-only flow ------------------------------------------------------
vectors:
	@$(PYTHON) $(SCRIPTS)/gen_gnss_vectors.py

refsim: vectors
	@$(PYTHON) $(SCRIPTS)/run_reference_sim.py

check:
	@$(PYTHON) $(SCRIPTS)/check_gnss_results.py

summary:
	@$(PYTHON) $(SCRIPTS)/summarize_results.py

plots:
	@$(PYTHON) $(SCRIPTS)/plot_gnss_metrics.py || echo "  (plots skipped -- matplotlib not available)"

selfcheck: vectors refsim check summary
	@echo ""
	@echo "selfcheck complete -- see results/summary.md"

# ---- Tool-dependent flows (fail honestly if tools absent) ------------------
hls:
	@command -v vitis_hls >/dev/null 2>&1 || { \
	  echo "ERROR: vitis_hls not on PATH. Install Vitis HLS 2022.2+ or run 'make selfcheck'."; exit 1; }
	@bash $(SCRIPTS)/run_hls.sh $(PART)

hls-csim: vectors
	@bash $(SCRIPTS)/run_hls_csim.sh

xsim: vectors
	@command -v xvlog >/dev/null 2>&1 || { \
	  echo "ERROR: xvlog/Vivado not on PATH. Install Vivado 2022.2+ or run 'make selfcheck'."; exit 1; }
	@bash $(SCRIPTS)/run_xsim.sh

all: selfcheck
	@echo ""
	@if command -v vitis_hls >/dev/null 2>&1; then \
	  echo "== Vitis HLS detected: running make hls =="; $(MAKE) hls || true; \
	else echo "== Vitis HLS not found: trying HLS C-sim via headers (make hls-csim) =="; \
	  $(MAKE) hls-csim || echo "   (hls-csim skipped: no Vitis headers)"; fi
	@if command -v xvlog >/dev/null 2>&1; then \
	  echo "== Vivado/XSim detected: running make xsim =="; $(MAKE) xsim || true; $(MAKE) check summary || true; \
	else echo "== Vivado/XSim not found: skipping make xsim =="; fi

clean:
	@bash $(SCRIPTS)/clean.sh
