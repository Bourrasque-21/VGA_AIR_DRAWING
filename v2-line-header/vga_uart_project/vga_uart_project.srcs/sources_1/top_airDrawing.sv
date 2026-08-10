module top_airDrawing (
    input  logic       clk,
    input  logic       rst,
    input  logic       i_pclk,
    input  logic       i_href,
    input  logic       i_vsync,
    input  logic [7:0] i_pdata,
    input  logic       i_start_btn,
    input  logic       i_clear_btn,
    input  logic       i_btn_pen_mode,
    input  logic       i_btn_pen_size,
    input  logic       i_btn_eraser,
    input  logic       i_rx,
    output logic       o_xclk,
    output logic       o_hsync,
    output logic       o_vsync,
    output logic [3:0] o_red,
    output logic [3:0] o_green,
    output logic [3:0] o_blue,
    output logic       o_scl,
    output logic       o_tx,
    inout  logic       io_sda
);
    logic        tick_25;
    logic        xclk_24;
    logic        display_enable;
    logic [9:0]  screen_x;
    logic [9:0]  screen_y;
    logic        frame_write_enable;
    logic [18:0] frame_write_addr;
    logic [15:0] frame_write_data;
    logic [11:0] camera_rgb;
    logic [11:0] canvas_rgb;
    logic        canvas_valid;
    logic        pixel_good;
    logic        line_valid;
    logic [9:0]  source_x;
    logic [8:0]  source_y;
    logic [7:0]  source_frame_id;
    logic [11:0] vga_rgb;
    logic [8:0]  x_center;
    logic [8:0]  y_center;
    logic        rx_packet_valid;
    logic [2:0]  rx_pen_color;
    logic        rx_eraser;
    logic        rx_size;
    logic        rx_texture_enable;
    logic [2:0]  rx_texture_shape;
    logic        rx_paper;
    logic        rx_freeze;
    logic        rx_clear_pulse;
    logic [2:0]  pen_color;
    logic        pen_eraser;
    logic        pen_size;
    logic        pen_texture_enable;
    logic [2:0]  pen_texture_shape;
    logic        pen_paper;
    logic        pen_freeze;
    logic        uart_clear;
    logic        canvas_clear;
    logic        btn_mode_pulse;
    logic        btn_size_pulse;
    logic        btn_eraser_pulse;
    logic        clock_reset;
    logic        system_reset;
    logic        system_reset_pclk;
    logic        camera_vsync;

    assign o_xclk = xclk_24;
    assign canvas_clear = i_clear_btn | uart_clear | system_reset_pclk;
    assign {o_red, o_green, o_blue} = vga_rgb;

    reset_controller U_RESET_CONTROLLER (
        .clk               (clk),
        .rst               (rst),
        .i_pclk            (i_pclk),
        .o_clock_rst       (clock_reset),
        .o_system_rst      (system_reset),
        .o_system_pclk_rst (system_reset_pclk)
    );

    clock_gen U_CLOCK_GEN (
        .clk       (clk),
        .rst       (clock_reset),
        .o_tick_25 (tick_25),
        .o_xclk_24 (xclk_24)
    );

    vga_decoder U_VGA_DECODER (
        .clk          (clk),
        .rst          (system_reset),
        .i_pclk       (tick_25),
        .o_hsync      (o_hsync),
        .o_vsync      (o_vsync),
        .o_display_en (display_enable),
        .o_x          (screen_x),
        .o_y          (screen_y)
    );

    top_ov7670 U_TOP_OV7670 (
        .clk                  (clk),
        .i_ctrl_rst           (system_reset),
        .i_capture_rst        (system_reset_pclk),
        .i_tick_25            (tick_25),
        .i_start_btn          (i_start_btn),
        .o_scl                (o_scl),
        .io_sda               (io_sda),
        .i_camera_pclk        (i_pclk),
        .i_camera_href        (i_href),
        .i_camera_vsync       (i_vsync),
        .i_camera_data        (i_pdata),
        .o_camera_vsync       (camera_vsync),
        .o_frame_write_enable (frame_write_enable),
        .o_frame_write_addr   (frame_write_addr),
        .o_frame_write_data   (frame_write_data)
    );

    camera_line_bridge U_CAMERA_LINE_BRIDGE (
        .i_write_rst      (system_reset_pclk),
        .i_read_rst       (system_reset),
        .i_write_clk      (i_pclk),
        .i_write_enable   (frame_write_enable),
        .i_write_addr     (frame_write_addr),
        .i_write_data     (frame_write_data),
        .i_read_clk       (clk),
        .i_pixel_tick     (tick_25),
        .i_display_enable (display_enable),
        .i_screen_x       (screen_x),
        .i_screen_y       (screen_y),
        .o_camera_rgb     (camera_rgb),
        .o_pixel_good     (pixel_good),
        .o_line_valid     (line_valid),
        .o_source_x       (source_x),
        .o_source_y       (source_y),
        .o_frame_id       (source_frame_id)
    );

    canvas_pipeline U_CANVAS_PIPELINE (
        .i_capture_rst     (system_reset_pclk),
        .i_camera_vsync    (camera_vsync),
        .i_capture_clk     (i_pclk),
        .i_capture_enable  (frame_write_enable),
        .i_capture_addr    (frame_write_addr),
        .i_capture_rgb565  (frame_write_data),
        .i_read_clk        (clk),
        .i_source_x        (source_x),
        .i_source_y        (source_y),
        .i_pen_color       (pen_color),
        .i_eraser          (pen_eraser),
        .i_size            (pen_size),
        .i_texture_enable  (pen_texture_enable),
        .i_texture_shape   (pen_texture_shape),
        .i_canvas_clear    (canvas_clear),
        .o_canvas_rgb      (canvas_rgb),
        .o_canvas_valid    (canvas_valid),
        .o_x_center        (x_center),
        .o_y_center        (y_center)
    );

    vga_output_pipeline U_VGA_OUTPUT_PIPELINE (
        .i_screen_x     (screen_x),
        .i_screen_y     (screen_y),
        .i_pixel_good   (pixel_good),
        .i_line_valid   (line_valid),
        .i_frame_id     (source_frame_id),
        .i_source_y     (source_y),
        .i_camera_rgb   (camera_rgb),
        .i_canvas_rgb   (canvas_rgb),
        .i_canvas_valid (canvas_valid),
        .i_paper        (pen_paper),
        .i_freeze       (pen_freeze),
        .o_pixel_rgb    (vga_rgb)
    );

    top_uart U_TOP_UART (
        .clk                  (clk),
        .rst                  (system_reset),
        .i_rx                 (i_rx),
        .o_tx                 (o_tx),
        .i_send_trigger       (camera_vsync),
        .i_x_center           (x_center),
        .i_y_center           (y_center),
        .i_pen_color          (pen_color),
        .i_pen_eraser         (pen_eraser),
        .i_pen_size           (pen_size),
        .i_pen_texture_enable (pen_texture_enable),
        .i_pen_texture_shape  (pen_texture_shape),
        .i_pen_paper          (pen_paper),
        .i_pen_freeze         (pen_freeze),
        .i_clear              (canvas_clear),
        .o_rx_pen_color       (rx_pen_color),
        .o_rx_eraser          (rx_eraser),
        .o_rx_size            (rx_size),
        .o_rx_texture_enable  (rx_texture_enable),
        .o_rx_texture_shape   (rx_texture_shape),
        .o_rx_paper           (rx_paper),
        .o_rx_freeze          (rx_freeze),
        .o_rx_clear_pulse     (rx_clear_pulse),
        .o_rx_packet_valid    (rx_packet_valid)
    );

    top_button U_TOP_BUTTON (
        .clk              (clk),
        .rst              (system_reset),
        .i_pen_mode       (i_btn_pen_mode),
        .i_pen_size       (i_btn_pen_size),
        .i_eraser         (i_btn_eraser),
        .o_pen_mode_pulse (btn_mode_pulse),
        .o_pen_size_pulse (btn_size_pulse),
        .o_eraser_pulse   (btn_eraser_pulse)
    );

    pen_config_controller U_PEN_CONFIG_CONTROLLER (
        .clk                   (clk),
        .rst                   (system_reset),
        .i_uart_valid          (rx_packet_valid),
        .i_uart_pen_color      (rx_pen_color),
        .i_uart_eraser         (rx_eraser),
        .i_uart_size           (rx_size),
        .i_uart_texture_enable (rx_texture_enable),
        .i_uart_texture_shape  (rx_texture_shape),
        .i_uart_paper          (rx_paper),
        .i_uart_freeze         (rx_freeze),
        .i_uart_clear_pulse    (rx_clear_pulse),
        .i_btn_eraser          (btn_eraser_pulse),
        .i_btn_mode            (btn_mode_pulse),
        .i_btn_size            (btn_size_pulse),
        .o_pen_color           (pen_color),
        .o_eraser              (pen_eraser),
        .o_size                (pen_size),
        .o_texture_enable      (pen_texture_enable),
        .o_texture_shape       (pen_texture_shape),
        .o_paper               (pen_paper),
        .o_freeze              (pen_freeze),
        .o_clear               (uart_clear)
    );
endmodule
