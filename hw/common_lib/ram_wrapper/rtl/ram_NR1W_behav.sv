// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
//
// Behavioral RAM : NR1W RAM.
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
// RD_PORT_NB        : The number of read ports
// HAS_RST           : The whole RAM can be synchronously reset
// RST_VAL           : The reset value for when HAS_RST == 1'b1
//
// ==============================================================================================

module ram_NR1W_behav #(
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
  input                     clk,        // clock
  input                     s_rst_n,    // synchronous reset

  // Write port
  input                     wr_en,
  input [$clog2(DEPTH)-1:0] wr_add,
  input [WIDTH-1:0]         wr_data,

  // Read port
  input                     rd_en   [RD_PORT_NB],
  input [$clog2(DEPTH)-1:0] rd_add  [RD_PORT_NB],
  output [WIDTH-1:0]        rd_data [RD_PORT_NB] // available RAM_LATENCY cycles after rd_en
);

// ============================================================================================== --
// localparam
// ============================================================================================== --
  localparam int RD_WR_ACCESS_TYPE_CONFLICT = 0;
  localparam int RD_WR_ACCESS_TYPE_READ_OLD = 1;
  localparam int RD_WR_ACCESS_TYPE_READ_NEW = 2;

  localparam int RAM_LAT_LOCAL = RAM_LATENCY - 1;
  localparam int RAM_LAT_IN  = RAM_LAT_LOCAL / 2;
  localparam int RAM_LAT_OUT = (RAM_LAT_LOCAL+1)/2;

// ============================================================================================== --
// Check parameter
// ============================================================================================== --
// pragma translate_off
  initial begin
    assert_valid_access_type:
    assert (RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_CONFLICT
        || RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_READ_OLD
        || RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_READ_NEW)
    else $error("> ERROR: Unsupported RAM access type : %d", RD_WR_ACCESS_TYPE);
  end
// pragma translate_on

// ============================================================================================== --
// Input pipe
// ============================================================================================== --
  logic                     in_rd_en  [RD_PORT_NB];
  logic [$clog2(DEPTH)-1:0] in_rd_add [RD_PORT_NB];

  logic                     in_wr_en;
  logic [$clog2(DEPTH)-1:0] in_wr_add;
  logic [WIDTH-1:0]         in_wr_data;

  generate
    if (RAM_LAT_IN > 0) begin : gen_in_pip
      logic [RAM_LAT_IN-1:0]                    in_wr_en_sr;
      logic [RAM_LAT_IN-1:0][$clog2(DEPTH)-1:0] in_wr_add_sr;
      logic [RAM_LAT_IN-1:0][WIDTH-1:0]         in_wr_data_sr;

      logic [RAM_LAT_IN-1:0]                    in_wr_en_srD;
      logic [RAM_LAT_IN-1:0][$clog2(DEPTH)-1:0] in_wr_add_srD;
      logic [RAM_LAT_IN-1:0][WIDTH-1:0]         in_wr_data_srD;

      assign in_wr_en   = in_wr_en_sr[RAM_LAT_IN-1];
      assign in_wr_add  = in_wr_add_sr[RAM_LAT_IN-1];
      assign in_wr_data = in_wr_data_sr[RAM_LAT_IN-1];

      assign in_wr_en_srD[0]   = wr_en;
      assign in_wr_add_srD[0]  = wr_add;
      assign in_wr_data_srD[0] = wr_data;

      if (RAM_LAT_IN > 1) begin : gen_ram_lat_in_gt_1
        assign in_wr_en_srD[RAM_LAT_IN-1:1]   = in_wr_en_sr[RAM_LAT_IN-2:0];
        assign in_wr_add_srD[RAM_LAT_IN-1:1]  = in_wr_add_sr[RAM_LAT_IN-2:0];
        assign in_wr_data_srD[RAM_LAT_IN-1:1] = in_wr_data_sr[RAM_LAT_IN-2:0];
      end

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          in_wr_en_sr <= '0;
        end else begin
          in_wr_en_sr <= in_wr_en_srD;
        end

      always_ff @(posedge clk) begin
        in_wr_add_sr   <= in_wr_add_srD;
        in_wr_data_sr  <= in_wr_data_srD;
      end

      // Read Ports
      for(genvar i = 0; i < RD_PORT_NB; i++) begin: read_port_in
        logic [RAM_LAT_IN-1:0]                    in_rd_en_sr;
        logic [RAM_LAT_IN-1:0][$clog2(DEPTH)-1:0] in_rd_add_sr;
        logic [RAM_LAT_IN-1:0]                    in_rd_en_srD;
        logic [RAM_LAT_IN-1:0][$clog2(DEPTH)-1:0] in_rd_add_srD;

        assign in_rd_en_srD[0]   = rd_en[i];
        assign in_rd_add_srD[0]  = rd_add[i];

        if (RAM_LAT_IN > 1) begin : gen_ram_lat_in_gt_1
          assign in_rd_en_srD[RAM_LAT_IN-1:1]  = in_rd_en_sr[RAM_LAT_IN-2:0];
          assign in_rd_add_srD[RAM_LAT_IN-1:1] = in_rd_add_sr[RAM_LAT_IN-2:0];
        end

        always_ff @(posedge clk)
          if (!s_rst_n) begin
            in_rd_en_sr <= '0;
          end else begin
            in_rd_en_sr <= in_rd_en_srD;
          end

        always_ff @(posedge clk) begin
          in_rd_add_sr <= in_rd_add_srD;
        end

        assign in_rd_en[i]  = in_rd_en_sr[RAM_LAT_IN-1];
        assign in_rd_add[i] = in_rd_add_sr[RAM_LAT_IN-1];
      end

    end
    else begin : gen_no_in_pipe
      assign in_rd_en   = rd_en;
      assign in_rd_add  = rd_add;
      assign in_wr_en   = wr_en;
      assign in_wr_add  = wr_add;
      assign in_wr_data = wr_data;
    end
  endgenerate
// ============================================================================================== --
// ram_NR1W_behav
// ============================================================================================== --
// ---------------------------------------------------------------------------------------------- --
// RAM NR1W core
// ---------------------------------------------------------------------------------------------- --
  // Note :
  //  - If access conflict will read the old value.
  //  - Has no read latency
  logic [WIDTH-1:0] datar_tmp [RD_PORT_NB];
  ram_NR1W_behav_core #(
    .WIDTH      ( WIDTH      ) ,
    .DEPTH      ( DEPTH      ) ,
    .RD_PORT_NB ( RD_PORT_NB ) ,
    .HAS_RST    ( HAS_RST    ) ,
    .RST_VAL    ( RST_VAL    )
  )
  ram_NR1W_core
  (
    .clk     ( clk        ) ,
    .s_rst_n ( s_rst_n    ) ,

    .rd_add  ( in_rd_add  ) ,
    .rd_data ( datar_tmp  ) ,

    .wr_en   ( in_wr_en   ) ,
    .wr_add  ( in_wr_add  ) ,
    .wr_data ( in_wr_data )
  );

// ---------------------------------------------------------------------------------------------- --
// Data management
// ---------------------------------------------------------------------------------------------- --
  generate for(genvar rd_port = 0; rd_port < RD_PORT_NB; rd_port++) begin: read_port
    logic [WIDTH-1:0] datar_tmp2;

    if (RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_READ_OLD) begin : rd_wr_access_type_read_old_gen
      assign datar_tmp2 = datar_tmp[rd_port];
    end
    else begin : no_rd_wr_access_type_read_old_gen
      logic             access_conflict;
      logic             access_conflictD;

      assign access_conflictD = in_wr_en & in_rd_en[rd_port] & (in_wr_add == in_rd_add[rd_port]);

      always_ff @(posedge clk)
        if (!s_rst_n) begin
          access_conflict <= 1'b0;
        end
        else begin
          access_conflict <= access_conflictD;
        end

      if (RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_CONFLICT) begin : rd_wr_access_type_conflict_gen
        assign datar_tmp2 = access_conflict ? {WIDTH{1'bx}} : datar_tmp[rd_port];
      end
      else if (RD_WR_ACCESS_TYPE == RD_WR_ACCESS_TYPE_READ_NEW) begin : rd_wr_access_type_read_new_gen
        assign datar_tmp2 = access_conflict ? in_wr_data : datar_tmp[rd_port];
      end
    end

// ---------------------------------------------------------------------------------------------- --
// datar
// ---------------------------------------------------------------------------------------------- --
    logic [WIDTH-1:0] datar;

    if (KEEP_RD_DATA != 0) begin : keep_rd_data_gen
      logic [WIDTH-1:0] datar_kept;

      always_ff @(posedge clk) begin
        if(!s_rst_n && HAS_RST)
          datar_kept <= RST_VAL;
        else if (in_rd_en[rd_port])
          datar_kept <= datar_tmp2;
      end

      assign datar = in_rd_en[rd_port] ? datar_tmp2 : datar_kept;
    end
    else begin : no_keep_rd_data_gen
      assign datar = datar_tmp2;
    end

    if (RAM_LAT_OUT != 0) begin : add_ram_latency_gen
      logic [RAM_LAT_OUT-1:0][WIDTH-1:0] datar_sr;
      logic [RAM_LAT_OUT-1:0][WIDTH-1:0] datar_srD;
      logic [RAM_LAT_OUT-1:0]            datar_en_sr;
      logic [RAM_LAT_OUT-1:0]            datar_en_srD;

      assign datar_srD[0]    = in_rd_en[rd_port] ? datar : datar_sr[0];
      assign datar_en_srD[0] = in_rd_en[rd_port];

      if (RAM_LAT_OUT > 1) begin : ram_lat_out_gt_1
        assign datar_en_srD[RAM_LAT_OUT-1:1] = datar_en_sr[RAM_LAT_OUT-2:0];
        for (genvar gen_i=1; gen_i<RAM_LAT_OUT; gen_i=gen_i+1) begin: gen_data_sr
          assign datar_srD[gen_i] = datar_en_sr[gen_i-1] ? datar_sr[gen_i-1] : datar_sr[gen_i];
        end
      end

      always_ff @(posedge clk)
        if (!s_rst_n) datar_en_sr <= '0;
        else          datar_en_sr <= datar_en_srD;

      always_ff @(posedge clk)
        if(!s_rst_n && HAS_RST)
          datar_sr <= {RAM_LAT_OUT{RST_VAL}};
        else
          datar_sr <= datar_srD;

      assign rd_data[rd_port] = datar_sr[RAM_LAT_OUT-1];
    end
    else begin : no_add_ram_latency_gen
      assign rd_data[rd_port] = datar;
    end
  end endgenerate
endmodule
