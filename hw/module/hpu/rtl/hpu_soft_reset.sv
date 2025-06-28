// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// This module generates a global reset controlled by a config register.
// ==============================================================================================

module hpu_soft_reset (
  input  logic cfg_clk,
  input  logic cfg_srst_n,
  input  logic prc_clk_free,
  input  logic prc_srst_n_free,

  input  logic prc_clk,
  input  logic prc_srst_n,

  input  logic hpu_reset,      // Active high
  output logic hpu_reset_done, // pulse

  // The soft reset output, active low
  output logic soft_prc_srst_n
);

  typedef enum logic [1:0] {
    IDLE = 0,
    ASSERT,
    DEASSERT,
    WAIT
  } state_t;

  state_t stateD;
  state_t state;

  logic   soft_reset_txD;
  logic   hpu_reset_doneD;
  logic   soft_reset_tx;
  logic   check_bit_rx;

  always_comb begin
    hpu_reset_doneD = 1'b0;
    soft_reset_txD  = 1'b0;
    case(state)
      IDLE: begin
        stateD         = hpu_reset ? ASSERT : IDLE;
      end
      ASSERT: begin
        stateD          = check_bit_rx ? ASSERT : DEASSERT;
        soft_reset_txD  = check_bit_rx;
      end
      DEASSERT: begin
        stateD          = check_bit_rx ? WAIT : DEASSERT;
        hpu_reset_doneD = check_bit_rx;
      end
      WAIT: begin
        stateD          = hpu_reset ? WAIT : IDLE;
      end
    endcase
  end

  always_ff @(posedge cfg_clk) begin
    if(!cfg_srst_n) begin
      state          <= IDLE;
      soft_reset_tx  <= 1'b0;
      hpu_reset_done <= 1'b0;
    end else begin
      state          <= stateD;
      soft_reset_tx  <= soft_reset_txD;
      hpu_reset_done <= hpu_reset_doneD;
    end
  end

  hpu_sync #(
    // The frequency of the input signal is extremely low, this should be enough
    .DEPTH   ( 2    ) ,
    .RST_VAL ( 1'b1 )
  ) sync_cfg_prc_free (
    .clk     ( prc_clk_free    ) ,
    .s_rst_n ( prc_srst_n_free ) ,
    .in      ( ~soft_reset_tx  ) ,
    .out     ( soft_prc_srst_n )
  );

  // A reset check flag
  logic check_bit_tx;

  always_ff @(posedge prc_clk) begin
    if(!prc_srst_n) begin
      check_bit_tx <= 1'b0;
    end else begin
      check_bit_tx <= 1'b1;
    end
  end

  hpu_sync #(
    .DEPTH   ( 2    ) ,
    .RST_VAL ( 1'b0 )
  ) sync_prc_cfg (
    .clk     ( cfg_clk      ) ,
    .s_rst_n ( cfg_srst_n   ) ,
    .in      ( check_bit_tx ) ,
    .out     ( check_bit_rx )
  );

endmodule
