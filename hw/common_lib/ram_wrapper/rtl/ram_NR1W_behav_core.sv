
// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// LUTRAM
// RAM interface for one N+1 port RAM, with N read ports and 1 write port, single clock.
//
// These are mostly mapped to LUTRAMs in Xilinx FPGA devices.
//
// Parameters :
// WIDTH             : Data width
// DEPTH             : RAM depth (number of words in RAM)
// RD_PORT_NB        : Number of read ports
// HAS_RST           : The whole RAM can be synchronously reset
// ==============================================================================================

module ram_NR1W_behav_core #(
  parameter int unsigned WIDTH      = 32,
  parameter int unsigned DEPTH      = 512,
  parameter int unsigned RD_PORT_NB = 1,
  parameter bit          HAS_RST    = 1'b0,
  parameter [WIDTH-1:0]  RST_VAL    = '0,

  localparam int unsigned ADD_W     = $clog2(DEPTH)
)
(
  input                    clk,
  input                    s_rst_n,

  // Write port
  input  logic             wr_en,
  input  logic [ADD_W-1:0] wr_add,
  input  logic [WIDTH-1:0] wr_data,

  // Read ports
  input  logic [ADD_W-1:0] rd_add  [RD_PORT_NB],
  output logic [WIDTH-1:0] rd_data [RD_PORT_NB]
);

  // You could uncomment the following line to force inference of LUTRAM
  // (* ram_style = distributed *)
  logic [WIDTH-1:0] ram [DEPTH];

  generate if(HAS_RST) begin: with_reset

    always @(posedge clk)
      if(!s_rst_n)
        for(int unsigned i = 0; i < DEPTH; i++)
          ram[i] <= RST_VAL;
      else if(wr_en)
        ram[wr_add] <= wr_data;

  end else begin: no_reset

    always @(posedge clk)
      if(wr_en)
        ram[wr_add] <= wr_data;

  end endgenerate

  generate for(genvar i = 0; i < RD_PORT_NB; i++) begin: read_port
    assign rd_data[i] = ram[rd_add[i]];
  end endgenerate

endmodule
