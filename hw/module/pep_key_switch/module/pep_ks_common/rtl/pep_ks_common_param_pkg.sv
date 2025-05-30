// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Package containing common localparams used in pep_key_switch.
// ==============================================================================================

package pep_ks_common_param_pkg;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import pep_ks_common_definition_pkg::*;

  // Maximum number of PBS per batch
  export pep_ks_common_definition_pkg::LBX;
  export pep_ks_common_definition_pkg::LBY;
  export pep_ks_common_definition_pkg::LBZ;

  // ------------------------------------------------------------------------------------------- --
  // Derived localparam
  // ------------------------------------------------------------------------------------------- --
  // Total number of coefficients
  localparam int LB               = LBX*LBY*LBZ;
  // A processing block is composed of LBX x LBY elements.
  localparam int KS_BLOCK_LINE_NB = (BLWE_K + LBY-1) / LBY;
  localparam int KS_BLOCK_COL_NB  = (LWE_K_P1 + LBX-1) / LBX;
  localparam int KS_LINE_NB       = KS_BLOCK_LINE_NB * LBY;
  localparam int KS_COL_NB        = KS_BLOCK_COL_NB * LBX;
  // Decomposed BLWE coefficient size (counting all the levels)
  localparam int KS_DECOMP_W      = KS_L * (KS_B_W+1); // Signed values

  // Since we are processing LBZ levels in parallel. Gives the local number of "level groups"
  localparam int KS_LG_NB         = (KS_L + LBZ-1) / LBZ;

  localparam int OUT_FIFO_DEPTH   = 4; // OUT_FIFO_DEPTH * LBX LWE coefficients stored per batch
  localparam int OUT_FIFO_DEPTH_W = $clog2(OUT_FIFO_DEPTH) == 0 ? 1 : $clog2(OUT_FIFO_DEPTH);

  // ------------------------------------------------------------------------------------------- --
  // Counter size
  // ------------------------------------------------------------------------------------------- --
  localparam int LB_W  = $clog2(LB)  == 0 ? 1 : $clog2(LB);
  localparam int LBX_W = $clog2(LBX) == 0 ? 1 : $clog2(LBX);
  localparam int LBY_W = $clog2(LBY) == 0 ? 1 : $clog2(LBY);
  localparam int LBZ_W = $clog2(LBZ) == 0 ? 1 : $clog2(LBZ);

  localparam int KS_BLOCK_LINE_W  = $clog2(KS_BLOCK_LINE_NB) == 0 ? 1 : $clog2(KS_BLOCK_LINE_NB);
  localparam int KS_BLOCK_COL_W   = $clog2(KS_BLOCK_COL_NB) == 0 ? 1 : $clog2(KS_BLOCK_COL_NB);
  localparam int KS_LINE_W        = $clog2(KS_LINE_NB) == 0 ? 1 : $clog2(KS_LINE_NB);
  localparam int KS_COL_W         = $clog2(KS_COL_NB) == 0 ? 1 : $clog2(KS_COL_NB);
  localparam int KS_LG_W          = $clog2(KS_LG_NB) == 0 ? 1 : $clog2(KS_LG_NB);

  // ------------------------------------------------------------------------------------------- --
  // Mean compensation configuration
  // ------------------------------------------------------------------------------------------- --
  // Mean correction related
  localparam logic [127:0] KS_MAX_ABS_ERROR = (2**(MOD_KSK_W - LWE_COEF_W - 1) * LWE_K);
  localparam int unsigned KS_MAX_ERROR_W    = unsigned'($clog2(KS_MAX_ABS_ERROR+1) + 1); // The mod_switch_error is signed

  // The KS key mean is encoded in fixed point. The final encoded value is:
  //  KS_KEY_MEAN * 2**-KS_KEY_MEAN_F
  localparam real         KS_KEY_MEAN_R = 0.5;
  localparam int unsigned KS_KEY_MEAN_W = 1;
  localparam int unsigned KS_KEY_MEAN_F = 1; // Fixed point location index
  localparam int unsigned KS_KEY_MEAN   = KS_KEY_MEAN_R * (1 << KS_KEY_MEAN_F);
  // Note: An implicit convertion from a floating point value to an integer is implicitly
  // rounded as stated in the system verilog standard.

  // ------------------------------------------------------------------------------------------- --
  // type
  // ------------------------------------------------------------------------------------------- --
  typedef struct packed {
    logic [PID_W-1:0]            first_pid;  // Use in IPIP
    logic [TOTAL_BATCH_NB_W-1:0] batch_id;    // Use in BPIP
    logic [TOTAL_BATCH_NB-1:0]   batch_id_1h; // Use in BPIP
    logic [BPBS_ID_W-1:0]        pbs_cnt_max;
    logic [KS_BLOCK_COL_W-1:0]   ks_loop;
  } proc_cmd_t;

  localparam int PROC_CMD_W = $bits(proc_cmd_t);

  //=== Typedef
  typedef struct packed {
    logic [BPBS_NB_WW-1:0]     pbs_nb; // Number of PBS in the batch
    logic [KS_BLOCK_COL_W-1:0] ks_loop;
  } ks_batch_cmd_t;

  localparam int KS_BATCH_CMD_W = $bits(ks_batch_cmd_t);

endpackage
