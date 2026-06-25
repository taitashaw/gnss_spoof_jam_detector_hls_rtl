# Real-Data Validation: TEXBAT (ds2 and ds7)

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

This runs the accelerator's metric pipeline over **real recorded GPS spoofing
data** from the Texas Spoofing Test Battery (TEXBAT), not synthetic and not
re-transmitted. It reports what the data actually shows, including a null result.

## Scope statement (read first)

This is a streaming **pre-tracking anomaly accelerator** whose despreading code is
a **PRN-like LFSR**, not a full GPS C/A tracking receiver. It does **not** acquire
or track the real GPS C/A Gold codes in the TEXBAT recordings. The claim here is
narrow and honest: do the anomaly metrics **respond** at the documented attack
onset on real recorded spoofing data? It is **not** a receiver-grade detection-rate
claim.

A direct consequence, confirmed by the data below: the correlation-based metrics
(`corr_prompt/early/late`, `symmetry_error`) do **not** provide despread-based
spoof discrimination, because the PRN-like LFSR does not correlate with the real
C/A code. Where they move, they move because they scale with overall signal
amplitude, not because of code despreading. The metrics that can respond to a
real attack here are the **amplitude/structure** ones — `power_estimate` and
`doppler_energy`. Full C/A acquisition and tracking is the next development step
required for receiver-grade detection.

## What TEXBAT is

TEXBAT (UT Austin Radionavigation Laboratory) is a public set of recorded RF
captures: a clean interval followed by a live GPS L1 C/A spoofing attack, recorded
at complex baseband for repeatable, standardized evaluation of spoofing detectors.

Citation: T. E. Humphreys, J. A. Bhatti, D. P. Shepard, K. D. Wesson, "The Texas
Spoofing Test Battery: Toward a Standard for Evaluating GPS Signal Authentication
Techniques," Proc. ION GNSS+ 2012. Source: radionavlab.ae.utexas.edu/texbat.

- **ds2** — static receiver, overpowered time-push spoofing (carrier-phase
  unaligned, roughly a 10 dB power advantage): an intermediate-difficulty attack.
- **ds7** — static receiver, matched-power security-code-estimation-and-replay
  (SCER) spoofing: the hardest TEXBAT class, designed to be power-matched and
  code-aligned so power-based detection has nothing obvious to latch onto.

## Confirmed data format (empirical, not assumed)

`scripts/texbat_probe.py` read the first 1 MiB of each file and confirmed the byte
layout against candidate rates and both endiannesses:

| File | Format | Rate | Duration |
|---|---|---|---|
| ds2.bin | int16 complex, little-endian, I/Q interleaved (I first), 16-bit | 25.000 Msps | 457.18 s |
| ds7.bin | int16 complex, little-endian, I/Q interleaved (I first), 16-bit | 25.000 Msps | 470.00 s |

Little-endian is unambiguous: it decodes to non-saturated samples (rms ~844 / 2357,
no railing), whereas big-endian rails at +/-32768 (garbage). 46.08 Msps was tested
and rejected (it implies ~248 s, physically wrong); 25 Msps is the documented and
confirmed rate.

## Method

For each file, two slices of 128 windows (`WINDOW_SIZE` = 1024 complex samples each;
5.24 ms of signal) were read directly from the local `.bin` via byte-offset seek —
the multi-GB files are never loaded whole and never committed.

- **clean** slice at t = 20 s (well before the documented ~100 s spoofing onset).
- **spoofed** slice after onset: ds2 at t = 150 s; ds7 at t = 250 s, chosen safely
  deep inside the SCER attack interval (ds7 runs to 470 s).

No decimation and no rescaling are applied: the repo is a rate-agnostic streaming
accelerator and the native TEXBAT int16 samples already match the s16 AXIS contract
(`tdata[31:16]=I`, `tdata[15:0]=Q`) and sit well inside int16 range. The repo's own
mix/PRN front-end produces `tapped_stream.txt` so the HLS C-sim path stays
consistent with the RTL path (the front-end cross-check passes on all four slices).

Both paths were run on every slice: the C golden model and the cycle-accurate
XSim flow (`tb_gnss_top`). XSim passed all four slices (128 metrics packets each,
scoreboard clean) and its metrics are **bit-exact** with the C reference, so the
real recorded data ran end-to-end through the RTL pipeline, not just the software
model. The values below are the mean over the 128 windows.

## Results (real run, mean over 128 windows; C golden model, XSim bit-exact)

### ds2 — overpowered time-push

| Metric | clean | spoofed | delta |
|---|---|---|---|
| power_estimate | 7.24e8 | 2.35e9 | **+224.9%** |
| doppler_energy | 3.50e8 | 9.04e8 | **+158.2%** |
| spoof_score | 51.0 | 99.0 | +94.1% |
| jam_score | 95.0 | 124.8 | +31.3% |
| corr_prompt | 31290 | 56572 | +80.8% |
| corr_early | 30768 | 54884 | +78.4% |
| corr_late | 31483 | 56037 | +78.0% |
| symmetry_error | 19299 | 30569 | +58.4% |
| cn0_proxy | 183.8 | 168.2 | -8.5% |

### ds7 — matched-power SCER (hardest class)

| Metric | clean | spoofed | delta |
|---|---|---|---|
| power_estimate | 5.65e9 | 5.93e9 | +4.8% |
| doppler_energy | 2.75e9 | 2.87e9 | +4.4% |
| spoof_score | 137.4 | 144.2 | +5.0% |
| jam_score | 142.1 | 146.3 | +3.0% |
| symmetry_error | 45399 | 47522 | +4.7% |
| corr_prompt | 85673 | 79630 | -7.1% |
| corr_early | 84307 | 85569 | +1.5% |
| corr_late | 86670 | 88195 | +1.8% |
| cn0_proxy | 159.2 | 157.1 | -1.3% |

## What separated, what did not

- **ds2:** `power_estimate` (+225%) and `doppler_energy` (+158%) respond strongly
  and unambiguously at the spoofing onset on real recorded data; the saturated
  `spoof_score` nearly doubles. This is a clear positive response — the overpowered
  spoofer's added power and signal structure show up exactly where they should.
- **ds2 correlations:** `corr_prompt/early/late` all rise together (~78-81%) and
  `symmetry_error` rises ~58%, but this is amplitude scaling, **not** despread
  discrimination — all three taps move in lockstep because the PRN-like LFSR is not
  correlating with the real C/A code. This is the predicted limitation, visible in
  the data.
- **ds7:** every metric moves **under 8%** (power +4.8%, doppler +4.4%, scores
  +3-5%); `corr_prompt` even drops slightly. This is a **null result** — the
  matched-power SCER attack produces no clear anomaly in these metrics. That is the
  honest, expected outcome for the hardest TEXBAT class against an amplitude/energy
  detector.

## Is ds7 harder than ds2?

**Yes, decisively.** ds2's overpowered attack lifts `power_estimate` by +225%;
ds7's matched-power SCER lifts it by +4.8%. The accelerator clearly responds to
ds2 and does **not** clearly flag ds7. This matches TEXBAT's documented difficulty
ordering (SCER is the hardest class) and is the expected ceiling for a power/energy
anomaly detector without code-level (C/A acquisition) discrimination.

## Conclusion and next step

On real recorded spoofing data, the amplitude/energy metrics respond strongly to the
overpowered ds2 attack and do not separate the matched-power ds7 (SCER) attack. The
correlation metrics do not provide despread-based discrimination because the front
end uses a PRN-like LFSR rather than the GPS C/A Gold codes. The next development
step for receiver-grade detection is full C/A acquisition and tracking (correct
per-satellite Gold code, code/carrier alignment), after which the early/prompt/late
symmetry and C/N0 metrics would carry real despread information.

## Data provenance (large files never committed)

| File | Path | SHA256 |
|---|---|---|
| ds2.bin | ~/Downloads/ds2.bin (45,717,913,600 bytes) | 65bfba9bbb8643c1f6b8f1a48bdef8adfc0e787458f0c5b0cb54ca92977bed5e |
| ds7.bin | ~/Downloads/ds7.bin (47,000,141,168 bytes) | 64a0e85ca72cb8391ba912bd07ad0f921555d9627e793b4e363d316992add0c5 |

The `.bin` files (~43 GB each) are referenced by path + SHA256 + citation and are
**never committed**. Each `vectors/texbat_*/metadata.json` records the source URL,
citation, SHA256, byte offset, slice duration, and the confirmed format.
