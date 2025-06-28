// ==============================================================================================
// BSD 3-Clause Clear License
// Copyright © 2025 ZAMA. All rights reserved.
// ----------------------------------------------------------------------------------------------
// Description  :
// ----------------------------------------------------------------------------------------------
// A simple synchronizer
// Make sure the DEPTH is good enough for the desired MTBF. This might be harder said than done
// since one would have to find the flop settling probability from Xilinx, so exagerate.
// ==============================================================================================

// No cross hierarchy optimizations
(* keep_hierarchy = "yes" *)
module hpu_sync #(
  parameter int unsigned WIDTH = 1,
  parameter int unsigned DEPTH = 3,
  parameter              RST_VAL = 1'b0
) (
  input  logic             clk,
  input  logic             s_rst_n,
  input  logic [WIDTH-1:0] in,
  output logic [WIDTH-1:0] out
);

  generate
    if((unsigned'($bits(RST_VAL))) != WIDTH) begin: __BAD_WIDTH
      $fatal(1, "Error: RST_VAL %0d width must match the WIDTH parameter: %0d",
        RST_VAL, WIDTH);
    end

    if(DEPTH < 1) begin: __BAD_DEPTH
      $fatal(1, "Error: Cannot have a synchronizer with no depth.");
    end
  endgenerate

  generate for(genvar i = 0; i < WIDTH; i++) begin: gen_bit
    logic [DEPTH-1:0] d;
    logic [DEPTH-1:0] q;

    if (DEPTH > 1) begin: depth_gt2
      assign d   = {q[DEPTH-2:0], in};
      assign out = q[DEPTH-1];
    end else begin: depth_eq1
      assign d[0] = in;
      assign out  = q[0];
    end

    // Directly instantiate registers and assign them to the same slice for maximum MTBF
    for(genvar u = 0; u < DEPTH; u++) begin: depth
      if(RST_VAL[i]) begin: set
        (* DONT_TOUCH = "TRUE", RLOC="X0Y0" *)
        FDSE #(
          .INIT          ( 1'b1 ) ,
          .IS_S_INVERTED ( 1'b1 )
        ) ff (
          .C  ( clk     ) ,
          .S  ( s_rst_n ) ,
          .CE ( 1'b1    ) ,
          .D  ( d[u]    ) ,
          .Q  ( q[u]    )
        );
      end else begin: reset
        (* DONT_TOUCH = "TRUE", RLOC="X0Y0" *)
        FDRE #(
          .INIT          ( 1'b0 ) ,
          .IS_R_INVERTED ( 1'b1 )
        ) ff (
          .C  ( clk     ) ,
          .R  ( s_rst_n ) ,
          .CE ( 1'b1    ) ,
          .D  ( d[u]    ) ,
          .Q  ( q[u]    )
        );
      end
    end
  end endgenerate

endmodule
