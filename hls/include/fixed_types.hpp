// ============================================================================
// fixed_types.hpp  --  fixed-point widths + shared integer math primitives
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Dual mode:
//   * Define GNSS_NATIVE_TYPES (the C reference / golden build, plain g++):
//       the fixed-point types collapse to native 64-bit integers. No Xilinx
//       headers required, so the golden model compiles anywhere.
//   * Otherwise (Vitis HLS build): the types are ap_int<> with the widths from
//       the Section 5 fixed-point budget, so synthesis sees exact widths.
//
// Because all metric math is plain integer arithmetic, the native and ap_int
// builds produce bit-identical results as long as the widths below never wrap
// (they are sized with margin in docs/fixed_point_design.md). The HLS testbench
// still applies a small tolerance per the verification strategy.
//
// NO FLOATING POINT in any synthesizable path. Float appears only in optional
// debug prints in the reference model and in Python.
// ============================================================================
#ifndef FIXED_TYPES_HPP
#define FIXED_TYPES_HPP

#include <stdint.h>

#ifdef GNSS_NATIVE_TYPES
  // ---- Golden / reference build: native integers --------------------------
  typedef int16_t  iq_sample_t;   // s16 I/Q sample
  typedef uint32_t power_t;       // I^2 + Q^2 per sample
  typedef int64_t  accum_t;       // power accumulator (>= u48 of range)
  typedef int64_t  corr_accum_t;  // correlation per-tap accumulator (s32 range)
  typedef int64_t  dopp_accum_t;  // doppler cross-product accumulator (s48 range)
  typedef uint32_t metric_t;      // exported metric field (u32)
  typedef uint32_t score_t;       // saturated score (u16 range, stored u32)
  typedef int32_t  config_t;      // reg-bank config word
  typedef int16_t  sin_lut_t;     // Q14 sine LUT entry
  typedef int64_t  wide_t;        // generic wide scratch
#else
  // ---- HLS build: ap_int<> with Section 5 widths --------------------------
  #include "ap_int.h"
  typedef ap_int<16>  iq_sample_t;
  typedef ap_uint<32> power_t;
  typedef ap_int<48>  accum_t;     // power accumulator, u48 budget + sign margin
  typedef ap_int<32>  corr_accum_t;
  typedef ap_int<48>  dopp_accum_t;
  typedef ap_uint<32> metric_t;
  typedef ap_uint<32> score_t;
  typedef ap_int<32>  config_t;
  typedef ap_int<16>  sin_lut_t;
  typedef ap_int<64>  wide_t;
#endif

// ----------------------------------------------------------------------------
// Shared integer math primitives. Written with native 64-bit semantics so the
// reference and HLS builds agree exactly. (ap_int promotes cleanly to these.)
// ----------------------------------------------------------------------------

// Saturate v to symmetric s16 range.
static inline int32_t gnss_sat16(int64_t v) {
    if (v >  32767) return  32767;
    if (v < -32767) return -32767;
    return (int32_t)v;
}

// Clamp v to [lo, hi].
static inline int64_t gnss_clamp(int64_t v, int64_t lo, int64_t hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

// Position of most-significant set bit (0 if x==0, else floor(log2(x))).
static inline int gnss_msb_index(uint64_t x) {
    int idx = 0;
    while (x > 1) { x >>= 1; ++idx; }
    return idx;
}

// Q4 fixed-point log2 proxy: (msb << 4) | (4 fractional bits below msb).
// Deterministic, division-free, monotonic in x. Returns 0 for x==0.
static inline int gnss_log2_fx(uint64_t x) {
    if (x == 0) return 0;
    int msb = gnss_msb_index(x);
    int frac;
    if (msb >= 4) {
        frac = (int)((x >> (msb - 4)) & 0xF); // top 4 bits below the leading 1
    } else {
        frac = (int)((x << (4 - msb)) & 0xF); // small x: shift up into 4 frac bits
    }
    return (msb << 4) | frac;
}

// Arithmetic-shift normalize then clamp to [0, NORM_MAX].
static inline int gnss_norm(int64_t v, int shift, int norm_max) {
    if (v < 0) v = -v;
    int64_t n = v >> shift;
    if (n > norm_max) n = norm_max;
    return (int)n;
}

#endif // FIXED_TYPES_HPP
