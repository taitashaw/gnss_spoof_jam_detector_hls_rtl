// ============================================================================
// gnss_types.hpp  --  metrics packet struct shared by the kernel and the ref
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// One gnss_metrics_t is produced per input window. The field set matches the
// Section 4 output packet exactly; gnss_alert_packer.sv packs the same fields
// onto the AXI4-Stream metrics output in RTL.
// ============================================================================
#ifndef GNSS_TYPES_HPP
#define GNSS_TYPES_HPP

#include "fixed_types.hpp"

// Tapped-stream beat: the metric engine's input element (Section 2 contract).
//   mixed_I, mixed_Q : s16 NCO-mixed sample
//   chip_e/p/l       : early / prompt / late chip signs, encoded {0 -> -1, 1 -> +1}
//   sample_index     : 0..WINDOW_SIZE-1 within the window
//   last             : 1 on the final sample of the window
struct tapped_beat_t {
    iq_sample_t mixed_i;
    iq_sample_t mixed_q;
    int         chip_e;   // +1 or -1
    int         chip_p;   // +1 or -1
    int         chip_l;   // +1 or -1
    int         sample_index;
    int         last;
};

// Metrics packet (Section 4). Plain-integer fields so the struct is portable
// across the native reference build and the HLS build.
struct gnss_metrics_t {
    uint32_t window_id;
    uint64_t power_estimate;     // u48 in HW, widened here
    uint32_t noise_estimate;
    uint32_t cn0_proxy;
    uint32_t corr_prompt;
    uint32_t corr_early;
    uint32_t corr_late;
    uint32_t symmetry_error;
    uint64_t doppler_energy;     // u48 in HW, widened here
    uint64_t power_jump_metric;  // |power - power_prev|
    uint32_t spoof_score;
    uint32_t jam_score;
    uint32_t alert_flags;
    uint32_t latency_cycles;
    uint32_t sample_count;
    uint32_t packet_status;
};

#endif // GNSS_TYPES_HPP
