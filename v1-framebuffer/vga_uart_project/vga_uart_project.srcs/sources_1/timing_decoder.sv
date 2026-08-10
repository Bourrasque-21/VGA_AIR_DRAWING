`timescale 1ns / 1ps
module timing_decoder (
    input  [9:0] i_hcount,
    input  [9:0] i_vcount,
    output       o_hsync,
    output       o_vsync,
    output       o_display_en
);

  parameter int WIDTH = 640, HEIGHT = 480;
  parameter int H_FRONT = 16, H_SYNC = 96, H_BACK = 48;
  parameter int V_FRONT = 10, V_SYNC = 2, V_BACK = 29;

  assign o_display_en = (i_hcount < WIDTH) && (i_vcount < HEIGHT);
  assign o_hsync = ~((i_hcount > (WIDTH + H_FRONT-1)) && (i_hcount < (WIDTH + H_FRONT + H_SYNC)));  // 656~751
  assign o_vsync = ~((i_vcount > (HEIGHT + V_FRONT-1)) && (i_vcount < (HEIGHT + V_FRONT + V_SYNC))); // 490~491

endmodule
