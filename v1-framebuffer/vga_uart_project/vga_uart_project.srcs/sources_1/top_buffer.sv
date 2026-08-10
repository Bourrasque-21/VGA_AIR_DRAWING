module top_buffer (
    input logic i_rst, input logic i_vsync,
    input logic [2:0] i_pen_color, input logic i_eraser, input logic i_size,
    input logic i_texture_enable, input logic [2:0] i_texture_shape,
    input logic i_paper,  // 도화지 모드: 배경을 카메라 대신 흰색으로
    input logic i_freeze, // 캡처 모드: 배경 프레임버퍼 쓰기 정지 (마지막 프레임 고정)
    input logic i_canvas_clear,
    input logic i_write_clk, input logic i_write_enable,
    input logic [$clog2(320 * 240)-1:0] i_write_addr, input logic [15:0] i_write_data,
    input logic i_read_clk, input logic i_display_enable,
    input logic [9:0] i_x_pixel, input logic [9:0] i_y_pixel,
    output logic [11:0] o_qvga_pixel_rgb,
    output logic [8:0] o_x_center, output logic [8:0] o_y_center
);
    logic [15:0] frame_pixel, canvas_pixel, display_pixel;
    logic canvas_valid;
    logic [$clog2(320 * 240)-1:0] selected_read_addr;

    // 캡처(freeze): 배경 프레임버퍼 쓰기만 멈춰 마지막 카메라 프레임을 고정한다.
    // 검출/캔버스 쓰기 경로(top_canvas)는 그대로라 멈춘 화면 위에 계속 그려진다.
    // i_freeze는 clk 도메인의 준정적 신호라 쓰기 클럭으로 2FF 동기화만 한다.
    logic freeze_meta, freeze_sync;
    always_ff @(posedge i_write_clk) begin
        freeze_meta <= i_freeze;
        freeze_sync <= freeze_meta;
    end

    top_framebuffer U_TOP_FRAMEBUFFER (
        .i_write_clk(i_write_clk), .i_write_enable(i_write_enable & ~freeze_sync),
        .i_write_addr(i_write_addr), .i_write_data(i_write_data),
        .i_read_clk(i_read_clk), .i_display_enable(i_display_enable),
        .i_x_pixel(i_x_pixel), .i_y_pixel(i_y_pixel),
        .i_display_pixel(display_pixel),
        .o_frame_pixel(frame_pixel), .o_selected_read_addr(selected_read_addr),
        .o_qvga_pixel_rgb(o_qvga_pixel_rgb)
    );

    top_canvas U_TOP_CANVAS (
        .i_rst(i_rst), .i_vsync(i_vsync), .i_pen_color(i_pen_color),
        .i_eraser(i_eraser), .i_size(i_size), .i_texture_enable(i_texture_enable),
        .i_texture_shape(i_texture_shape),
        .i_canvas_clear(i_canvas_clear), .i_write_clk(i_write_clk),
        .i_write_enable(i_write_enable), .i_write_addr(i_write_addr),
        .i_write_data(i_write_data), .i_read_clk(i_read_clk),
        .i_read_addr(selected_read_addr), .o_canvas_pixel(canvas_pixel),
        .o_canvas_valid(canvas_valid), .o_x_center(o_x_center),
        .o_y_center(o_y_center)
    );

    // 도화지 모드에서는 카메라 배경 대신 흰색을 깐다.
    // 검출 경로(colour_detector, top_canvas의 write side)는 그대로라
    // 화면에 안 보여도 초록 마커 추적은 계속 동작한다.
    logic [15:0] background_pixel;
    assign background_pixel = i_paper ? 16'hFFFF : frame_pixel;

    overlay_pixel_mux U_FRAME_CANVAS_OVERLAY (
        .i_canvas_valid(canvas_valid), .i_frame_pixel(background_pixel),
        .i_canvas_pixel(canvas_pixel), .o_display_pixel(display_pixel)
    );
endmodule
