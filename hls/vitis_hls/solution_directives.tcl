# ============================================================================
# solution_directives.tcl -- HLS optimization directives
# Author: John Bagshaw   License: MIT (c) 2026 John Bagshaw
#
# The primary directives live INLINE as #pragma in gnss_metric_hls.cpp so the
# intent travels with the code:
#   * #pragma HLS PIPELINE II=1            on the accumulation loop (ACC_LOOP)
#   * #pragma HLS INTERFACE axis           on tap_in / metric_out
#   * #pragma HLS INTERFACE s_axilite      on the scalar config/status ports
#   * #pragma HLS ARRAY_PARTITION complete on blk_sum[] (8 parallel sub-blocks)
#
# This file holds solution-level settings and is the place to add experiment
# directives without editing the source. Guarded so missing labels never abort
# the build on a given tool version.
# ============================================================================

# Keep small loops pipelined; flatten/auto-inline helpers.
catch { config_compile -pipeline_loops 64 }

# Example experiment hooks (commented; enable to explore micro-architecture):
# set_directive_pipeline -II 1 "gnss_metric_hls/ACC_LOOP"
# set_directive_array_partition -type complete -dim 1 "gnss_metric_hls" blk_sum
# set_directive_allocation -limit 2 -type operation "gnss_metric_hls" mul
