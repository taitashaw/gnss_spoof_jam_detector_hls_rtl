// ============================================================================
// gnss_top_pkg.sv -- shared parameters, typedefs, and the NCO sine LUT
// ----------------------------------------------------------------------------
// Author : John Bagshaw   License : MIT (c) 2026 John Bagshaw
//
// Compiled FIRST (see vivado/compile_order.tcl).
//
// IMPORTANT: the numeric constants here MUST match hls/include/gnss_config.hpp,
// which is the single source of truth. The Python flow parses the .hpp; this
// package is the SystemVerilog mirror. XSim is checked LOOSE against ranges +
// exact alert flags (see docs/verification_strategy.md), and the thresholds
// carry wide margins, so the documented front-end edge approximation in the
// streaming RTL cannot flip a flag.
// ============================================================================
`default_nettype none

package gnss_top_pkg;

    // ---- windowing ----
    localparam int WINDOW_SIZE   = 1024;
    localparam int WINDOW_LOG2   = 10;
    localparam int NUM_SUBBLOCKS = 8;
    localparam int SUBBLOCK_SIZE = 128;
    localparam int SUBBLOCK_LOG2 = 7;
    localparam int NOISE_SMOOTH_SHIFT = 3;

    // ---- NCO / mixer ----
    localparam int NCO_LUT_SIZE       = 64;
    localparam int NCO_LUT_LOG2       = 6;
    localparam int NCO_SCALE          = 14;
    localparam int NCO_PHASE_ACC_BITS = 24;
    localparam int NCO_PHASE_SHIFT    = 18;
    localparam int NCO_QUARTER        = 16;
    localparam int NCO_PHASE_INC_DEFAULT = 262144;
    localparam int IQ_SAT_MAX = 32767;
    localparam int IQ_SAT_MIN = -32767;

    // ---- PRN LFSR ----
    localparam int PRN_LFSR_WIDTH   = 10;
    localparam int PRN_LFSR_MASK    = 1023;
    localparam int PRN_TAP_A        = 9;
    localparam int PRN_TAP_B        = 6;
    localparam int PRN_SEED_DEFAULT = 337;

    // ---- C/N0 proxy (log-domain) ----
    localparam int LOG2_FRAC_BITS  = 4;
    localparam int CN0_K           = 1;
    localparam int CN0_OFFSET      = 256;
    localparam int CN0_MAX         = 1023;
    localparam int CN0_HEALTHY_REF = 200;
    localparam int CN0_ABNORMAL_MAX = 255;

    // ---- score normalization ----
    localparam int NORM_MAX            = 255;
    localparam int SYM_NORM_SHIFT      = 15;
    localparam int DOPP_NORM_SHIFT     = 30;
    localparam int CN0ABN_NORM_SHIFT   = 0;
    localparam int REPL_NORM_SHIFT     = 18;
    localparam int PWR_NORM_SHIFT      = 33;
    localparam int COLLAPSE_NORM_SHIFT = 16;
    localparam int TONE_NORM_SHIFT     = 24;
    localparam longint CORR_PROMPT_REF = 2097152;

    // ---- score weights ----
    localparam int W_SYM      = 8;
    localparam int W_DOP      = 4;
    localparam int W_CN0      = 3;
    localparam int W_REPL     = 2;
    localparam int W_PWR      = 8;
    localparam int W_LOWCN0   = 2;
    localparam int W_COLLAPSE = 2;
    localparam int W_TONE     = 4;
    localparam int SCORE_MAX  = 65535;

    // ---- thresholds ----
    localparam longint POWER_JAM_THRESHOLD      = 64'd150000000000;
    localparam int     CN0_DROP_THRESHOLD       = 180;
    localparam longint SYMMETRY_THRESHOLD       = 64'd2000000;
    localparam longint DOPPLER_ENERGY_THRESHOLD = 64'd20000000000;
    localparam int     SPOOF_SCORE_THRESHOLD    = 500;
    localparam int     JAM_SCORE_THRESHOLD      = 500;

    // ---- alert flag bit positions ----
    localparam int FLAG_HIGH_POWER_JAM   = 0;
    localparam int FLAG_CN0_DROP         = 1;
    localparam int FLAG_CORR_ASYMMETRY   = 2;
    localparam int FLAG_DOPPLER_ANOMALY  = 3;
    localparam int FLAG_SPOOF_SCORE_HIGH = 4;
    localparam int FLAG_JAM_SCORE_HIGH   = 5;
    localparam int FLAG_MALFORMED_PACKET = 6;
    localparam int FLAG_RESERVED         = 7;

    localparam int PKT_STATUS_OK        = 0;
    localparam int PKT_STATUS_MALFORMED = 1;

    // ---- tapped-stream packing widths (mixed_i,mixed_q,e,p,l,index,last) ----
    // 16 + 16 + 1 + 1 + 1 + 11 = 46 data bits (+ tlast carried separately)
    localparam int TAP_W = 46;

    // ---- metrics output bus packing (single wide AXIS beat per window) ----
    // One metrics packet = one wide AXIS beat. Field offsets (LSB-first) are the
    // single source of truth for gnss_alert_packer.sv AND tb_gnss_top.sv.
    localparam int METRIC_W       = 512;
    localparam int M_WINDOW_ID_O  = 0;    // [31:0]
    localparam int M_POWER_O      = 32;   // [79:32]   48b
    localparam int M_NOISE_O      = 80;   // [111:80]
    localparam int M_CN0_O        = 112;  // [143:112]
    localparam int M_CP_O         = 144;  // [175:144]
    localparam int M_CE_O         = 176;  // [207:176]
    localparam int M_CL_O         = 208;  // [239:208]
    localparam int M_SYM_O        = 240;  // [271:240]
    localparam int M_DOPP_O       = 272;  // [319:272] 48b
    localparam int M_PJUMP_O      = 320;  // [367:320] 48b
    localparam int M_SPOOF_O      = 368;  // [399:368]
    localparam int M_JAM_O        = 400;  // [431:400]
    localparam int M_FLAGS_O      = 432;  // [439:432] 8b
    localparam int M_LAT_O        = 440;  // [471:440]
    localparam int M_SCNT_O       = 472;  // [503:472]
    localparam int M_STATUS_O     = 504;  // [511:504] 8b

    // Deterministic 64-entry Q14 sine LUT. MUST equal NCO_SIN_LUT in
    // gnss_metric_ref.cpp and NCO_SIN_LUT in scripts/gnss_cfg.py.
    function automatic signed [15:0] nco_sin(input int unsigned idx);
        logic signed [15:0] lut [0:63];
        lut = '{
            16'sd0,    16'sd1606,  16'sd3196,  16'sd4756,  16'sd6270,  16'sd7723,
            16'sd9102, 16'sd10394, 16'sd11585, 16'sd12665, 16'sd13623, 16'sd14449,
            16'sd15137,16'sd15679, 16'sd16069, 16'sd16305, 16'sd16384, 16'sd16305,
            16'sd16069,16'sd15679, 16'sd15137, 16'sd14449, 16'sd13623, 16'sd12665,
            16'sd11585,16'sd10394, 16'sd9102,  16'sd7723,  16'sd6270,  16'sd4756,
            16'sd3196, 16'sd1606,  16'sd0,    -16'sd1606, -16'sd3196, -16'sd4756,
           -16'sd6270,-16'sd7723, -16'sd9102, -16'sd10394,-16'sd11585,-16'sd12665,
           -16'sd13623,-16'sd14449,-16'sd15137,-16'sd15679,-16'sd16069,-16'sd16305,
           -16'sd16384,-16'sd16305,-16'sd16069,-16'sd15679,-16'sd15137,-16'sd14449,
           -16'sd13623,-16'sd12665,-16'sd11585,-16'sd10394,-16'sd9102, -16'sd7723,
           -16'sd6270, -16'sd4756, -16'sd3196, -16'sd1606
        };
        return lut[idx[5:0]];
    endfunction

endpackage

`default_nettype wire
