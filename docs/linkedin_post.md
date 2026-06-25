# LinkedIn Post

Author: John Bagshaw

---

Most FPGA portfolios show a clean functional demo. That is the one thing that
proves nothing about whether a design survives real hardware.

So I built a GNSS spoofing and jamming detector and verified it the way production
work is actually judged: a streaming HLS and RTL design driven under cycle-level
AXI4-Stream backpressure, with the same scenarios passing under no stalls, random
stalls, and burst backpressure — with identical results.

What it does. Signed complex I/Q streams in. An RTL NCO mixer brings it to
baseband. An RTL PRN generator drives early, prompt, and late correlators. A
fixed-point metric engine computes correlation symmetry, a division-free C/N0
proxy, an FFT-free Doppler-energy proxy, and saturated spoof and jam scores. An
RTL alert packer emits one metrics packet per window with packed alert flags and a
cycle-accurate latency count. It detects wideband jamming, tone jamming, C/N0
degradation, correlation-symmetry distortion, delayed spoof-like replicas, and
Doppler anomalies across eight deterministic scenarios.

Where the engineering actually is.

- The HLS metric engine does the accumulation and the fixed-point scoring, no
  floating point anywhere in the synthesizable path.
- The RTL does everything that has to be cycle-exact: a skid buffer that holds data
  stable under backpressure, an NCO whose phase advances only on an accepted
  handshake, a deterministic LFSR, early/prompt/late alignment, threshold and flag
  packing, and a hardware latency counter.
- One golden C reference defines every metric. The HLS kernel matches it tightly,
  the SystemVerilog model and the Python generator match it too, and a cross-check
  proves the front-ends are bit-for-bit identical before any metric is compared.

The part that matters. The bug class that kills streaming designs is an AXI master
whose valid depends on ready, or whose data is not held stable while stalled. C
simulation cannot see it. So I drove the whole pipeline in XSim under seeded
random and burst backpressure with protocol assertions enabled, and confirmed the
metrics are unchanged by the stalls. The measured per-window latency moved from
about 1000 cycles with no stalls to roughly 2000 under burst backpressure, exactly
as it should, and nothing dropped. That equivalence under backpressure is the
property a functional demo never proves, and it is the whole point.

I did not fake synthesis or timing. Where the full HLS synthesis tool was not
available, I reported no area or frequency numbers and ran the HLS kernel C
simulation against the real vendor fixed-point headers instead. The only latency I
report is the one the hardware counter measured.

This is the kind of evidence that should exist before a company spends interview
cycles on an FPGA or ASIC engineer. It is exactly what ShawSilicon (shawsilicon.ai)
is built to verify: not a resume claim, but a design that holds up cycle by cycle.

Repo and full write-up: github.com/taitashaw/gnss_spoof_jam_detector_hls_rtl

---

## Strongest two opening lines (for reuse)

> Most FPGA portfolios show a clean functional demo. That is the one thing that
> proves nothing about whether a design survives real hardware.
