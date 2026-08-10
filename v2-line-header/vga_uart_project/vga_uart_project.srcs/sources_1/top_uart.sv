module top_uart (
    input  logic       clk,
    input  logic       rst,
    input  logic       i_rx,
    output logic       o_tx,
    input  logic       i_send_trigger,
    input  logic [8:0] i_x_center,
    input  logic [8:0] i_y_center,
    input  logic [2:0] i_pen_color,
    input  logic       i_pen_eraser,
    input  logic       i_pen_size,
    input  logic       i_pen_texture_enable,
    input  logic [2:0] i_pen_texture_shape,
    input  logic       i_pen_paper,
    input  logic       i_pen_freeze,
    input  logic       i_clear,
    output logic [2:0] o_rx_pen_color,
    output logic       o_rx_eraser,
    output logic       o_rx_size,
    output logic       o_rx_texture_enable,
    output logic [2:0] o_rx_texture_shape,
    output logic       o_rx_paper,
    output logic       o_rx_freeze,
    output logic       o_rx_clear_pulse,
    output logic       o_rx_packet_valid
);
  uart_packet_decoder #(
      .CLK_FREQ  (100_000_000),
      .BAUD_RATE (115_200)
  ) U_UART_PACKET_DECODER (
      .clk              (clk),
      .rst              (rst),
      .i_rx             (i_rx),
      .o_pen_color      (o_rx_pen_color),
      .o_eraser         (o_rx_eraser),
      .o_size           (o_rx_size),
      .o_texture_enable (o_rx_texture_enable),
      .o_texture_shape  (o_rx_texture_shape),
      .o_paper          (o_rx_paper),
      .o_freeze         (o_rx_freeze),
      .o_clear_pulse    (o_rx_clear_pulse),
      .o_packet_valid   (o_rx_packet_valid)
  );

  uart_packet_sender #(
      .CLK_FREQ  (100_000_000),
      .BAUD_RATE (115_200)
  ) U_UART_PACKET_SENDER (
      .clk              (clk),
      .rst              (rst),
      .i_send_trigger   (i_send_trigger),
      .i_x_center       (i_x_center),
      .i_y_center       (i_y_center),
      .i_paint_red      (i_pen_color[2]),
      .i_paint_green    (i_pen_color[1]),
      .i_paint_blue     (i_pen_color[0]),
      .i_eraser         (i_pen_eraser),
      .i_size           (i_pen_size),
      .i_texture_enable (i_pen_texture_enable),
      .i_texture_shape  (i_pen_texture_shape),
      .i_paper          (i_pen_paper),
      .i_freeze         (i_pen_freeze),
      .i_clear          (i_clear),
      .o_tx             (o_tx),
      .o_busy           ()
  );
endmodule
