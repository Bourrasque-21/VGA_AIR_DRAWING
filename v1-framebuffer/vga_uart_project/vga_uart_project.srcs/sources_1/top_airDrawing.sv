`timescale 1ns / 1ps

module top_airDrawing (
    input logic clk, input logic reset,
    input logic pclk, input logic href, input logic vsync, input logic [7:0] pdata,
    output logic xclk, output logic h_sync, output logic v_sync,
    output logic [3:0] port_red, output logic [3:0] port_green, output logic [3:0] port_blue,
    input logic start_btn, input logic clear_btn, output logic scl, inout logic sda,
    // 펜 제어 버튼 (btnU=모드 순환, btnD=두께, btnL=지우개)
    input logic btn_pen_mode, input logic btn_pen_size, input logic btn_eraser,
    output logic tx,
    input  logic rx
);
    logic tick_25, clk_25, de;
    logic [9:0] x_pixel, y_pixel;
    logic frame_we;
    logic [$clog2(320 * 240)-1:0] frame_waddr;
    logic [15:0] frame_wdata;
    logic [11:0] qvga_rgb;
    logic [8:0] x_center, y_center;
    logic uart_send_trigger;

    // UART 수신 펜 설정 (pen_config_controller가 상태 소유)
    logic       rx_packet_valid;
    logic [2:0] rx_pen_color;
    logic       rx_eraser, rx_size, rx_texture_enable, rx_paper, rx_freeze, rx_clear_pulse;
    logic [2:0] rx_texture_shape;

    logic [2:0] pen_color;
    logic       pen_eraser, pen_size, pen_texture_enable, pen_paper, pen_freeze;
    logic [2:0] pen_texture_shape;
    logic       uart_clear;
    logic       canvas_clear;
    logic       btn_mode_pulse, btn_size_pulse, btn_eraser_pulse;

    assign xclk = clk_25;
    assign uart_send_trigger = vsync;
    assign canvas_clear = clear_btn | uart_clear;

    clock_gen U_CLOCK_GEN (
        .clk(clk), .rst(reset), .o_tick_25(tick_25), .o_clk_25(clk_25)
    );

    vga_decoder U_VGA_DECODER (
        .clk(clk), .rst(reset), .i_pclk(tick_25),
        .o_hsync(h_sync), .o_vsync(v_sync), .o_display_en(de),
        .o_x(x_pixel), .o_y(y_pixel)
    );

    top_ov7670 U_TOP_OV7670 (
        .i_clk(clk), .i_rst(reset), .i_tick_25(tick_25), .i_start_btn(start_btn),
        .o_scl(scl), .io_sda(sda), .i_camera_pclk(pclk),
        .i_camera_href(href), .i_camera_vsync(vsync), .i_camera_data(pdata),
        .o_frame_write_enable(frame_we), .o_frame_write_addr(frame_waddr),
        .o_frame_write_data(frame_wdata)
    );

    top_buffer U_TOP_BUFFER (
        .i_rst(reset), .i_vsync(vsync),
        .i_pen_color(pen_color),
        .i_eraser(pen_eraser), .i_size(pen_size),
        .i_texture_enable(pen_texture_enable),
        .i_texture_shape(pen_texture_shape), .i_paper(pen_paper),
        .i_freeze(pen_freeze),
        .i_canvas_clear(canvas_clear),
        .i_write_clk(pclk), .i_write_enable(frame_we), .i_write_addr(frame_waddr),
        .i_write_data(frame_wdata), .i_read_clk(clk), .i_display_enable(de),
        .i_x_pixel(x_pixel), .i_y_pixel(y_pixel),
        .o_qvga_pixel_rgb(qvga_rgb),
        .o_x_center(x_center), .o_y_center(y_center)
    );

    assign {port_red, port_green, port_blue} = qvga_rgb;

    uart_packet_decoder #(.CLK_FREQ(100_000_000), .BAUD_RATE(115_200)) U_UART_PACKET_DECODER (
        .clk(clk), .rst(reset), .rx(rx),
        .o_pen_color(rx_pen_color), .o_eraser(rx_eraser), .o_size(rx_size),
        .o_texture_enable(rx_texture_enable), .o_texture_shape(rx_texture_shape),
        .o_paper(rx_paper), .o_freeze(rx_freeze), .o_clear_pulse(rx_clear_pulse),
        .o_packet_valid(rx_packet_valid)
    );

    button_debounce U_BTN_MODE (
        .clk(clk), .rst(reset), .btn_in(btn_pen_mode), .pulse(btn_mode_pulse)
    );
    button_debounce U_BTN_SIZE (
        .clk(clk), .rst(reset), .btn_in(btn_pen_size), .pulse(btn_size_pulse)
    );
    button_debounce U_BTN_ERASER (
        .clk(clk), .rst(reset), .btn_in(btn_eraser), .pulse(btn_eraser_pulse)
    );

    pen_config_controller U_PEN_CONFIG_CONTROLLER (
        .clk(clk), .rst(reset),
        .i_uart_valid(rx_packet_valid),
        .i_uart_pen_color(rx_pen_color), .i_uart_eraser(rx_eraser),
        .i_uart_size(rx_size), .i_uart_texture_enable(rx_texture_enable),
        .i_uart_texture_shape(rx_texture_shape), .i_uart_paper(rx_paper),
        .i_uart_freeze(rx_freeze), .i_uart_clear_pulse(rx_clear_pulse),
        .i_btn_eraser(btn_eraser_pulse), .i_btn_mode(btn_mode_pulse),
        .i_btn_size(btn_size_pulse),
        .o_pen_color(pen_color), .o_eraser(pen_eraser), .o_size(pen_size),
        .o_texture_enable(pen_texture_enable), .o_texture_shape(pen_texture_shape),
        .o_paper(pen_paper), .o_freeze(pen_freeze), .o_clear(uart_clear)
    );

    // TX는 스위치 원본이 아니라 실효 상태(pen_config_controller)를 보고한다.
    uart_packet_sender #(.CLK_FREQ(100_000_000), .BAUD_RATE(115_200)) U_UART_PACKET_SENDER (
        .clk(clk), .rst(reset), .send_trigger(uart_send_trigger),
        .X_center(x_center), .Y_center(y_center),
        .sw_paint_red(pen_color[2]), .sw_paint_green(pen_color[1]),
        .sw_paint_blue(pen_color[0]), .sw_eraser(pen_eraser), .sw_size(pen_size),
        .sw_texture_enable(pen_texture_enable), .texture_shape(pen_texture_shape),
        .paper(pen_paper), .freeze(pen_freeze),
        .clear_btn(canvas_clear), .tx(tx), .busy()
    );
endmodule
