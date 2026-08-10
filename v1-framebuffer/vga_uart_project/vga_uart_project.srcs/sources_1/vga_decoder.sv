`timescale 1ns / 1ps
module vga_decoder (
    input        clk,
    input        rst,
    input        i_pclk,
    output       o_hsync,
    output       o_vsync,
    output       o_display_en,
    output [9:0] o_x,
    output [9:0] o_y
);

  logic [9:0] hcount, vcount;

  assign o_x = hcount;
  assign o_y = vcount;


  hv_counter U_HV_COUNTER (
      .clk     (clk),
      .rst     (rst),
      .i_pclk  (i_pclk),
      .o_hcount(hcount),
      .o_vcount(vcount)
  );

  timing_decoder U_TIMING_DECODER (
      .i_hcount(hcount),
      .i_vcount(vcount),
      .o_hsync (o_hsync),
      .o_vsync (o_vsync),
        .o_display_en(o_display_en)
  );

endmodule
