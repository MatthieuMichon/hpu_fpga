// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// HPU top level.
// HPU is split into 3 parts.
// This module is the assembly of all parts.
// Mainly used to ease P&R constraints.
// ==============================================================================================

`include "hpu_io_macro_inc.sv"

module hpu_3parts
  import common_definition_pkg::*;
  import param_tfhe_pkg::*;
  import param_ntt_pkg::*;
  import top_common_param_pkg::*;
  import hpu_common_param_pkg::*;
  import hpu_common_instruction_pkg::*;
  import axi_if_common_param_pkg::*;
  import axi_if_shell_axil_pkg::*;
  import axi_if_bsk_axi_pkg::*;
  import axi_if_ksk_axi_pkg::*;
  import axi_if_glwe_axi_pkg::*;
  import axi_if_ct_axi_pkg::*;
  import axi_if_trc_axi_pkg::*;
  import regf_common_param_pkg::*;
  import pem_common_param_pkg::*;
  import pea_common_param_pkg::*;
  import pep_common_param_pkg::*;
  import ntt_core_common_param_pkg::*;
  import pep_ks_common_param_pkg::*;
  import pep_if_pkg::*;
#(
  // AXI4 ADD_W could be redefined by the simulation.
  parameter int    AXI4_TRC_ADD_W   = 64,
  parameter int    AXI4_PEM_ADD_W   = 64,
  parameter int    AXI4_GLWE_ADD_W  = 64,
  parameter int    AXI4_BSK_ADD_W   = 64,
  parameter int    AXI4_KSK_ADD_W   = 64,

  // HPU version
  parameter int    VERSION_MAJOR    = 2,
  parameter int    VERSION_MINOR    = 0,

  // Add pipe on signals between parts.
  parameter int    INTER_PART_PIPE  = 2 // Indicates the number of pipes on signals crossing the SLRs.
                                        // Note that 0 means not used.
)
(
  input  logic                 prc_clk,    // process clock
  input  logic                 prc_clk_free, // process clock, free running
  input  logic                 prc_srst_n, // synchronous reset
  output logic                 prc_ce,     // process clock enable

  input  logic                 cfg_clk,    // config clock
  input  logic                 cfg_srst_n, // synchronous reset

  output logic [3:0]           interrupt,

  //== Axi4-lite slave @prc_clk and @cfg_clk
  `HPU_AXIL_IO(prc_1in3,axi_if_shell_axil_pkg)
  `HPU_AXIL_IO(cfg_1in3,axi_if_shell_axil_pkg)
  `HPU_AXIL_IO(prc_3in3,axi_if_shell_axil_pkg)
  `HPU_AXIL_IO(cfg_3in3,axi_if_shell_axil_pkg)

  //== Axi4 trace interface
  `HPU_AXI4_IO(trc, TRC, axi_if_trc_axi_pkg,)

  //== Axi4 PEM interface
  `HPU_AXI4_IO(pem, PEM, axi_if_ct_axi_pkg, [PEM_PC_MAX-1:0])

  //== Axi4 GLWE interface
  `HPU_AXI4_IO(glwe, GLWE, axi_if_glwe_axi_pkg, [GLWE_PC_MAX-1:0])

  //== Axi4 KSK interface
  `HPU_AXI4_IO(ksk, KSK, axi_if_ksk_axi_pkg, [KSK_PC_MAX-1:0])

  //== Axi4 BSK interface
  `HPU_AXI4_IO(bsk, BSK, axi_if_bsk_axi_pkg, [BSK_PC_MAX-1:0])

  //== AXI stream for ISC
  input  logic [PE_INST_W-1:0] isc_dop,
  output logic                 isc_dop_rdy,
  input  logic                 isc_dop_vld,

  output logic [PE_INST_W-1:0] isc_ack,
  input  logic                 isc_ack_rdy,
  output logic                 isc_ack_vld
);

// ============================================================================================== --
// Signals
// ============================================================================================== --
  // -------------------------------------------------------------------------------------------- --
  //-- NTT : ntt <-> mmacc
  // -------------------------------------------------------------------------------------------- --
  typedef struct packed {
    logic [PSI-1:0][R-1:0][PBS_B_W:0] data; // 2s complement
    logic                             sob;
    logic                             eob;
    logic                             sog;
    logic                             eog;
    logic                             sol;
    logic                             eol;
    logic [BPBS_ID_W-1:0]             pbs_id;
    logic                             last_pbs;
    logic                             full_throughput;
  } decomp_ntt_data_t;

  typedef struct packed {
    logic [PSI-1:0][R-1:0]            data_avail;
    logic                             ctrl_avail;
  } decomp_ntt_ctrl_t;

  typedef struct packed {
    // Mod switch
    logic [PSI-1:0][R-1:0][MOD_Q_W-1:0] data;
    logic                               sob;
    logic                               eob;
    logic                               sol;
    logic                               eol;
    logic                               sog;
    logic                               eog;
    logic [BPBS_ID_W-1:0]               pbs_id;
  } ntt_acc_modsw_data_t;

  typedef struct packed {
    // Mod switch
    logic [PSI-1:0][R-1:0]              data_avail;
    logic                               ctrl_avail;
  } ntt_acc_modsw_ctrl_t;

  decomp_ntt_data_t    in_decomp_ntt_data;
  decomp_ntt_ctrl_t    in_decomp_ntt_ctrl;
  decomp_ntt_data_t    out_decomp_ntt_data;
  decomp_ntt_ctrl_t    out_decomp_ntt_ctrl;
  ntt_acc_modsw_data_t in_ntt_acc_modsw_data;
  ntt_acc_modsw_ctrl_t in_ntt_acc_modsw_ctrl;
  ntt_acc_modsw_data_t out_ntt_acc_modsw_data;
  ntt_acc_modsw_ctrl_t out_ntt_acc_modsw_ctrl;

  // -------------------------------------------------------------------------------------------- --
  //-- BSK : entry <-> bsk
  // -------------------------------------------------------------------------------------------- --
  entrybsk_proc_t       in_entry_bsk_proc;
  bskentry_proc_t       in_bsk_entry_proc;

  entrybsk_proc_t       out_entry_bsk_proc;
  bskentry_proc_t       out_bsk_entry_proc;
  // -------------------------------------------------------------------------------------------- --
  //-- NTT processing path
  // -------------------------------------------------------------------------------------------- --
  //== Cmd path
  ntt_proc_cmd_t         in_ntt_proc_cmd;
  logic                  in_ntt_proc_cmd_avail;

  ntt_proc_cmd_t         out_ntt_proc_cmd;
  logic                  out_ntt_proc_cmd_avail;

  //== Data path
  ntt_proc_data_t        in_p2_p3_ntt_proc_data;
  logic [PSI-1:0][R-1:0] in_p2_p3_ntt_proc_avail;
  logic                  in_p2_p3_ntt_proc_ctrl_avail;

  ntt_proc_data_t        in_p3_p2_ntt_proc_data;
  logic [PSI-1:0][R-1:0] in_p3_p2_ntt_proc_avail;
  logic                  in_p3_p2_ntt_proc_ctrl_avail;

  ntt_proc_data_t        out_p2_p3_ntt_proc_data;
  logic [PSI-1:0][R-1:0] out_p2_p3_ntt_proc_avail;
  logic                  out_p2_p3_ntt_proc_ctrl_avail;

  ntt_proc_data_t        out_p3_p2_ntt_proc_data;
  logic [PSI-1:0][R-1:0] out_p3_p2_ntt_proc_avail;
  logic                  out_p3_p2_ntt_proc_ctrl_avail;

  // -------------------------------------------------------------------------------------------- --
  //-- To regif
  // -------------------------------------------------------------------------------------------- --
  pep_rif_elt_t          in_p2_p3_pep_rif_elt;

  pep_rif_elt_t          out_p2_p3_pep_rif_elt;

  // -------------------------------------------------------------------------------------------- --
  //-- Interrupt
  // -------------------------------------------------------------------------------------------- --
  logic                  in_p1_prc_interrupt;
  logic                  in_p1_cfg_interrupt;
  logic                  in_p3_prc_interrupt;
  logic                  in_p3_cfg_interrupt;

  logic                  out_p1_prc_interrupt;
  logic                  out_p1_cfg_interrupt;
  logic                  out_p3_prc_interrupt;
  logic                  out_p3_cfg_interrupt;

// ============================================================================================== --
// Interrupts // TOREVIEW
// ============================================================================================== --
  assign interrupt = {out_p3_cfg_interrupt,
                      out_p3_prc_interrupt,
                      out_p1_cfg_interrupt,
                      out_p1_prc_interrupt};

// ============================================================================================== --
// Daisy chain the reset signals to be able to pin the reset root to different SLRs
// ============================================================================================== --
  logic [2:0] prc_srst_n_part;
  logic [1:0] prc_rst_sll;

  fpga_clock_reset #(
    .RST_POL         ( 1'b0                  ) ,
    .INTER_PART_PIPE ( INTER_PART_PIPE       ) ,
    .INTRA_PART_PIPE ( 2*INTER_PART_PIPE + 1 ) // To match the latency of the other resets
  ) prc3_clk_rst (
    .clk_in  ( prc_clk_free       ) ,
    .rst_in  ( prc_srst_n         ) ,
    .rst_nxt ( prc_rst_sll[0]     ) ,
    .clk_en  ( prc_ce             ) ,
    .rst_out ( prc_srst_n_part[2] )
  );

  fpga_clock_reset #(
    .RST_POL         ( 1'b0                ) ,
    .INTER_PART_PIPE ( INTER_PART_PIPE     ) ,
    .INTRA_PART_PIPE ( INTER_PART_PIPE + 1 ) // To match the latency of the other resets
  ) prc2_clk_rst (
    .clk_in  ( prc_clk_free       ) ,
    .rst_in  ( prc_rst_sll[0]     ) ,
    .rst_nxt ( prc_rst_sll[1]     ) ,
    .clk_en  ( /*UNUSED*/   ) ,
    .rst_out ( prc_srst_n_part[1] )
  );

  fpga_clock_reset #(
    .RST_POL         ( 1'b0  ) ,
    .INTER_PART_PIPE ( 0     ) ,
    .INTRA_PART_PIPE ( 1     ) // To match the latency of the other resets
  ) prc1_clk_rst (
    .clk_in  ( prc_clk_free       ) ,
    .rst_in  ( prc_rst_sll[1]     ) ,
    .rst_nxt ( /*NC*/             ) ,
    .clk_en  ( /*NC*/             ) ,
    .rst_out ( prc_srst_n_part[0] )
  );

//=====================================
// Fifo element
//=====================================
  // These belong to SLR2, where the ISC is placed. The NOC slave is very close to it already

  logic [31:0] s1_isc_dop;
  logic        s1_isc_dop_vld;
  logic        s1_isc_dop_rdy;
  fifo_element #(
  .WIDTH          (32),
  .DEPTH          (1),
  .TYPE_ARRAY     (4'h3),
  .DO_RESET_DATA  (0),
  .RESET_DATA_VAL (0)
  ) fifo_element_isc_dop (
    .clk     (prc_clk),
    .s_rst_n (prc_srst_n_part[0]),

    .in_data (isc_dop),
    .in_vld  (isc_dop_vld),
    .in_rdy  (isc_dop_rdy),

    .out_data(s1_isc_dop),
    .out_vld (s1_isc_dop_vld),
    .out_rdy (s1_isc_dop_rdy)
  );

  logic [31:0] s1_isc_ack;
  logic        s1_isc_ack_vld;
  logic        s1_isc_ack_rdy;
  fifo_element #(
  .WIDTH          (32),
  .DEPTH          (1),
  .TYPE_ARRAY     (4'h3),
  .DO_RESET_DATA  (0),
  .RESET_DATA_VAL (0)
  ) fifo_element_isc_ack (
    .clk     (prc_clk),
    .s_rst_n (prc_srst_n_part[0]),

    .in_data (s1_isc_ack),
    .in_vld  (s1_isc_ack_vld),
    .in_rdy  (s1_isc_ack_rdy),

    .out_data (isc_ack),
    .out_vld  (isc_ack_vld),
    .out_rdy  (isc_ack_rdy)
  );

// ============================================================================================== --
// Inter part pipes
// ============================================================================================== --
// Note: Increasing inter part pipe here will increase the NTT and, consequently, PBS latency
  localparam int unsigned P2_P1_PART_PIPE = INTER_PART_PIPE > 0 ? unsigned'(1) : unsigned'(0);
  localparam int unsigned P1_P2_PART_PIPE = unsigned'(0);

  hpu_qual_sll #(
    .IN_DEPTH    ( 0                            ) ,
    .OUT_DEPTH   ( P1_P2_PART_PIPE              ) ,
    .DATA_WIDTH  ( $bits(decomp_ntt_data_t)     ) ,
    .CTRL_WIDTH  ( $bits(decomp_ntt_ctrl_t)     ) ,
    .CTRL_RST    ( $bits(decomp_ntt_ctrl_t)'(0) )
  ) p1_p2_sll_decomp_ntt (
    .in_clk      ( prc_clk             ) ,
    .in_s_rst_n  ( prc_srst_n_part[0]  ) ,
    .in_data     ( in_decomp_ntt_data  ) ,
    .in_ctrl     ( in_decomp_ntt_ctrl  ) ,
    .out_clk     ( prc_clk             ) ,
    .out_s_rst_n ( prc_srst_n_part[1]  ) ,
    .out_data    ( out_decomp_ntt_data ) ,
    .out_ctrl    ( out_decomp_ntt_ctrl )
  );

  hpu_qual_sll #(
    .IN_DEPTH    ( 0                               ) ,
    .OUT_DEPTH   ( P2_P1_PART_PIPE                 ) ,
    .DATA_WIDTH  ( $bits(ntt_acc_modsw_data_t)     ) ,
    .CTRL_WIDTH  ( $bits(ntt_acc_modsw_ctrl_t)     ) ,
    .CTRL_RST    ( $bits(ntt_acc_modsw_ctrl_t)'(0) )
  ) p2_p1_sll_ntt_acc_modsw (
    .in_clk      ( prc_clk                ) ,
    .in_s_rst_n  ( prc_srst_n_part[1]     ) ,
    .in_data     ( in_ntt_acc_modsw_data  ) ,
    .in_ctrl     ( in_ntt_acc_modsw_ctrl  ) ,
    .out_clk     ( prc_clk                ) ,
    .out_s_rst_n ( prc_srst_n_part[0]     ) ,
    .out_data    ( out_ntt_acc_modsw_data ) ,
    .out_ctrl    ( out_ntt_acc_modsw_ctrl )
  );

  generate
    if (INTER_PART_PIPE > 0) begin : gen_inter_part_pipe
      //-- BSK : entry <-> bsk
      entrybsk_proc_t        out_entry_bsk_procD;
      bskentry_proc_t        out_bsk_entry_procD;

      //-- NTT processing path
      //== Cmd path
      ntt_proc_cmd_t         out_ntt_proc_cmdD;
      logic                  out_ntt_proc_cmd_availD;

      //== Data path
      ntt_proc_data_t        out_p2_p3_ntt_proc_dataD;
      logic [PSI-1:0][R-1:0] out_p2_p3_ntt_proc_availD;
      logic                  out_p2_p3_ntt_proc_ctrl_availD;

      ntt_proc_data_t        out_p3_p2_ntt_proc_dataD;
      logic [PSI-1:0][R-1:0] out_p3_p2_ntt_proc_availD;
      logic                  out_p3_p2_ntt_proc_ctrl_availD;

      //-- To regif
      pep_rif_elt_t          out_p2_p3_pep_rif_eltD;

      // ----------------------------------------------------------------------------------------- //
      // Interpart Resetable output flops
      // ----------------------------------------------------------------------------------------- //
      // Part 1
      always_ff @(posedge prc_clk)
        if (!prc_srst_n_part[0]) begin
          out_bsk_entry_proc               <= '0;
          out_p1_prc_interrupt             <= '0;
        end
        else begin
          out_bsk_entry_proc               <= out_bsk_entry_procD;
          out_p1_prc_interrupt             <= out_p1_prc_interrupt;
        end

      // Part 2
      always_ff @(posedge prc_clk)
        if (!prc_srst_n_part[1]) begin
          out_ntt_proc_cmd_avail           <= '0;
          out_p3_p2_ntt_proc_avail         <= '0;
          out_p3_p2_ntt_proc_ctrl_avail    <= '0;
        end
        else begin
          out_ntt_proc_cmd_avail           <= out_ntt_proc_cmd_availD;
          out_p3_p2_ntt_proc_avail         <= out_p3_p2_ntt_proc_availD;
          out_p3_p2_ntt_proc_ctrl_avail    <= out_p3_p2_ntt_proc_ctrl_availD;
        end

      // Part 3
      always_ff @(posedge prc_clk)
        if (!prc_srst_n_part[2]) begin
          out_entry_bsk_proc               <= '0;
          out_p2_p3_ntt_proc_avail         <= '0;
          out_p2_p3_ntt_proc_ctrl_avail    <= '0;
          out_p2_p3_pep_rif_elt            <= '0;
          out_p3_prc_interrupt             <= '0;
        end
        else begin
          out_entry_bsk_proc               <= out_entry_bsk_procD;
          out_p2_p3_ntt_proc_avail         <= out_p2_p3_ntt_proc_availD;
          out_p2_p3_ntt_proc_ctrl_avail    <= out_p2_p3_ntt_proc_ctrl_availD;
          out_p2_p3_pep_rif_elt            <= out_p2_p3_pep_rif_eltD;
          out_p3_prc_interrupt             <= out_p3_prc_interrupt;
        end
      // ----------------------------------------------------------------------------------------- //

      always_ff @(posedge prc_clk) begin
        out_ntt_proc_cmd           <= out_ntt_proc_cmdD;
        out_p3_p2_ntt_proc_data    <= out_p3_p2_ntt_proc_dataD;
      end

      always_ff @(posedge prc_clk) begin
        out_p2_p3_ntt_proc_data    <= out_p2_p3_ntt_proc_dataD;
      end

      always_ff @(posedge cfg_clk)
        if (!cfg_srst_n) begin
          out_p1_cfg_interrupt <= '0;
        end
        else begin
          out_p1_cfg_interrupt <= in_p1_cfg_interrupt;
        end

      always_ff @(posedge cfg_clk)
        if (!cfg_srst_n) begin
          out_p3_cfg_interrupt <= '0;
        end
        else begin
          out_p3_cfg_interrupt <= in_p3_cfg_interrupt;
        end

      if (INTER_PART_PIPE == 1) begin
        assign out_entry_bsk_procD            = in_entry_bsk_proc;
        assign out_bsk_entry_procD            = in_bsk_entry_proc;

        assign out_ntt_proc_cmdD              = in_ntt_proc_cmd;
        assign out_ntt_proc_cmd_availD        = in_ntt_proc_cmd_avail;

        assign out_p2_p3_ntt_proc_dataD       = in_p2_p3_ntt_proc_data;
        assign out_p2_p3_ntt_proc_availD      = in_p2_p3_ntt_proc_avail;
        assign out_p2_p3_ntt_proc_ctrl_availD = in_p2_p3_ntt_proc_ctrl_avail;

        assign out_p3_p2_ntt_proc_dataD       = in_p3_p2_ntt_proc_data;
        assign out_p3_p2_ntt_proc_availD      = in_p3_p2_ntt_proc_avail;
        assign out_p3_p2_ntt_proc_ctrl_availD = in_p3_p2_ntt_proc_ctrl_avail;

        assign out_p2_p3_pep_rif_eltD         = in_p2_p3_pep_rif_elt;

      end
      else if (INTER_PART_PIPE == 2) begin
        //-- BSK : entry <-> bsk
        entrybsk_proc_t        in_entry_bsk_proc_dly;
        bskentry_proc_t        in_bsk_entry_proc_dly;

        //-- NTT processing path
        //== Cmd path
        ntt_proc_cmd_t         in_ntt_proc_cmd_dly;
        logic                  in_ntt_proc_cmd_avail_dly;

        //== Data path
        ntt_proc_data_t        in_p2_p3_ntt_proc_data_dly;
        logic [PSI-1:0][R-1:0] in_p2_p3_ntt_proc_avail_dly;
        logic                  in_p2_p3_ntt_proc_ctrl_avail_dly;

        ntt_proc_data_t        in_p3_p2_ntt_proc_data_dly;
        logic [PSI-1:0][R-1:0] in_p3_p2_ntt_proc_avail_dly;
        logic                  in_p3_p2_ntt_proc_ctrl_avail_dly;

        //-- To regif
        pep_rif_elt_t          in_p2_p3_pep_rif_elt_dly;

        assign out_entry_bsk_procD            = in_entry_bsk_proc_dly;
        assign out_bsk_entry_procD            = in_bsk_entry_proc_dly;

        assign out_ntt_proc_cmdD              = in_ntt_proc_cmd_dly;
        assign out_ntt_proc_cmd_availD        = in_ntt_proc_cmd_avail_dly;

        assign out_p2_p3_ntt_proc_dataD       = in_p2_p3_ntt_proc_data_dly;
        assign out_p2_p3_ntt_proc_availD      = in_p2_p3_ntt_proc_avail_dly;
        assign out_p2_p3_ntt_proc_ctrl_availD = in_p2_p3_ntt_proc_ctrl_avail_dly;

        assign out_p3_p2_ntt_proc_dataD       = in_p3_p2_ntt_proc_data_dly;
        assign out_p3_p2_ntt_proc_availD      = in_p3_p2_ntt_proc_avail_dly;
        assign out_p3_p2_ntt_proc_ctrl_availD = in_p3_p2_ntt_proc_ctrl_avail_dly;

        always_ff @(posedge prc_clk)
          if (!prc_srst_n_part[0]) begin
            in_ntt_proc_cmd_avail_dly        <= '0;
            in_entry_bsk_proc_dly            <= '0;
          end
          else begin
            in_ntt_proc_cmd_avail_dly        <= in_ntt_proc_cmd_avail;
            in_entry_bsk_proc_dly            <= in_entry_bsk_proc;
          end

        always_ff @(posedge prc_clk)
          if (!prc_srst_n_part[1]) begin
            in_p2_p3_ntt_proc_avail_dly      <= '0;
            in_p2_p3_ntt_proc_ctrl_avail_dly <= '0;
            in_p2_p3_pep_rif_elt_dly         <= '0;
          end
          else begin
            in_p2_p3_ntt_proc_avail_dly      <= in_p2_p3_ntt_proc_avail     ;
            in_p2_p3_ntt_proc_ctrl_avail_dly <= in_p2_p3_ntt_proc_ctrl_avail;
            in_p2_p3_pep_rif_elt_dly         <= in_p2_p3_pep_rif_elt;
          end

        always_ff @(posedge prc_clk)
          if (!prc_srst_n_part[2]) begin
            in_bsk_entry_proc_dly            <= '0;
            in_p3_p2_ntt_proc_avail_dly      <= '0;
            in_p3_p2_ntt_proc_ctrl_avail_dly <= '0;
          end
          else begin
            in_bsk_entry_proc_dly            <= in_bsk_entry_proc;
            in_p3_p2_ntt_proc_avail_dly      <= in_p3_p2_ntt_proc_avail     ;
            in_p3_p2_ntt_proc_ctrl_avail_dly <= in_p3_p2_ntt_proc_ctrl_avail;
          end

        always_ff @(posedge prc_clk) begin
          in_ntt_proc_cmd_dly        <= in_ntt_proc_cmd;
        end

        always_ff @(posedge prc_clk) begin
          in_p2_p3_ntt_proc_data_dly <= in_p2_p3_ntt_proc_data;
        end

        always_ff @(posedge prc_clk) begin
          in_p3_p2_ntt_proc_data_dly <= in_p3_p2_ntt_proc_data;
        end
      end
      else begin
        $fatal(1,"> ERROR: Unsupported INTER_PART_PIPE (%0d) > 2", INTER_PART_PIPE);
      end

    end
    else begin : gen_no_inter_part_pipe
      assign out_entry_bsk_proc             = in_entry_bsk_proc;
      assign out_bsk_entry_proc             = in_bsk_entry_proc;

      assign out_ntt_proc_cmd               = in_ntt_proc_cmd;
      assign out_ntt_proc_cmd_avail         = in_ntt_proc_cmd_avail;

      assign out_p2_p3_ntt_proc_data        = in_p2_p3_ntt_proc_data;
      assign out_p2_p3_ntt_proc_avail       = in_p2_p3_ntt_proc_avail;
      assign out_p2_p3_ntt_proc_ctrl_avail  = in_p2_p3_ntt_proc_ctrl_avail;

      assign out_p3_p2_ntt_proc_data        = in_p3_p2_ntt_proc_data;
      assign out_p3_p2_ntt_proc_avail       = in_p3_p2_ntt_proc_avail;
      assign out_p3_p2_ntt_proc_ctrl_avail  = in_p3_p2_ntt_proc_ctrl_avail;

      assign out_p2_p3_pep_rif_elt          = in_p2_p3_pep_rif_elt;

      assign out_p1_prc_interrupt           = in_p1_prc_interrupt;
      assign out_p1_cfg_interrupt           = in_p1_cfg_interrupt;
      assign out_p3_prc_interrupt           = in_p3_prc_interrupt;
      assign out_p3_cfg_interrupt           = in_p3_cfg_interrupt;
    end
  endgenerate

// ============================================================================================== --
// Tie unused AXI channels
// ============================================================================================== --
  generate
    if (PEM_PC < PEM_PC_MAX) begin : gen_tie_unused_pem_pc
      `HPU_AXI4_TIE_WR_UNUSED(pem, [PEM_PC_MAX-1:PEM_PC])
      `HPU_AXI4_TIE_RD_UNUSED(pem, [PEM_PC_MAX-1:PEM_PC])
    end
    if (GLWE_PC < GLWE_PC_MAX) begin : gen_tie_unused_glwe_pc
      `HPU_AXI4_TIE_WR_UNUSED(glwe, [GLWE_PC_MAX-1:GLWE_PC])
      `HPU_AXI4_TIE_RD_UNUSED(glwe, [GLWE_PC_MAX-1:GLWE_PC])
    end
    if (BSK_PC < BSK_PC_MAX) begin : gen_tie_unused_bsk_pc
      `HPU_AXI4_TIE_WR_UNUSED(bsk, [BSK_PC_MAX-1:BSK_PC])
      `HPU_AXI4_TIE_RD_UNUSED(bsk, [BSK_PC_MAX-1:BSK_PC])
    end
    if (KSK_PC < KSK_PC_MAX) begin : gen_tie_unused_ksk_pc
      `HPU_AXI4_TIE_WR_UNUSED(ksk, [KSK_PC_MAX-1:KSK_PC])
      `HPU_AXI4_TIE_RD_UNUSED(ksk, [KSK_PC_MAX-1:KSK_PC])
    end
  endgenerate

// ============================================================================================== --
// hpu_3parts_1in3
// ============================================================================================== --
  hpu_3parts_1in3_core
  #(
    .AXI4_TRC_ADD_W    (AXI4_TRC_ADD_W),
    .AXI4_PEM_ADD_W    (AXI4_PEM_ADD_W),
    .AXI4_GLWE_ADD_W   (AXI4_GLWE_ADD_W),
    .AXI4_KSK_ADD_W    (AXI4_KSK_ADD_W),
    .VERSION_MAJOR     (VERSION_MAJOR),
    .VERSION_MINOR     (VERSION_MINOR)
  ) hpu_3parts_1in3_core (
    .prc_clk                 (prc_clk),
    .prc_srst_n              (prc_srst_n_part[0]),

    .cfg_clk                 (cfg_clk),
    .cfg_srst_n              (cfg_srst_n),

    .interrupt                ({in_p1_cfg_interrupt,in_p1_prc_interrupt}),

    //== Axi4-lite slave @prc_clk and @cfg_clk
    `HPU_AXIL_INSTANCE(prc,prc_1in3)
    `HPU_AXIL_INSTANCE(cfg,cfg_1in3)

    //== Axi4 trace interface
    `HPU_AXI4_FULL_INSTANCE(trc, trc,,)

    //== Axi4 PEM interface
    `HPU_AXI4_FULL_INSTANCE(pem, pem,,[PEM_PC-1:0])

    //== Axi4 GLWE interface
    `HPU_AXI4_FULL_INSTANCE(glwe, glwe,,[GLWE_PC-1:0])

    //== Axi4 KSK interface
    `HPU_AXI4_FULL_INSTANCE(ksk, ksk,,[KSK_PC-1:0])

    .isc_dop                   (s1_isc_dop),
    .isc_dop_rdy               (s1_isc_dop_rdy),
    .isc_dop_vld               (s1_isc_dop_vld),

    .isc_ack                   (s1_isc_ack),
    .isc_ack_rdy               (s1_isc_ack_rdy),
    .isc_ack_vld               (s1_isc_ack_vld),

    .entry_bsk_proc            (in_entry_bsk_proc),
    .bsk_entry_proc            (out_bsk_entry_proc),

    .ntt_proc_cmd              (in_ntt_proc_cmd),
    .ntt_proc_cmd_avail        (in_ntt_proc_cmd_avail),

    .decomp_ntt_data_avail      (in_decomp_ntt_ctrl.data_avail     ),
    .decomp_ntt_data            (in_decomp_ntt_data.data           ),
    .decomp_ntt_sob             (in_decomp_ntt_data.sob            ),
    .decomp_ntt_eob             (in_decomp_ntt_data.eob            ),
    .decomp_ntt_sog             (in_decomp_ntt_data.sog            ),
    .decomp_ntt_eog             (in_decomp_ntt_data.eog            ),
    .decomp_ntt_sol             (in_decomp_ntt_data.sol            ),
    .decomp_ntt_eol             (in_decomp_ntt_data.eol            ),
    .decomp_ntt_pbs_id          (in_decomp_ntt_data.pbs_id         ),
    .decomp_ntt_last_pbs        (in_decomp_ntt_data.last_pbs       ),
    .decomp_ntt_full_throughput (in_decomp_ntt_data.full_throughput),
    .decomp_ntt_ctrl_avail      (in_decomp_ntt_ctrl.ctrl_avail     ),

    .ntt_acc_modsw_data_avail   (out_ntt_acc_modsw_ctrl.data_avail ),
    .ntt_acc_modsw_ctrl_avail   (out_ntt_acc_modsw_ctrl.ctrl_avail ),
    .ntt_acc_modsw_data         (out_ntt_acc_modsw_data.data       ),
    .ntt_acc_modsw_sob          (out_ntt_acc_modsw_data.sob        ),
    .ntt_acc_modsw_eob          (out_ntt_acc_modsw_data.eob        ),
    .ntt_acc_modsw_sol          (out_ntt_acc_modsw_data.sol        ),
    .ntt_acc_modsw_eol          (out_ntt_acc_modsw_data.eol        ),
    .ntt_acc_modsw_sog          (out_ntt_acc_modsw_data.sog        ),
    .ntt_acc_modsw_eog          (out_ntt_acc_modsw_data.eog        ),
    .ntt_acc_modsw_pbs_id       (out_ntt_acc_modsw_data.pbs_id     )
  );

// ============================================================================================== --
// hpu_3parts_2in3
// ============================================================================================== --
  hpu_3parts_2in3_core
  #(
    .AXI4_TRC_ADD_W    (AXI4_TRC_ADD_W),
    .AXI4_PEM_ADD_W    (AXI4_PEM_ADD_W),
    .AXI4_GLWE_ADD_W   (AXI4_GLWE_ADD_W),
    .AXI4_BSK_ADD_W    (AXI4_BSK_ADD_W),
    .AXI4_KSK_ADD_W    (AXI4_KSK_ADD_W),

    .VERSION_MAJOR     (VERSION_MAJOR),
    .VERSION_MINOR     (VERSION_MINOR)
  ) hpu_3parts_2in3_core (
    .prc_clk                    (prc_clk),
    .prc_srst_n                 (prc_srst_n_part[1]),

    .cfg_clk                    (cfg_clk),
    .cfg_srst_n                 (cfg_srst_n),

    .decomp_ntt_data_avail      (out_decomp_ntt_ctrl.data_avail),
    .decomp_ntt_data            (out_decomp_ntt_data.data),
    .decomp_ntt_sob             (out_decomp_ntt_data.sob),
    .decomp_ntt_eob             (out_decomp_ntt_data.eob),
    .decomp_ntt_sog             (out_decomp_ntt_data.sog),
    .decomp_ntt_eog             (out_decomp_ntt_data.eog),
    .decomp_ntt_sol             (out_decomp_ntt_data.sol),
    .decomp_ntt_eol             (out_decomp_ntt_data.eol),
    .decomp_ntt_pbs_id          (out_decomp_ntt_data.pbs_id),
    .decomp_ntt_last_pbs        (out_decomp_ntt_data.last_pbs),
    .decomp_ntt_full_throughput (out_decomp_ntt_data.full_throughput),
    .decomp_ntt_ctrl_avail      (out_decomp_ntt_ctrl.ctrl_avail),

    .ntt_acc_modsw_data_avail   (in_ntt_acc_modsw_ctrl.data_avail),
    .ntt_acc_modsw_ctrl_avail   (in_ntt_acc_modsw_ctrl.ctrl_avail),
    .ntt_acc_modsw_data         (in_ntt_acc_modsw_data.data),
    .ntt_acc_modsw_sob          (in_ntt_acc_modsw_data.sob),
    .ntt_acc_modsw_eob          (in_ntt_acc_modsw_data.eob),
    .ntt_acc_modsw_sol          (in_ntt_acc_modsw_data.sol),
    .ntt_acc_modsw_eol          (in_ntt_acc_modsw_data.eol),
    .ntt_acc_modsw_sog          (in_ntt_acc_modsw_data.sog),
    .ntt_acc_modsw_eog          (in_ntt_acc_modsw_data.eog),
    .ntt_acc_modsw_pbs_id       (in_ntt_acc_modsw_data.pbs_id),

    .p2_p3_ntt_proc_data        (in_p2_p3_ntt_proc_data),
    .p2_p3_ntt_proc_avail       (in_p2_p3_ntt_proc_avail),
    .p2_p3_ntt_proc_ctrl_avail  (in_p2_p3_ntt_proc_ctrl_avail),

    .p3_p2_ntt_proc_data        (out_p3_p2_ntt_proc_data),
    .p3_p2_ntt_proc_avail       (out_p3_p2_ntt_proc_avail),
    .p3_p2_ntt_proc_ctrl_avail  (out_p3_p2_ntt_proc_ctrl_avail),

    .ntt_proc_cmd               (out_ntt_proc_cmd),
    .ntt_proc_cmd_avail         (out_ntt_proc_cmd_avail),

    .pep_rif_elt                (in_p2_p3_pep_rif_elt)
  );

// ============================================================================================== --
// hpu_3parts_3in3
// ============================================================================================== --
  hpu_3parts_3in3_core
  #(
    .AXI4_TRC_ADD_W    (AXI4_TRC_ADD_W),
    .AXI4_PEM_ADD_W    (AXI4_PEM_ADD_W),
    .AXI4_GLWE_ADD_W   (AXI4_GLWE_ADD_W),
    .AXI4_BSK_ADD_W    (AXI4_BSK_ADD_W),
    .AXI4_KSK_ADD_W    (AXI4_KSK_ADD_W),

    .VERSION_MAJOR     (VERSION_MAJOR),
    .VERSION_MINOR     (VERSION_MINOR)
  ) hpu_3parts_3in3_core (
    .prc_clk                  (prc_clk),
    .prc_srst_n               (prc_srst_n_part[2]),

    .cfg_clk                  (cfg_clk),
    .cfg_srst_n               (cfg_srst_n),

    .interrupt                ({in_p3_cfg_interrupt,in_p3_prc_interrupt}),

    //== Axi4-lite slave @prc_clk and @cfg_clk
    `HPU_AXIL_INSTANCE(prc,prc_3in3)
    `HPU_AXIL_INSTANCE(cfg,cfg_3in3)

    //== Axi4 BSK interface
    `HPU_AXI4_FULL_INSTANCE(bsk, bsk,,[BSK_PC-1:0])

    .p2_p3_ntt_proc_data       (out_p2_p3_ntt_proc_data),
    .p2_p3_ntt_proc_avail      (out_p2_p3_ntt_proc_avail),
    .p2_p3_ntt_proc_ctrl_avail (out_p2_p3_ntt_proc_ctrl_avail),

    .p3_p2_ntt_proc_data       (in_p3_p2_ntt_proc_data),
    .p3_p2_ntt_proc_avail      (in_p3_p2_ntt_proc_avail),
    .p3_p2_ntt_proc_ctrl_avail (in_p3_p2_ntt_proc_ctrl_avail),

    .ntt_proc_cmd              (out_ntt_proc_cmd),
    .ntt_proc_cmd_avail        (out_ntt_proc_cmd_avail),

    .entry_bsk_proc            (out_entry_bsk_proc),
    .bsk_entry_proc            (in_bsk_entry_proc),

    .p2_p3_pep_rif_elt         (out_p2_p3_pep_rif_elt)
  );

endmodule
