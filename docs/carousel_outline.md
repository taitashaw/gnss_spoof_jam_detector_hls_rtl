# Carousel Outline (10 slides)

Author: John Bagshaw

Design notes: no emoji, em-dash only, ShawSilicon as the only company reference.
Keep one idea per slide and let the verification carry the story.

---

## Slide 1 — Title

I built a GNSS spoofing detector that behaves like hardware, not a toy demo.

Streaming HLS plus RTL, verified under cycle-level AXI4-Stream backpressure.
John Bagshaw.

## Slide 2 — The bench

Target: Zynq UltraScale plus, ZCU104 class. A GNSS RF front-end over FMC and a GPS
antenna are the eventual bench. The design is simulation-first and runs today from
generated synthetic I/Q, structured so a real ADC stream drops in unchanged.

## Slide 3 — The input

Signed complex I/Q streams. A 32-bit AXI4-Stream: I in the high half, Q in the low
half, tlast on the last sample of each window. This is the contract a real ADC
front-end will satisfy.

## Slide 4 — The RTL path

An NCO mixer brings the signal to baseband — its phase accumulator advances only on
an accepted handshake. A PRN LFSR drives early, prompt, and late correlator taps.
Deterministic, cycle-exact, reproducible every run.

## Slide 5 — The HLS path

The metric engine: early/prompt/late correlation, a division-free C/N0 proxy, an
FFT-free Doppler-energy proxy, and saturated spoof and jam scores. Fixed-point
throughout, no floating point in the synthesizable path.

## Slide 6 — The bug class

AXI backpressure drops data if VALID is wrong. If valid depends on ready, or data
is not held stable while stalled, a streaming design silently corrupts. C
simulation cannot see any of it.

## Slide 7 — The verification

HLS C simulation proves the math. XSim cycle simulation proves the hardware: the
full pipeline driven under seeded random and burst backpressure, with protocol
assertions enabled.

## Slide 8 — The result

Alert packets with packed flags, saturated scores, and a cycle-accurate latency
count. The same eight scenarios pass with identical metrics under no stalls,
random stalls, and burst backpressure. Latency grew from about 1000 to about 2000
cycles under backpressure, and nothing dropped.

## Slide 9 — What this proves

A real FPGA engineer is the one whose design holds up cycle by cycle under
backpressure, not the one with a clean waveform on a slide. One golden model
defines every metric; the HLS kernel, the RTL model, and the generator all match
it. No faked synthesis, no invented timing.

## Slide 10 — Why ShawSilicon

ShawSilicon (shawsilicon.ai) verifies engineers before companies interview them —
with exactly this kind of evidence: a design proven under real conditions, not a
resume claim. Repo: github.com/taitashaw/gnss_spoof_jam_detector_hls_rtl
