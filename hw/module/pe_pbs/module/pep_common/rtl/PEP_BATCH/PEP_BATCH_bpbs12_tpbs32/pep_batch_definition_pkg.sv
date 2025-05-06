// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Definition of localparams used in pe_pbs.
// Should not be used as is.
// Should be imported by pep_common_param_pkg.
// ==============================================================================================

package pep_batch_definition_pkg;
  import common_definition_pkg::*;

  // Number of batches in the processing pipe
  localparam int BATCH_NB = 1;
  localparam int TOTAL_BATCH_NB = 1;

  // Maximum number of processed PBS per batch.
  // The optimal value depend on the NTT architecture and the keys loading bandwidth.
  // In HPU should be a multiple of GRAM_NB = 4.
  localparam int BATCH_PBS_NB = 12;

  // Total number of PBS that can be stored in HPU.
  // In HPU should be a multiple of GRAM_NB = 4.
  // Is >= BATCH_PBS_NB.
  localparam int TOTAL_PBS_NB = 32;

endpackage
