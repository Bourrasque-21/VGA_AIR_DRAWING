module pen_tracker (
    input  logic        i_pixel_clk,
    input  logic        i_vsync,
    input  logic        i_sample_valid,
    input  logic [15:0] i_pixel_rgb565,
    output logic [8:0]  o_x_center,
    output logic [8:0]  o_y_center,
    output logic        o_pen_present,
    output logic        o_frame_done
);
    logic       green_detected;
    logic [8:0] raw_x;
    logic [8:0] raw_y;
    logic       raw_pen_present;
    logic       raw_valid;

    colour_detector U_COLOUR_DETECTOR (
        .i_wdata          (i_pixel_rgb565),
        .o_green_detected (green_detected)
    );

    centroid_accum #(
        .PEN_MIN (15),
        .PEN_MAX (1200),
        .ERODE   (1'b1)
    ) U_CENTROID_ACCUM (
        .i_pclk  (i_pixel_clk),
        .i_vsync (i_vsync),
        .i_we    (i_sample_valid),
        .i_hit   (green_detected),
        .o_cx    (raw_x),
        .o_cy    (raw_y),
        .o_pen   (raw_pen_present),
        .o_valid (raw_valid)
    );

    coord_filter U_COORD_FILTER (
        .i_pclk  (i_pixel_clk),
        .i_valid (raw_valid),
        .i_cx    (raw_x),
        .i_cy    (raw_y),
        .i_pen   (raw_pen_present),
        .o_x     (o_x_center),
        .o_y     (o_y_center),
        .o_pen   (o_pen_present),
        .o_valid (o_frame_done)
    );
endmodule
