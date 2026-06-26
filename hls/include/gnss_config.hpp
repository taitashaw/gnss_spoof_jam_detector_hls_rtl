// ============================================================================
// gnss_config.hpp  --  SINGLE SOURCE OF TRUTH for all GNSS detector constants
// ----------------------------------------------------------------------------
// Project : gnss_spoof_jam_detector_hls_rtl  (Project 1)
// Author  : John Bagshaw
// License : MIT (c) 2026 John Bagshaw
//
// Every numeric constant the detector depends on lives here. The C reference
// model, the HLS kernel, the Python vector generator / golden sim, and the
// SystemVerilog behavioral model all reference THESE numbers.
//
//   * C++ / HLS  include this header directly.
//   * Python     parses it with scripts/gnss_cfg.py (regex over the
//                "static const <int-type> NAME = VALUE;" lines below).
//   * SV         mirrors the values in rtl/gnss/gnss_top_pkg.sv; that file
//                carries a header comment requiring it to match this one.
//                (XSim is checked LOOSE against ranges + exact flags, so the
//                SV path tolerates the documented front-end edge difference.)
//
// To keep the Python parser trivial, the tunable constants below are written
// as plain integer literals in "static const <type> NAME = VALUE;" form.
// Do NOT introduce arithmetic expressions on those lines.
// ============================================================================
#ifndef GNSS_CONFIG_HPP
#define GNSS_CONFIG_HPP

// ===========================================================================
// CURRENT DETECTOR  --  DBZP ddMap + own fixed-point FFT + early/late SQM
//   These are the parameters of the live detection core
//   (hls/src/ddmap_sqm_hls.cpp + hls/src/fft_fixed.hpp). The detector defines
//   them inline in those files; they are restated here for reference. See
//   docs/architecture.md, docs/fixed_point_design.md, docs/fft_fixed_design.md.
// ===========================================================================
static const int DDMAP_FFT_N        = 2048; // FFT length (radix-2 DIT, 11 stages)
static const int DDMAP_FFT_LOG2N    = 11;   // log2(FFT_N)
static const int DDMAP_CA_LEN       = 1023; // GPS L1 C/A code length (chips)
static const int DDMAP_SAMP_PER_CHIP= 2;    // samples per chip -> NS = 2046
static const int DDMAP_NS           = 2046; // used samples per 1 ms block
static const int DDMAP_N_BLK        = 4;    // coherent 1 ms blocks per ddMap cell
static const int DDMAP_PROD_SHIFT   = 14;   // spectral-product rescale = 2^14 (shift)
static const int DDMAP_SQM_MAX_LANES= 4;    // partial-max peak-search lanes
// Spoof decision: early/late distortion |E-L|/(E+L) >= threshold (Q16 output).
// TEXBAT-validated threshold = 0.50 (50% in Q16 = 32768); 0% clean false-alarm,
// 100% ds7 detection (docs/single_pass_detection.md). The host/eval applies it.
static const int DDMAP_DISTORTION_THR_Q16 = 32768; // 0.50 in Q16

// ===========================================================================
// LEGACY STREAMING FRONT-END  (superseded -- NOT the current detector)
//   The constants below configure the older streaming anomaly metric engine
//   (NCO mixer -> PRN LFSR / E-P-L tap -> metric engine -> alert packer). They
//   are retained only for that legacy subsystem (rtl/gnss/*, the C reference,
//   the SV model) and are not used by the ddMap/SQM detector above. See README
//   section 11.
// ===========================================================================

// ---------------------------------------------------------------------------
// Windowing  (legacy)
// ---------------------------------------------------------------------------
static const int WINDOW_SIZE      = 1024; // complex samples per metrics packet
static const int WINDOW_LOG2      = 10;   // log2(WINDOW_SIZE)
static const int NUM_SUBBLOCKS    = 8;    // noise estimate sub-blocks
static const int SUBBLOCK_SIZE    = 128;  // WINDOW_SIZE / NUM_SUBBLOCKS
static const int SUBBLOCK_LOG2    = 7;    // log2(SUBBLOCK_SIZE)
static const int NOISE_SMOOTH_SHIFT = 3;  // noise = prev + ((blk_min-prev)>>3)

// ---------------------------------------------------------------------------
// NCO / mixer  (front-end, replicated in Python + RTL)
// ---------------------------------------------------------------------------
static const int NCO_LUT_SIZE       = 64;     // entries in the sine LUT
static const int NCO_LUT_LOG2       = 6;      // log2(NCO_LUT_SIZE)
static const int NCO_SCALE          = 14;     // LUT amplitude is Q14 (2^14)
static const int NCO_PHASE_ACC_BITS = 24;     // phase accumulator width
static const int NCO_PHASE_SHIFT    = 18;     // ACC_BITS - LUT_LOG2 (index pick)
static const int NCO_QUARTER        = 16;     // NCO_LUT_SIZE/4 -> cos = sin+quarter
static const int NCO_PHASE_INC_DEFAULT = 262144; // 1<<18 : one LUT step / sample
static const int IQ_SAT_MAX         = 32767;  // s16 saturate high
static const int IQ_SAT_MIN         = -32767; // s16 saturate low (symmetric)

// ---------------------------------------------------------------------------
// PRN / LFSR  (front-end, replicated in Python + RTL)
//   10-bit Fibonacci LFSR, primitive polynomial x^10 + x^7 + 1.
//   out_bit = state & 1 ; chip = out_bit ? +1 : -1
//   feedback = ((state>>9) ^ (state>>6)) & 1 ; state=((state<<1)|fb)&0x3FF
//   LFSR is reset to PRN_SEED_DEFAULT at each window start (window independence).
//   E/P/L taps use the window-local wrap definition in the GOLDEN model:
//     prompt = c[n], early = c[(n+1)%N], late = c[(n-1)%N].
// ---------------------------------------------------------------------------
static const int PRN_LFSR_WIDTH   = 10;
static const int PRN_LFSR_MASK    = 1023;  // (1<<10)-1
static const int PRN_TAP_A        = 9;     // 0-indexed feedback tap
static const int PRN_TAP_B        = 6;     // 0-indexed feedback tap
static const int PRN_SEED_DEFAULT = 337;   // nonzero seed (0x151)

// ---------------------------------------------------------------------------
// C/N0 proxy  (division-free log-domain despread-carrier-to-noise ratio)
//   log2_fx(x) = (msb(x) << 4) | (next 4 bits below msb)   [Q4 log2]
//   carrier_proxy = corr_prompt   (despread signal magnitude |I|+|Q|)
//   cn0_proxy = clamp( CN0_K*(log2_fx(carrier) - log2_fx(noise)) + CN0_OFFSET,
//                      0, CN0_MAX )
//   Higher cn0_proxy = healthier link. cn0_drop alert when below threshold.
//   Error bound: 4 fractional log2 bits -> <= 1/16 octave (~4.4% ratio) error.
// ---------------------------------------------------------------------------
static const int LOG2_FRAC_BITS = 4;
static const int CN0_K          = 1;
static const int CN0_OFFSET     = 256;
static const int CN0_MAX        = 1023;
static const int CN0_HEALTHY_REF = 200; // cn0_abnormal = clamp(REF-cn0,0,255)
static const int CN0_ABNORMAL_MAX = 255;

// ---------------------------------------------------------------------------
// Score normalization  (fixed-point shift-normalize to 0..NORM_MAX)
//   norm_X(v) = clamp(v >> SHIFT_X, 0, NORM_MAX)
//   These shifts were chosen empirically from the 8 reference scenarios so that
//   clean stays low and each attack lifts its corresponding term. See
//   docs/fixed_point_design.md for the measured magnitudes behind each shift.
// ---------------------------------------------------------------------------
static const int NORM_MAX            = 255;
static const int SYM_NORM_SHIFT      = 15;  // symmetry_error  -> norm
static const int DOPP_NORM_SHIFT     = 30;  // doppler_energy   -> norm
static const int CN0ABN_NORM_SHIFT   = 0;   // cn0_abnormal     -> norm (already small)
static const int REPL_NORM_SHIFT     = 18;  // delayed_replica  -> norm
static const int PWR_NORM_SHIFT      = 33;  // power_estimate   -> norm
static const int COLLAPSE_NORM_SHIFT = 16;  // corr_collapse    -> norm
static const int TONE_NORM_SHIFT     = 24;  // elevated noise floor -> norm

// Reference levels for "collapse / excess" derived metrics.
//   corr_collapse        = max(0, CORR_PROMPT_REF - corr_prompt)
//   tone_or_wideband_sig = noise_estimate (elevated noise floor under jamming)
static const int CORR_PROMPT_REF = 2097152; // expected clean prompt mag (~2^21)

// ---------------------------------------------------------------------------
// Score weights (fixed-point weighted sum, then saturate to score_t u16)
//   spoof_score = sat( W_SYM*nSym + W_DOP*nDop + W_CN0*nCn0 + W_REPL*nRepl )
//   jam_score   = sat( W_PWR*nPwr + W_LOWCN0*nLow + W_COLLAPSE*nCol + W_TONE*nTone )
// ---------------------------------------------------------------------------
// Weights are non-uniform so each score is dominated by its most discriminative
// feature: spoof_score by the early/late asymmetry, jam_score by absolute power.
// (The spec's 4/4/4/4 is the starting point; these were tuned on the 8 scenarios.)
static const int W_SYM      = 8;
static const int W_DOP      = 4;
static const int W_CN0      = 3;
static const int W_REPL     = 2;
static const int W_PWR      = 8;
static const int W_LOWCN0   = 2;
static const int W_COLLAPSE = 2;
static const int W_TONE     = 4;
static const int SCORE_MAX  = 65535; // score_t saturation (u16)

// ---------------------------------------------------------------------------
// Alert thresholds  (defaults; also live in the reg bank as run-time config)
//   Tuned from the 8 reference scenarios so clean raises no attack flag and
//   each attack raises its expected flag(s). See expected_metrics.json.
// ---------------------------------------------------------------------------
static const long POWER_JAM_THRESHOLD      = 150000000000; // power_estimate high
static const int CN0_DROP_THRESHOLD        = 180;        // cn0_proxy below -> drop
static const int SYMMETRY_THRESHOLD        = 2000000;    // symmetry_error above
static const long DOPPLER_ENERGY_THRESHOLD = 20000000000; // doppler_energy above
static const int SPOOF_SCORE_THRESHOLD     = 500;        // spoof_score above
static const int JAM_SCORE_THRESHOLD       = 500;        // jam_score above

// ---------------------------------------------------------------------------
// alert_flags bit positions
// ---------------------------------------------------------------------------
static const int FLAG_HIGH_POWER_JAM      = 0;
static const int FLAG_CN0_DROP            = 1;
static const int FLAG_CORR_ASYMMETRY      = 2;
static const int FLAG_DOPPLER_ANOMALY     = 3;
static const int FLAG_SPOOF_SCORE_HIGH    = 4;
static const int FLAG_JAM_SCORE_HIGH      = 5;
static const int FLAG_MALFORMED_PACKET    = 6;
static const int FLAG_RESERVED            = 7;

// ---------------------------------------------------------------------------
// packet_status codes
// ---------------------------------------------------------------------------
static const int PKT_STATUS_OK        = 0;
static const int PKT_STATUS_MALFORMED = 1;

#endif // GNSS_CONFIG_HPP
