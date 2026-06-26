# Known Limitations

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

Deliberately honest scope for the current **DBZP ddMap + own-FFT + SQM** detector.
These are real boundaries, not defects, and every one is reported elsewhere with
measurements.

- **ds2 (overpowered time-push) is not separated by the SQM distortion.** The
  early/late distortion catches matched-power SCER (ds7) at 100% / 0% clean
  false-alarm, but an overpowered, displaced-but-clean peak (ds2) is honestly not
  separated by peak shape — it must be caught by absolute power / ddMap energy. See
  `docs/single_pass_detection.md`.
- **Sample scope is one slice per scenario**, over the acquired satellites, at a
  single coherent length — a measured result, not a full ROC sweep. The DBZP-vs-PCS
  sensitivity gain (+1–2 dB) is consistent with literature but measured on a limited
  set (`docs/comparison_baseline_vs_ddmap.md`).
- **Not a tracking receiver.** It computes one acquisition ddMap cell per call and
  reads spoof/jam signatures off it; it does not close tracking loops or output a
  PVT solution.
- **Carrier-Doppler wipeoff and the PRN/Doppler search loop are the host's job.** The
  kernel computes one cell (one PRN, one Doppler hypothesis); the outer search is
  software.
- **Throughput cost of the 488 MHz timing closure.** Closing 400 MHz used a ping-pong
  FFT (II=2 butterfly) and per-call LOAD/OUT copies, raising latency from 80,208 to
  271,504 cycles/cell (~3.4×). It still meets the real-time monitoring deadline (7.2×
  per-cell headroom; `docs/audit_latency_cdc.md`). A streaming SDF FFT would recover
  throughput but is not required by the deadline.
- **Not board-flashed.** The own-FFT kernel is exported as IP and integrated into a
  Zynq UltraScale+ block design that validates with zero critical warnings
  (`vivado/run_bd_ownfft.tcl`), with a rendered block-design diagram and a real cosim
  AXIS waveform (`docs/images/`), and the PL-fabric CDC/latency are audited
  (`docs/audit_latency_cdc.md`) — but there is no on-hardware run (no bitstream flashed
  to a board).
- **Cold full-sky acquisition is not real-time per 4 ms window.** A full 32-PRN ×
  ~13-Doppler search is ~416 cells = 231 ms — fine at an operational detection cadence
  (≥ ~250 ms), but it exceeds a single 4 ms coherent window. Continuous per-window
  monitoring is sized for a tracked set of ≤ 7 satellites.
- **Not board-validated.** Synthesis, timing, csim, and the latency/CDC audit are real
  and committed; there is no on-hardware run.

## Legacy streaming front-end (superseded)

The earlier streaming anomaly metric engine (NCO mixer → PRN LFSR → fixed-point
metric engine → alert packer) is superseded by the detector above (README §11). Its
own limitations — a PRN-*like* LFSR rather than a real C/A code, an FFT-free Doppler
proxy, the legacy metric-kernel synthesis numbers (DSP 4 / FF 1735 / LUT 4026 /
BRAM 0 at 5 ns) — applied to that subsystem and do **not** describe the current
detector, which uses real G1/G2 C/A Gold codes and a real FFT.
