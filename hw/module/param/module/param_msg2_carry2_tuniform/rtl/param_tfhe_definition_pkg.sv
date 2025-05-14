// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Parameters that defines the PBS for concrete boolean.
// Do not use this package directly in modules. Use param_tfhe_pkg instead.
// This purpose of this package is to ease the tests/synthesis with various localparam sets.
// // security = 132 bits, p-fail = 2^-64.138, algorithmic cost ~ 113, 2-norm = 5
//  pub const PARAM_MESSAGE_2_CARRY_2_KS_PBS_TUNIFORM_2M64: ClassicPBSParameters =
//    ClassicPBSParameters {
//        lwe_dimension: LweDimension(887),
//        glwe_dimension: GlweDimension(1),
//        polynomial_size: PolynomialSize(2048),
//        lwe_noise_distribution: DynamicDistribution::new_t_uniform(46),
//        glwe_noise_distribution: DynamicDistribution::new_t_uniform(17),
//        pbs_base_log: DecompositionBaseLog(22),
//        pbs_level: DecompositionLevelCount(1),
//        ks_base_log: DecompositionBaseLog(3),
//        ks_level: DecompositionLevelCount(5),
//        message_modulus: MessageModulus(4),
//        carry_modulus: CarryModulus(4),
//        max_noise_level: MaxNoiseLevel::new(5),
//        log2_p_fail: -64.138,
//        ciphertext_modulus: CiphertextModulus::new_native(),
//        encryption_key_choice: EncryptionKeyChoice::Big,
//    };
// ==============================================================================================

package param_tfhe_definition_pkg;
  import common_definition_pkg::*;

  localparam application_name_e APPLICATION_NAME = APPLICATION_NAME_MSG2_CARRY2_TUNIFORM;

  // Number of coefficient in the polynomial
  localparam int           N       = 2048;
  // The dimension of GLWE.
  localparam int           GLWE_K  = 1;
  // Number of decomposition levels.
  localparam int           PBS_L   = 1;
  // Decomposition base, in number of bits
  localparam int           PBS_B_W = 22;
  // Ciphertext size
  localparam int           LWE_K   = 887;
  // GLWE coefficient size
  localparam int           MOD_Q_W = 64;
  // GLWE coefficient modulo
  localparam [MOD_Q_W:0]   MOD_Q   = 2**MOD_Q_W;
  // Number of decomposition levels.
  localparam int           KS_L    = 5;
  // Decomposition base, in number of bits
  localparam int           KS_B_W  = 3;
  // KSK coefficient size
  localparam int           MOD_KSK_W = 21;
  // KSK coefficient modulo
  localparam [MOD_KSK_W:0] MOD_KSK = 2**MOD_KSK_W;
  // Useful message bit (padding + payload)
  localparam int           PAYLOAD_BIT   = 4;
  localparam int           PADDING_BIT   = 1;
endpackage
