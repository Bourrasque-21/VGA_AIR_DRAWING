module vga_output_pipeline (
    input  logic [9:0]  i_screen_x,
    input  logic [9:0]  i_screen_y,
    input  logic        i_pixel_good,
    input  logic        i_line_valid,
    input  logic [7:0]  i_frame_id,
    input  logic [8:0]  i_source_y,
    input  logic [11:0] i_camera_rgb,
    input  logic [11:0] i_canvas_rgb,
    input  logic        i_canvas_valid,
    input  logic        i_paper,
    input  logic        i_freeze,
    output logic [11:0] o_pixel_rgb
);
    logic        header_enable;
    logic [11:0] header_rgb;

    vga_transport_header_encoder U_VGA_TRANSPORT_HEADER_ENCODER (
        .i_screen_x      (i_screen_x),
        .i_screen_y      (i_screen_y),
        .i_line_valid    (i_line_valid),
        .i_frame_id      (i_frame_id),
        .i_source_y      (i_source_y),
        .o_header_enable (header_enable),
        .o_header_rgb    (header_rgb)
    );

    video_pixel_compositor U_VIDEO_PIXEL_COMPOSITOR (
        .i_pixel_good    (i_pixel_good),
        .i_canvas_valid  (i_canvas_valid),
        .i_canvas_rgb    (i_canvas_rgb),
        .i_paper         (i_paper),
        .i_freeze        (i_freeze),
        .i_camera_rgb    (i_camera_rgb),
        .i_header_enable (header_enable),
        .i_header_rgb    (header_rgb),
        .o_pixel_rgb     (o_pixel_rgb)
    );
endmodule
