// ============================================================================
// axis_types.hpp  --  AXI4-Stream side-channel types for the HLS kernel
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Uses ap_axiu<> from ap_axi_sdata.h (Vitis HLS). Only included by the HLS
// build; the native reference model does not need AXI types.
//
//   axis_iq_t     : raw 32-bit I/Q input  (tdata[31:16]=I, tdata[15:0]=Q)
//   axis_tapped_t : tapped-stream beat packed into a 64-bit tdata word
//   axis_metric_t : one 32-bit metric word (the kernel streams the packet out
//                   as a short burst of metric words; see gnss_metric_hls.cpp)
//
// Tapped-stream packing (64-bit tdata), LSB first:
//   [15:0]  mixed_I (s16)
//   [31:16] mixed_Q (s16)
//   [32]    chip_E sign bit (1 -> +1, 0 -> -1)
//   [33]    chip_P sign bit
//   [34]    chip_L sign bit
//   [63:48] sample_index (u16)
// tlast marks the final sample of the window.
// ============================================================================
#ifndef AXIS_TYPES_HPP
#define AXIS_TYPES_HPP

#ifndef GNSS_NATIVE_TYPES

#include "ap_int.h"
#include "ap_axi_sdata.h"
#include "hls_stream.h"

// Raw I/Q in: 32b data, no user/id/dest, keep+strb present per ap_axiu default.
typedef ap_axiu<32, 0, 0, 0> axis_iq_t;

// Tapped stream: 64b data carrying mixed I/Q + E/P/L chip signs + index.
typedef ap_axiu<64, 0, 0, 0> axis_tapped_t;

// Metric output word: 32b data; tlast marks the last word of a packet.
typedef ap_axiu<32, 0, 0, 0> axis_metric_t;

// Wide metric bundle: one packed beat per window (no flags/latency/status --
// those are added by the RTL gnss_alert_packer). Field offsets below.
typedef ap_axiu<512, 0, 0, 0> axis_metric_pkt_t;

// Metric-bundle field offsets (LSB-first) -- shared by the kernel and its tb.
#define B_WINDOW_O 0    // [31:0]
#define B_POWER_O  32   // [79:32]   48b
#define B_NOISE_O  80   // [111:80]
#define B_CN0_O    112  // [143:112]
#define B_CP_O     144  // [175:144]
#define B_CE_O     176  // [207:176]
#define B_CL_O     208  // [239:208]
#define B_SYM_O    240  // [271:240]
#define B_DOPP_O   272  // [319:272] 48b
#define B_PJUMP_O  320  // [367:320] 48b
#define B_SPOOF_O  368  // [399:368]
#define B_JAM_O    400  // [431:400]
#define B_SCNT_O   432  // [463:432]

// ---- Tapped-stream field helpers (keep packing in ONE place) --------------
static inline ap_uint<64> pack_tapped(int16_t mixed_i, int16_t mixed_q,
                                      int chip_e, int chip_p, int chip_l,
                                      int sample_index) {
    ap_uint<64> w = 0;
    w(15, 0)  = (ap_uint<16>)(uint16_t)mixed_i;
    w(31, 16) = (ap_uint<16>)(uint16_t)mixed_q;
    w[32] = (chip_e > 0) ? 1 : 0;
    w[33] = (chip_p > 0) ? 1 : 0;
    w[34] = (chip_l > 0) ? 1 : 0;
    w(63, 48) = (ap_uint<16>)sample_index;
    return w;
}

static inline void unpack_tapped(ap_uint<64> w, int16_t &mixed_i,
                                 int16_t &mixed_q, int &chip_e, int &chip_p,
                                 int &chip_l, int &sample_index) {
    mixed_i = (int16_t)(uint16_t)w(15, 0);
    mixed_q = (int16_t)(uint16_t)w(31, 16);
    chip_e  = w[32] ? 1 : -1;
    chip_p  = w[33] ? 1 : -1;
    chip_l  = w[34] ? 1 : -1;
    sample_index = (int)(uint16_t)w(63, 48);
}

#endif // !GNSS_NATIVE_TYPES
#endif // AXIS_TYPES_HPP
