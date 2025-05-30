
// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// RAM wrapper.
// RAM interface for one N+1 port RAM, with N read ports and 1 write port, single clock.
// These are mostly mapped to LUTRAMs in FPGA devices.
//
// Parameters :
// WIDTH             : Data width
// DEPTH             : RAM depth (number of words in RAM)
// RD_WR_ACCESS_TYPE : Behavior when there is a read and write access conflict.
//                     0 : output 'X'
//                     1 : Read old value - BRAM default behaviour
//                     2 : Read new value
// KEEP_RD_DATA      : Read data is kept until the next read request.
// RAM_LATENCY       : RAM read latency. Can be zero
// RD_PORT_NB        : Number of read ports
// HAS_RST           : The whole RAM can be synchronously reset
// RST_VAL           : The reset value for when HAS_RST == 1'b1
// ==============================================================================================

module ram_wrapper_NR1W #(
  parameter int         WIDTH             = 8,
  parameter int         DEPTH             = 512,
  parameter int         RD_WR_ACCESS_TYPE = 1,
  parameter bit         KEEP_RD_DATA      = 1,
  parameter int         RAM_LATENCY       = 0,
  parameter int         RD_PORT_NB        = 1,
  parameter bit         HAS_RST           = 1'b0,
  parameter [WIDTH-1:0] RST_VAL           = '0
)
(
  input                            clk,        // clock
  input                            s_rst_n,    // Synchronous reset

  // Write port
  input  logic                     wr_en,
  input  logic [$clog2(DEPTH)-1:0] wr_add,
  input  logic [WIDTH-1:0]         wr_data,

  // Read ports
  input  logic                     rd_en   [RD_PORT_NB],
  input  logic [$clog2(DEPTH)-1:0] rd_add  [RD_PORT_NB],
  output logic [WIDTH-1:0]         rd_data [RD_PORT_NB]
);

// ============================================================================================== --
// ram_wrapper_NR1W
// ============================================================================================== --
// TODO : Use generate to choose the RAM to be instantiated.

// ---------------------------------------------------------------------------------------------- --
// For FPGA
// ---------------------------------------------------------------------------------------------- --
  ram_NR1W_behav #(
    .WIDTH             ( WIDTH             ) ,
    .DEPTH             ( DEPTH             ) ,
    .RD_WR_ACCESS_TYPE ( RD_WR_ACCESS_TYPE ) ,
    .KEEP_RD_DATA      ( KEEP_RD_DATA      ) ,
    .RAM_LATENCY       ( RAM_LATENCY       ) ,
    .RD_PORT_NB        ( RD_PORT_NB        ) ,
    .HAS_RST           ( HAS_RST           ) ,
    .RST_VAL           ( RST_VAL           )
  ) ram_prim (
    .clk      ( clk     ) ,
    .s_rst_n  ( s_rst_n ) ,
    .wr_en    ( wr_en    ) ,
    .wr_add   ( wr_add   ) ,
    .wr_data  ( wr_data  ) ,
    .rd_en    ( rd_en    ) ,
    .rd_add   ( rd_add   ) ,
    .rd_data  ( rd_data  )
  );

endmodule
