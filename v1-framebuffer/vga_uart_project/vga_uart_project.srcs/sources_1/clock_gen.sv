`timescale 1ns / 1ps
module clock_gen (
    input        clk,
    input        rst,
    output logic o_tick_25,
    output logic o_clk_25
);
  logic [1:0] r_count;
  // 25 MHz one-cycle tick at a 100 MHz system clock.
  assign o_tick_25 = (r_count == 2'd3);

  // 25 MHz, 50% duty-cycle output for OV7670 XCLK.
  assign o_clk_25 = r_count[1];

  always_ff @(posedge clk, posedge rst) begin
    if (rst) begin
      //o_pclk  <= 0;
      r_count <= 0;
    end else begin
      if (r_count == 4 - 1) begin
        //o_pclk  <= 1;
        r_count <= 0;
      end else begin
        //o_pclk  <= 0;
        r_count <= r_count + 1;
      end
    end
  end
endmodule
