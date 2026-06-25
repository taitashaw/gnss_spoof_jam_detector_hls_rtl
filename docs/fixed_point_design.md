# Fixed-Point Design

Author: John Bagshaw — License: MIT (c) 2026 John Bagshaw

No floating point appears in any synthesizable path. Float is used only in the
Python generator and in optional debug prints of the C reference, never in the
metric function body. Every width below is a minimum; widen them if `WINDOW_SIZE`
grows so an accumulator never silently wraps.

## Width budget

| Quantity | Width | Rationale |
|---|---|---|
| iq_sample_t (I, Q) | s16 | input sample format |
| per-sample power I^2 + Q^2 | u32 | (2^15)^2 + (2^15)^2 < 2^31 |
| power accumulator (1024 samples) | u48 | 2^31 x 2^10 = 2^41, margin to 48 |
| correlation per-tap accumulator | s32 | 16b x +/-1 x 1024 -> ~2^26 with sign |
| Doppler cross-product accumulator | s48 | 16b x 16b = 2^31, x1024 -> ~2^41 |
| metric_t (exported metrics) | u32 | packet field width |
| score_t | u16 (0..65535) | scaled/saturated scores |
| sub-block power sum (128 samples) | u41 | 2^31 x 2^7 = 2^38, margin to 41 |

The HLS kernel uses `ap_int`/`ap_uint` at these widths; the C reference uses
64-bit native integers; the SystemVerilog model uses matching reg widths. Because
all three do plain integer arithmetic, they produce identical results as long as
the widths do not wrap, which the budget guarantees.

## Scaling and the NCO

The sine LUT is 64 entries in Q14 (amplitude 2^14 = 16384). The mixer computes
`mixed_I = sat16((I*cos - Q*sin) >> 14)` and `mixed_Q = sat16((I*sin + Q*cos) >> 14)`,
saturating to symmetric s16. The intermediate products are s16 x s16 = s32; the
sum/difference fits s34; the arithmetic right shift by 14 returns to s16 range
before saturation. The exact 64 LUT values are committed identically in the C
reference, the Python generator, and the SystemVerilog package.

## Noise estimate (truncation, not rounding)

The noise floor proxy is the minimum of eight sub-block mean powers. Each
sub-block mean is `sub_block_sum >> 7` (truncating, since 128 = 2^7). The smoothed
estimate is a one-pole IIR, `noise = noise_prev + ((blk_min - noise_prev) >> NOISE_SMOOTH_SHIFT)`
with `NOISE_SMOOTH_SHIFT = 3`, computed in signed arithmetic so the negative delta
shifts arithmetically. On the first window (`noise_prev == 0`) the filter is seeded
directly with `blk_min`. The shift is arithmetic and truncating; this was the one
place where a careless mix of an unsigned operand turned `>>>` into a logical shift
and wrapped the negative delta — the model computes the IIR entirely in signed
locals to avoid it.

## C/N0 proxy (division-free) and its error bound

C/N0 is computed without division as a log-domain ratio. `log2_fx(x)` returns a
Q4 fixed-point base-2 logarithm: the most-significant set-bit position shifted left
by four, ORed with the four bits just below it (a priority encoder plus a bit
extract in hardware). The proxy is
`cn0 = clamp(CN0_K*(log2_fx(corr_prompt) - log2_fx(noise)) + CN0_OFFSET, 0, CN0_MAX)`.
Using the despread prompt-correlation magnitude as the carrier and the noise-floor
estimate as the reference gives the correct monotonicity: a jammer collapses the
correlation and lifts the floor, so the proxy drops. The four fractional bits bound
the per-operand log error to at most 1/16 of an octave, about a 4.4 percent ratio
error, which is far finer than the alert thresholds.

## Correlation accumulation growth

Each correlation tap accumulates `mixed * chip` with `chip` in `{+1, -1}`, so a tap
grows to at most `32767 * 1024` which is about 2^25, comfortably inside s32 with the
sign. The magnitude proxy `|I_corr| + |Q_corr|` peaks near 2^26, inside u32. The
symmetry error is the absolute difference of two such magnitudes and stays in u32.

## Score scaling and saturation

Each anomaly feature is normalized to 0..255 by an arithmetic shift chosen so a
clean link maps near zero and an attack saturates its term (the shifts are tuned on
the eight reference scenarios and documented in `gnss_config.hpp`). The spoof and
jam scores are non-uniform weighted sums of four normalized features each, then
clamped (saturated) to `score_t` (u16). Weights are non-uniform so spoof score is
dominated by the early/late asymmetry and jam score by absolute power, which is
what separates the scenarios cleanly. Saturation is explicit on both score outputs.

## How float is avoided in hardware

The mix uses an integer LUT; the C/N0 ratio uses a bit-position logarithm instead
of a divide; the Doppler proxy uses an integer cross-product instead of an FFT; the
noise reciprocal is replaced by the log-domain difference; and every normalization
is an arithmetic shift. The only place a divide-like operation would naturally
appear, C/N0, is precisely where the log-domain proxy removes it.
