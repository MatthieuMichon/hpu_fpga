// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// This module gets the coefficient from pep_ks_mult.
// The coefficients are mod-switched to 2N.
// This module deals also with the ordering of the resulting LWE coefficients.
// ==============================================================================================

module pep_ks_out_process
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import pep_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
#(
  parameter int OP_W           = 64
)
(
  input  logic                                          clk,        // clock
  input  logic                                          s_rst_n,    // synchronous reset

  // From ks mult
  input  logic [LBX-1:0][OP_W-1:0]                      mult_outp_data,
  input  logic [LBX-1:0]                                mult_outp_avail,
  input  logic [LBX-1:0]                                mult_outp_last_pbs, // last coef of column
  input  logic [LBX-1:0][TOTAL_BATCH_NB_W-1:0]          mult_outp_batch_id,
  // We need the PID of the multiplication result to be able to write correction factors into the
  // body_ram.
  input  logic [LBX-1:0][PID_W-1:0]                     mult_outp_pid,

  // body
  input  logic [TOTAL_BATCH_NB-1:0][OP_W-1:0]           bfifo_outp_data,
  input  logic [TOTAL_BATCH_NB-1:0][PID_W-1:0]          bfifo_outp_pid,
  input  logic [TOTAL_BATCH_NB-1:0]                     bfifo_outp_vld,
  output logic [TOTAL_BATCH_NB-1:0]                     bfifo_outp_rdy,

  // LWE coeff
  output logic [TOTAL_BATCH_NB-1:0][LWE_COEF_W-1:0]     br_proc_lwe,
  output logic [TOTAL_BATCH_NB-1:0]                     br_proc_vld,
  input  logic [TOTAL_BATCH_NB-1:0]                     br_proc_rdy,

  // Wr access to body RAM
  output logic [TOTAL_BATCH_NB-1:0]                     br_bfifo_wr_en,
  output logic [TOTAL_BATCH_NB-1:0][OP_W-1:0]           br_bfifo_data,
  output logic [TOTAL_BATCH_NB-1:0][PID_W-1:0]          br_bfifo_pid,
  output logic [TOTAL_BATCH_NB-1:0]                     br_bfifo_parity,

  // Correct access to the body RAM
  output logic [TOTAL_BATCH_NB-1:0]                     br_bfifo_corr_wr_en,
  output logic [TOTAL_BATCH_NB-1:0][KS_MAX_ERROR_W-1:0] br_bfifo_corr_data,
  output logic [TOTAL_BATCH_NB-1:0][PID_W-1:0]          br_bfifo_corr_pid,

  // reset cache
  input  logic                                          reset_cache,

  // Config
  input  logic                                          mod_switch_mean_comp,

  // BCOL done
  output logic [TOTAL_BATCH_NB-1:0]                     outp_ks_loop_done_mh,
  output logic [TOTAL_BATCH_NB-1:0]                     inc_ksk_rd_ptr

);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int LFIFO_DEPTH           = OUT_FIFO_DEPTH * LBX * BATCH_PBS_NB;
  localparam int COLUMN_PROC_CYCLE_MIN = KS_BLOCK_LINE_NB * KS_LG_NB;
  localparam int READ_PIPE_CYCLE_MAX   = LBX * BATCH_PBS_NB;
  localparam int XFIFO_DEPTH           = BATCH_PBS_NB < 2 ? 2 : BATCH_PBS_NB;
  localparam int unsigned ABS_ERROR_W  = (MOD_KSK_W - LWE_COEF_W);

  // Check parameters
  generate
    if (OP_W <= LWE_COEF_W) begin : __UNSUPPORTED__OP_W
      $fatal(1,"> ERROR: Unsupported OP_W value. It should be >= LWE_COEF_W!");
    end

    if (COLUMN_PROC_CYCLE_MIN < READ_PIPE_CYCLE_MAX) begin : __UNSUPPORTED__LBX_LBY
      initial begin
        $display("KS_LG_NB=%0d",KS_LG_NB);
        $display("KS_BLOCK_LINE_NB=%0d",KS_BLOCK_LINE_NB);
        $display("BATCH_PBS_NB=%0d",BATCH_PBS_NB);
        $display("LBX=%0d",LBX);
        $display("READ_PIPE_CYCLE_MAX=%0d",READ_PIPE_CYCLE_MAX);
      end
      $fatal(1,"> ERROR: Unsupported LBX, LBY, LBZ. Not enough time to empty the KS output pipe.");
    end
  endgenerate

// ============================================================================================== --
// typedef
// ============================================================================================== --
  typedef struct packed {
    logic [TOTAL_BATCH_NB-1:0] batch_id_1h;
    logic                      last_pbs;
    logic                      last_mask;
    logic [LWE_COEF_W-1:0]     coef;
  } xdata_t;

  localparam int XDATA_W = $bits(xdata_t);

// ============================================================================================== --
// Input pipe
// ============================================================================================== --
  logic [LBX-1:0][OP_W-1:0]             s0_x_data;
  logic [LBX-1:0]                       s0_x_avail;
  logic [LBX-1:0]                       s0_x_last_pbs;
  logic [LBX-1:0][TOTAL_BATCH_NB_W-1:0] s0_x_batch_id;
  logic [LBX-1:0][PID_W-1:0]            s0_x_pid;
  logic                                 reset_loop;

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      s0_x_avail <= '0;
      reset_loop <= 1'b0;
    end
    else begin
      s0_x_avail <= mult_outp_avail;
      reset_loop <= reset_cache;
    end

  always_ff @(posedge clk) begin
    s0_x_data     <= mult_outp_data;
    s0_x_last_pbs <= mult_outp_last_pbs;
    s0_x_batch_id <= mult_outp_batch_id;
    s0_x_pid      <= mult_outp_pid;
  end

// ---------------------------------------------------------------------------------------------- --
// Input pipe for body
// ---------------------------------------------------------------------------------------------- --
  logic [TOTAL_BATCH_NB-1:0][OP_W-1:0] s0_body;
  logic [TOTAL_BATCH_NB-1:0][PID_W-1:0]s0_pid;
  logic [TOTAL_BATCH_NB-1:0]           s0_body_vld;
  logic [TOTAL_BATCH_NB-1:0]           s0_body_rdy;

  generate
    for (genvar gen_i=0; gen_i<TOTAL_BATCH_NB; gen_i=gen_i+1) begin : gen_total_batch_loop
      fifo_element #(
      .WIDTH          (OP_W+PID_W),
      .DEPTH          (2),
      .TYPE_ARRAY     (8'h12),
      .DO_RESET_DATA  (0),
      .RESET_DATA_VAL (0)
      ) b_fifo_element (
        .clk      (clk),
        .s_rst_n  (s_rst_n),

        .in_data  ({bfifo_outp_pid[gen_i],bfifo_outp_data[gen_i]}),
        .in_vld   (bfifo_outp_vld[gen_i]),
        .in_rdy   (bfifo_outp_rdy[gen_i]),

        .out_data ({s0_pid[gen_i],s0_body[gen_i]}),
        .out_vld  (s0_body_vld[gen_i]),
        .out_rdy  (s0_body_rdy[gen_i])
      );
    end  // for gen_i TOTAL_BATCH_NB
  endgenerate

// ============================================================================================== --
// For each column
// ============================================================================================== --
  logic [LBX-1:0][TOTAL_BATCH_NB-1:0]  s0_x_body_rdy;
  logic [TOTAL_BATCH_NB-1:0][LBX-1:0]  s0_x_body_rdy_tmp;

  always_comb
    for (int i=0; i<TOTAL_BATCH_NB; i=i+1) begin
      for (int j=0; j<LBX; j=j+1)
        s0_x_body_rdy_tmp[i][j] = s0_x_body_rdy[j][i];
      s0_body_rdy[i] = (|s0_x_body_rdy_tmp[i]) | reset_loop;
    end

// pragma translate_off
  always_ff @(posedge clk)
    if (!s_rst_n) begin
      // do nothing
    end
    else begin
      for (int i=0; i<TOTAL_BATCH_NB; i=i+1)
        assert_onehot_s0_x_body_rdy_tmp:
        assert($countones(s0_x_body_rdy_tmp[i]) < 2)
        else begin
          $fatal(1,"%t > ERROR: Several ones in s0_x_body_rdy_tmp!", $time);
        end
    end
// pragma translate_on

  // lfifo
  logic [LBX-1:0][TOTAL_BATCH_NB-1:0]   x_lfifo_in_vld;
  logic [LBX-1:0][TOTAL_BATCH_NB-1:0]   x_lfifo_in_rdy;
  logic [TOTAL_BATCH_NB-1:0][LBX-1:0]   x_lfifo_in_rdy_tmp;
  xdata_t [LBX-1:0][TOTAL_BATCH_NB-1:0] x_lfifo_in_data;

  logic [LBX-1:0][TOTAL_BATCH_NB-1:0]   x_br_bfifo_wr_en;
  logic [LBX-1:0][OP_W-1:0]             x_br_bfifo_data;
  logic [LBX-1:0][PID_W-1:0]            x_br_bfifo_pid;
  logic [LBX-1:0]                       x_br_bfifo_parity;
  logic [TOTAL_BATCH_NB-1:0][LBX-1:0]   x_br_bfifo_wr_en_tmp;
  logic [LBX-1:0][TOTAL_BATCH_NB-1:0]   x_br_bfifo_wr_enD;
  logic [LBX-1:0][OP_W-1:0]             x_br_bfifo_dataD;
  logic [LBX-1:0][PID_W-1:0]            x_br_bfifo_pidD;
  logic [LBX-1:0]                       x_br_bfifo_parityD;
  logic [LBX-1:0][TOTAL_BATCH_NB-1:0]   x_ksk_rp_done;

  logic [TOTAL_BATCH_NB-1:0]            outp_ks_loop_done_mhD;
  logic [TOTAL_BATCH_NB-1:0]            inc_ksk_rd_ptrD;

  // For the mod_switch_error accumulation daisy chain
  typedef struct packed {
    logic [KS_MAX_ERROR_W-1:0]   data; // signed
    logic [PID_W-1:0]            pid;
    logic                        parity;
    logic [TOTAL_BATCH_NB_W-1:0] batch_id;
  } acc_chain_data_t;

  acc_chain_data_t prev_br_acc_data  [LBX:0];
  logic            prev_br_acc_avail [LBX:0];
  acc_chain_data_t next_br_acc_data  [LBX-1:0];
  logic            next_br_acc_avail [LBX-1:0];
  // --------------------------------

  assign inc_ksk_rd_ptrD = x_ksk_rp_done[LBX-1];

  always_ff @(posedge clk)
    if (!s_rst_n) begin
      outp_ks_loop_done_mh <= '0;
      inc_ksk_rd_ptr       <= '0;
    end
    else begin
      outp_ks_loop_done_mh <= outp_ks_loop_done_mhD;
      inc_ksk_rd_ptr       <= inc_ksk_rd_ptrD;
    end

  always_comb
    for (int i=0; i<TOTAL_BATCH_NB; i=i+1)
      for (int j=0; j<LBX; j=j+1)
        x_lfifo_in_rdy[j][i] = x_lfifo_in_rdy_tmp[i][j];

  always_ff @(posedge clk)
    if (!s_rst_n) x_br_bfifo_wr_en <= '0;
    else          x_br_bfifo_wr_en <= x_br_bfifo_wr_enD;

  always_ff @(posedge clk) begin
    x_br_bfifo_data   <= x_br_bfifo_dataD;
    x_br_bfifo_pid    <= x_br_bfifo_pidD;
    x_br_bfifo_parity <= x_br_bfifo_parityD;
  end

  generate
      for (genvar gen_x=0; gen_x < LBX; gen_x=gen_x+1) begin : gen_loop_x
        // ----------------------------------------------
        // Counters
        // ----------------------------------------------
        logic [TOTAL_BATCH_NB-1:0][KS_BLOCK_COL_W-1:0] s0_col;
        logic [TOTAL_BATCH_NB-1:0][KS_BLOCK_COL_W-1:0] s0_colD;
        logic [TOTAL_BATCH_NB-1:0][KS_COL_W-1:0]       s0_x;
        logic [TOTAL_BATCH_NB-1:0][KS_COL_W-1:0]       s0_xD;
        logic [TOTAL_BATCH_NB-1:0]                     s0_x_parity;
        logic [TOTAL_BATCH_NB-1:0]                     s0_x_parityD;
        logic [TOTAL_BATCH_NB-1:0]                     s0_last_col;

        // TOREVIEW : share counters between the x ? could be smaller ?
        always_comb
          for (int t=0; t<TOTAL_BATCH_NB; t=t+1) begin
            s0_last_col[t]  = s0_col[t] == KS_BLOCK_COL_W'(KS_BLOCK_COL_NB-1);
            s0_colD[t]      = (s0_x_avail[gen_x] && s0_x_last_pbs[gen_x] && s0_x_batch_id[gen_x]==TOTAL_BATCH_NB_W'(t)) ? s0_last_col[t] ? '0 : s0_col[t] + 1'b1 : s0_col[t];
            s0_xD[t]        = (s0_x_avail[gen_x] && s0_x_last_pbs[gen_x] && s0_x_batch_id[gen_x]==TOTAL_BATCH_NB_W'(t)) ? s0_last_col[t] ? KS_COL_W'(gen_x) : s0_x[t] + KS_COL_W'(LBX) : s0_x[t];
            s0_x_parityD[t] = (s0_x_avail[gen_x] && s0_x_last_pbs[gen_x] && s0_x_batch_id[gen_x]==TOTAL_BATCH_NB_W'(t) && s0_last_col[t])? ~s0_x_parity[t] : s0_x_parity[t];
          end

        always_ff @(posedge clk)
          if (!s_rst_n || reset_loop) begin
            s0_col      <= '0;
            s0_x        <= {TOTAL_BATCH_NB{gen_x[KS_COL_W-1:0]}};
            s0_x_parity <= '0;
          end
          else begin
            s0_col      <= s0_colD;
            s0_x        <= s0_xD;
            s0_x_parity <= s0_x_parityD;
          end

        logic [KS_COL_W-1:0] s0_cur_x;
        logic                s0_is_body;
        logic                s0_last_mask; // last mask coefficient

        assign s0_cur_x     = s0_x[s0_x_batch_id[gen_x]];
        assign s0_is_body   = s0_cur_x == KS_COL_W'(LWE_K_P1 - 1);
        assign s0_last_mask = s0_cur_x == KS_COL_W'(LWE_K - 1);

        logic s0_ksk_rp_done;

        assign s0_ksk_rp_done = s0_x_avail[gen_x] & s0_x_last_pbs[gen_x];
        assign x_ksk_rp_done[gen_x] = {TOTAL_BATCH_NB{s0_ksk_rp_done}} & (TOTAL_BATCH_NB'(1) << s0_x_batch_id[gen_x]);

        // ----------------------------------------------
        // Subtraction
        // ----------------------------------------------
        // The operation to be done is :
        // (0,0,...,0,b) - Sum(decomp<i> * ksk<i>)
        // We are working modulo a power of 2. So no reduction is needed here.
        logic [OP_W-1:0] s0_coef;
        logic [OP_W-1:0] s0_lwe_coef;

        assign s0_coef     = s0_is_body ? s0_body[s0_x_batch_id[gen_x]] : '0;
        assign s0_lwe_coef = s0_coef - s0_x_data[gen_x];

        // ----------------------------------------------
        // Ready/valid
        // ----------------------------------------------
        logic s0_x_body_rdy_tmp;
        assign s0_x_body_rdy_tmp    = s0_is_body & s0_x_avail[gen_x];
        assign s0_x_body_rdy[gen_x] = {TOTAL_BATCH_NB{s0_x_body_rdy_tmp}} & (TOTAL_BATCH_NB'(1) << s0_x_batch_id[gen_x]);

//pragma translate_off
        always_ff @(posedge clk)
          if (!s_rst_n) begin
            // Do nothing
          end
          else begin
            assert_body_available:
            assert(!s0_x_body_rdy_tmp || s0_body_vld[s0_x_batch_id[gen_x]])
            else begin
              $fatal(1,"%t > ERROR: body is not available while needed gen_x=%0d batch_id=%0d!", $time,gen_x,s0_x_batch_id[gen_x]);
            end

          end
//pragma translate_on

        // ----------------------------------------------
        // s1 : Mod switch to 2N
        // ----------------------------------------------
        logic [OP_W-1:0]             s1_lwe_coef;
        logic                        s1_avail;
        logic                        s1_x_avail;
        logic                        s1_last_pbs;
        logic [TOTAL_BATCH_NB_W-1:0] s1_batch_id;
        logic                        s1_is_body;
        logic                        s1_last_mask;
        logic                        s1_last_col;
        logic                        s1_x_parity;
        logic                        s1_availD;
        logic [PID_W-1:0]            s1_pid;
        logic [PID_W-1:0]            s1_pidD;

        assign s1_availD = s0_x_avail[gen_x] & (s0_cur_x < KS_COL_W'(LWE_K_P1)); // Dump additional columns.

        always_ff @(posedge clk)
          if (!s_rst_n) begin
            s1_avail <= '0;
            s1_x_avail <= '0;
          end else begin
            s1_avail <= s1_availD;
            s1_x_avail <= s0_x_avail[gen_x];
          end

        always_ff @(posedge clk) begin
          s1_lwe_coef   <= s0_lwe_coef;
          s1_last_pbs   <= s0_x_last_pbs[gen_x];
          s1_batch_id   <= s0_x_batch_id[gen_x];
          s1_is_body    <= s0_is_body;
          s1_last_mask  <= s0_last_mask;
          s1_x_parity   <= s0_x_parity;
          s1_pid        <= s0_x_pid[gen_x];
          s1_last_col   <= s0_last_col;
        end

        logic s1_body_avail;
        logic s1_mask_avail;

        assign s1_mask_avail = s1_avail & ~s1_is_body;
        assign s1_body_avail = s1_avail & s1_is_body;

        // We want to mod switch from 2**OP_W to 2N (=2**LWE_COEF_W).
        // 2**OP_W and 2N are both power of 2 values.
        // 2**OP_W > 2N

        logic [LWE_COEF_W-1:0] s1_lwe_mdsw;
        assign s1_lwe_mdsw = s1_lwe_coef[OP_W-1-:LWE_COEF_W] + s1_lwe_coef[OP_W-1-LWE_COEF_W];

        logic [KS_MAX_ERROR_W-1:0] s1_lwe_mod_switch_err; // signed
        assign s1_lwe_mod_switch_err  = s1_mask_avail && mod_switch_mean_comp ?
                                        KS_MAX_ERROR_W'(s1_lwe_coef[ABS_ERROR_W-1:0])
                                      - KS_MAX_ERROR_W'((s1_lwe_coef[ABS_ERROR_W-1] << ABS_ERROR_W))
                                      : '0;

        //pragma translate_off
        always @(posedge clk)
          if(s_rst_n && s0_x_avail[gen_x] && s0_is_body)
            assert_local_pid:
            assert(s0_pid[s0_x_batch_id[gen_x]] == s0_x_pid[gen_x])
            else $fatal(1, "Local PID (%0d) does not match the body PID (%0d) for gen_x: %0d",
              s0_pid[s0_x_batch_id[gen_x]], s0_x_pid[gen_x], gen_x);
        //pragma translate_on

        // ----------------------------------------------
        // s2 : pipe
        // ----------------------------------------------
        logic [LWE_COEF_W-1:0]       s2_lwe_mdsw;
        logic [OP_W-1:0]             s2_lwe_coef;
        acc_chain_data_t             s2_mod_switch_err_data;
        logic                        s2_mask_avail;
        logic                        s2_body_avail;
        logic                        s2_mod_switch_err_avail;
        logic                        s2_last_pbs;
        logic                        s2_last_mask;
        logic                        s2_x_parity;
        logic [TOTAL_BATCH_NB_W-1:0] s2_batch_id;
        logic [PID_W-1:0]            s2_pid;

        always_ff @(posedge clk)
          if (!s_rst_n) begin
            s2_mask_avail <= '0;
            s2_body_avail <= '0;
            s2_mod_switch_err_avail <= '0;
          end
          else begin
            s2_mask_avail           <= s1_mask_avail;
            s2_body_avail           <= s1_body_avail;
            s2_mod_switch_err_avail <= s1_x_avail;
          end

        always_ff @(posedge clk) begin
          s2_lwe_mdsw  <= s1_lwe_mdsw;
          s2_last_pbs  <= s1_last_pbs;
          s2_batch_id  <= s1_batch_id;
          s2_last_mask <= s1_last_mask;
          s2_pid       <= s1_pid;
          s2_x_parity  <= s1_x_parity;
          s2_lwe_coef  <= s1_lwe_coef;
        end

        always_ff @(posedge clk) begin
          s2_mod_switch_err_data.data     <= s1_lwe_mod_switch_err;
          s2_mod_switch_err_data.pid      <= s1_pid;
          s2_mod_switch_err_data.parity   <= s1_x_parity;
          s2_mod_switch_err_data.batch_id <= s1_batch_id;
        end

        // ----------------------------------------------
        // to br bfifo
        // ----------------------------------------------
        assign x_br_bfifo_wr_enD[gen_x]  = {TOTAL_BATCH_NB{s2_body_avail}} & (1 << s2_batch_id);
        assign x_br_bfifo_dataD[gen_x]   = s2_lwe_coef;
        assign x_br_bfifo_pidD[gen_x]    = s2_pid;
        assign x_br_bfifo_parityD[gen_x] = s2_x_parity;

        // ----------------------------------------------
        // Mean mod_switch_error accumulation
        // ----------------------------------------------

        // Fifo to the final X accumulator
        // The assumption here is that all column data will be ready when accumulating through the
        // pipeline.
        acc_chain_data_t s3_br_data;
        logic            s3_br_vld;

        // X accumulation daisy chain
        if (gen_x == 0) begin: first_x
          always_ff @(posedge clk) begin
            if(!s_rst_n) begin
              s3_br_vld <= '0;
            end else begin
              s3_br_vld <= s2_mod_switch_err_avail;
            end
          end

          always_ff @(posedge clk) begin
            s3_br_data <= s2_mod_switch_err_data;
          end

          assign prev_br_acc_avail[0] = s3_br_vld;
          assign prev_br_acc_data[0]  = '0;
        end else begin: next_x
          logic s3_br_rdy;
          logic s2_mod_switch_err_rdy;
          fifo_element #(
            .WIDTH          ($bits(s2_mod_switch_err_data)),
            .DEPTH          (2),
            .TYPE_ARRAY     (8'h12),
            .DO_RESET_DATA  (0),
            .RESET_DATA_VAL (0)
          ) mod_switch_err_fifo (
            .clk      (clk),
            .s_rst_n  (s_rst_n),

            .in_data  (s2_mod_switch_err_data),
            .in_vld   (s2_mod_switch_err_avail),
            .in_rdy   (s2_mod_switch_err_rdy),

            .out_data (s3_br_data),
            .out_vld  (s3_br_vld),
            .out_rdy  (s3_br_rdy)
          );

          assign s3_br_rdy = prev_br_acc_avail[gen_x];

          // pragma translate_off
          always_ff @(posedge clk)
            if (s_rst_n)
              assert_mod_switch_err_fifo_not_full:
              assert((s2_mod_switch_err_avail && s2_mod_switch_err_rdy) || (!s2_mod_switch_err_avail))
              else $fatal(1,"%t > ERROR: mod_switch_err_fifo[%0d] is full when in_vld == 1!",$time, gen_x);

          always_ff @(posedge clk)
            if (s_rst_n)
              assert_mod_switch_err_fifo_ready:
              assert((s3_br_rdy && s3_br_vld) || (!s3_br_rdy))
              else $fatal(1,"%t > ERROR: mod_switch_err_fifo[%0d] is not ready when needed!",$time, gen_x);
          // pragma translate_on
        end

        logic            next_br_acc_avail_ff;
        acc_chain_data_t next_br_acc_data_ff;

        always_ff @(posedge clk) begin
          if(!s_rst_n) begin
            next_br_acc_avail_ff <= '0;
          end else begin
            next_br_acc_avail_ff <= prev_br_acc_avail[gen_x];
          end
        end

        always_ff @(posedge clk) begin
          next_br_acc_data_ff.data     <= prev_br_acc_data[gen_x].data     + s3_br_data.data;
          next_br_acc_data_ff.pid      <= prev_br_acc_data[gen_x].pid      | s3_br_data.pid;
          next_br_acc_data_ff.batch_id <= prev_br_acc_data[gen_x].batch_id | s3_br_data.batch_id;
        end

        if (gen_x != 0)
          always_ff @(posedge clk)
            if(s_rst_n && prev_br_acc_avail[gen_x]) begin
              assert_daisy_chain_pid:
              assert(prev_br_acc_data[gen_x].pid == s3_br_data.pid)
              else $fatal(1, "%t> ERROR: The data in the accumulation chain does not belong to the same pid: %0d != %0d",
                             prev_br_acc_data[gen_x].pid, s3_br_data.pid);

              assert_daisy_chain_batch_id:
              assert(prev_br_acc_data[gen_x].batch_id == s3_br_data.batch_id)
              else $fatal(1, "%t> ERROR: The data in the accumulation chain does not belong to the same batch_id: %0d != %0d",
                             prev_br_acc_data[gen_x].batch_id, s3_br_data.batch_id);
            end

        assign next_br_acc_data[gen_x]    = next_br_acc_data_ff;
        assign next_br_acc_avail[gen_x]   = next_br_acc_avail_ff;
        assign prev_br_acc_data[gen_x+1]  = next_br_acc_data[gen_x];
        assign prev_br_acc_avail[gen_x+1] = next_br_acc_avail[gen_x];

        // ----------------------------------------------
        // xfifo
        // ----------------------------------------------
        xdata_t xfifo_in_data;
        logic   xfifo_in_vld;
        logic   xfifo_in_rdy;
        xdata_t xfifo_out_data;
        logic   xfifo_out_vld;
        logic   xfifo_out_rdy;

        assign xfifo_in_vld              = s2_mask_avail;
        assign xfifo_in_data.batch_id_1h = TOTAL_BATCH_NB'(1) << s2_batch_id;
        assign xfifo_in_data.last_pbs    = s2_last_pbs;
        assign xfifo_in_data.last_mask   = s2_last_mask;
        assign xfifo_in_data.coef        = s2_lwe_mdsw;

        fifo_reg #(
          .WIDTH       (XDATA_W),
          .DEPTH       (XFIFO_DEPTH),
          .LAT_PIPE_MH (2'b11)
        ) xfifo (
          .clk      (clk),
          .s_rst_n  (s_rst_n),

          .in_data  (xfifo_in_data),
          .in_vld   (xfifo_in_vld),
          .in_rdy   (xfifo_in_rdy),

          .out_data (xfifo_out_data),
          .out_vld  (xfifo_out_vld),
          .out_rdy  (xfifo_out_rdy)
        );

// pragma translate_off
        always_ff @(posedge clk)
          if (!s_rst_n) begin
            // do nothing
          end
          else begin
            assert_xfifo_ready:
            assert(!xfifo_in_vld || xfifo_in_rdy)
            else begin
              $fatal(1,"%t > ERROR: xfifo[%0d] is full when in_vld = 1!",$time, gen_x);
            end
          end
// pragma translate_on

        // ----------------------------------------------
        // to lfifo
        // ----------------------------------------------
        assign x_lfifo_in_vld[gen_x]  = {TOTAL_BATCH_NB{xfifo_out_vld}} & xfifo_out_data.batch_id_1h;
        assign x_lfifo_in_data[gen_x] = {TOTAL_BATCH_NB{xfifo_out_data}};
        assign xfifo_out_rdy = |(x_lfifo_in_rdy[gen_x] & xfifo_out_data.batch_id_1h);

      end // for gen_x

// ============================================================================================== --
// LFIFO
// ============================================================================================== --
// 1 FIFO per batch
// Read all the PBS of each x before reading the next x. Then wrap.

      for (genvar gen_b=0; gen_b<TOTAL_BATCH_NB; gen_b=gen_b+1) begin : gen_lfifo_loop
        //---------------------------------------------
        // counters
        //---------------------------------------------
        logic [LBX_W-1:0] l_x_id;
        logic [LBX_W-1:0] l_x_idD;
        logic             l_last_x_id;
        logic             l_wr_en;

        // select
        xdata_t           l_x_data;
        logic             l_x_vld;
        logic             l_x_rdy;
        logic [LBX-1:0]   x_lfifo_in_rdy_local;

        assign x_lfifo_in_rdy_tmp[gen_b] = x_lfifo_in_rdy_local;
        assign l_x_data = x_lfifo_in_data[l_x_id][gen_b];
        assign l_x_vld  = x_lfifo_in_vld[l_x_id][gen_b];

        always_comb
          for (int i=0; i<LBX; i=i+1)
            x_lfifo_in_rdy_local[i] = (l_x_id==LBX_W'(i)) ? l_x_rdy : 1'b0;

        assign l_last_x_id = (l_x_id == LBX_W'(LBX-1));
        assign l_x_idD     = l_wr_en && l_x_data.last_pbs ? l_last_x_id || l_x_data.last_mask ? '0 : l_x_id + 1'b1 : l_x_id;

        always_ff @(posedge clk)
          if (!s_rst_n) l_x_id <= '0;
          else          l_x_id <= l_x_idD;

        //---------------------------------------------
        // Instances
        //---------------------------------------------
        logic [LWE_COEF_W-1:0] lfifo_in_data;
        logic                  lfifo_in_ks_loop_done;
        logic                  lfifo_in_vld;
        logic                  lfifo_in_rdy;
        logic [LWE_COEF_W-1:0] lfifo_out_data;
        logic                  lfifo_out_ks_loop_done;
        logic                  lfifo_out_vld;
        logic                  lfifo_out_rdy;

        assign lfifo_in_data = l_x_data.coef;
        assign lfifo_in_vld  = l_x_vld;
        assign l_x_rdy       = lfifo_in_rdy;
        assign lfifo_in_ks_loop_done = l_x_data.last_pbs & (l_last_x_id || l_x_data.last_mask);

        assign l_wr_en       = lfifo_in_vld & lfifo_in_rdy;
        fifo_reg #(
          .WIDTH       (LWE_COEF_W + 1),
          .DEPTH       (LFIFO_DEPTH),
          .LAT_PIPE_MH (2'b11)
        ) lfifo (
          .clk      (clk),
          .s_rst_n  (s_rst_n),

          .in_data  ({lfifo_in_ks_loop_done,lfifo_in_data}),
          .in_vld   (lfifo_in_vld),
          .in_rdy   (lfifo_in_rdy),

          .out_data ({lfifo_out_ks_loop_done,lfifo_out_data}),
          .out_vld  (lfifo_out_vld),
          .out_rdy  (lfifo_out_rdy)
        );

        assign br_proc_lwe[gen_b] = lfifo_out_data;
        assign br_proc_vld[gen_b] = lfifo_out_vld;
        assign lfifo_out_rdy      = br_proc_rdy[gen_b] | reset_loop;
        assign outp_ks_loop_done_mhD[gen_b] = lfifo_out_ks_loop_done & lfifo_out_vld & lfifo_out_rdy;
      end // for gen_b
  endgenerate

// ============================================================================================== --
// Send the correction factor out
// ============================================================================================== --

  logic [TOTAL_BATCH_NB-1:0]            br_bfifo_corr_wr_enD;
  logic [TOTAL_BATCH_NB-1:0][OP_W-1:0]  br_bfifo_corr_dataD;
  logic [TOTAL_BATCH_NB-1:0][PID_W-1:0] br_bfifo_corr_pidD;

  assign br_bfifo_corr_wr_enD = {TOTAL_BATCH_NB{next_br_acc_avail[LBX-1]}}
                              & (TOTAL_BATCH_NB'(1) << next_br_acc_data[LBX-1].batch_id);

  always_comb begin
    br_bfifo_corr_dataD   = '0;
    br_bfifo_corr_pidD    = '0;
    for (int i=0; i<TOTAL_BATCH_NB; i=i+1) begin
      br_bfifo_corr_dataD[i]   = (next_br_acc_data[LBX-1].data & {OP_W{br_bfifo_corr_wr_enD[i]}});
      br_bfifo_corr_pidD[i]    = (next_br_acc_data[LBX-1].pid  & {PID_W{br_bfifo_corr_wr_enD[i]}});
    end
  end

  always_ff @(posedge clk)
    if (!s_rst_n) br_bfifo_corr_wr_en <= '0;
    else          br_bfifo_corr_wr_en <= br_bfifo_corr_wr_enD;

  always_ff @(posedge clk) begin
    br_bfifo_corr_data   <= br_bfifo_corr_dataD;
    br_bfifo_corr_pid    <= br_bfifo_corr_pidD;
  end

// ============================================================================================== --
// br bfifo
// ============================================================================================== --
  logic [TOTAL_BATCH_NB-1:0]            br_bfifo_wr_enD;
  logic [TOTAL_BATCH_NB-1:0][OP_W-1:0]  br_bfifo_dataD;
  logic [TOTAL_BATCH_NB-1:0][PID_W-1:0] br_bfifo_pidD;
  logic [TOTAL_BATCH_NB-1:0]            br_bfifo_parityD;

  always_comb
    for (int i=0; i<TOTAL_BATCH_NB; i=i+1) begin
      for (int j=0; j<LBX; j=j+1)
        x_br_bfifo_wr_en_tmp[i][j] = x_br_bfifo_wr_en[j][i];
      br_bfifo_wr_enD[i] = |x_br_bfifo_wr_en_tmp[i];
    end

  always_comb begin
    br_bfifo_dataD   = '0;
    br_bfifo_pidD    = '0;
    br_bfifo_parityD = '0;
    for (int i=0; i<TOTAL_BATCH_NB; i=i+1)
      for (int j=0; j<LBX; j=j+1) begin
        br_bfifo_dataD[i]   = br_bfifo_dataD[i] | (x_br_bfifo_data[j] & {OP_W{x_br_bfifo_wr_en[j][i]}});
        br_bfifo_pidD[i]    = br_bfifo_pidD[i]  | (x_br_bfifo_pid[j]  & {PID_W{x_br_bfifo_wr_en[j][i]}});
        br_bfifo_parityD[i] = br_bfifo_parityD[i]  | (x_br_bfifo_parity[j] & x_br_bfifo_wr_en[j][i]);
      end
  end

  always_ff @(posedge clk)
    if (!s_rst_n) br_bfifo_wr_en <= '0;
    else          br_bfifo_wr_en <= br_bfifo_wr_enD;

  always_ff @(posedge clk) begin
    br_bfifo_data   <= br_bfifo_dataD;
    br_bfifo_pid    <= br_bfifo_pidD;
    br_bfifo_parity <= br_bfifo_parityD;
  end

endmodule
