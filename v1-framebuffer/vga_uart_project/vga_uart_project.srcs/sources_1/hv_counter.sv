`timescale 1ns / 1ps
module hv_counter (
    input              clk,
    input              rst,
    input              i_pclk,
    output logic [9:0] o_hcount,
    output logic [9:0] o_vcount
);

  parameter int unsigned H_WIDTH = 800, V_WIDTH = 521;

  always_ff @(posedge clk, posedge rst) begin
    if (rst) begin
      o_hcount <= 0;
      o_vcount <= 0;
    end else begin
      if (i_pclk) begin
        if (o_hcount == H_WIDTH - 1) begin
          o_hcount <= 0;
          if (o_vcount == V_WIDTH - 1) o_vcount <= 0;
          else o_vcount <= o_vcount + 1;
        end else begin
          o_hcount <= o_hcount + 1;
        end
      end
    end
  end
endmodule
