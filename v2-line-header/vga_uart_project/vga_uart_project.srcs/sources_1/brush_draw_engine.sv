module brush_draw_engine (
    input  logic                       clk,
    input  logic                       rst,
    input  logic                       i_frame_done,
    input  logic                       i_pen_present,
    input  logic [ 8:0]                i_x_center,
    input  logic [ 8:0]                i_y_center,
    input  logic [ 2:0]                i_pen_color,
    input  logic                       i_eraser,
    input  logic                       i_size,
    input  logic                       i_texture_enable,
    input  logic [ 2:0]                i_texture_shape,
    output logic                       o_ram_we,
    output logic [$clog2(320*240)-1:0] o_ram_waddr,
    output logic [ 3:0]                o_ram_wdata,
    output logic                       o_busy
);
    logic        line_start;
    logic        line_ready;
    logic        line_done;
    logic [8:0]  line_x0;
    logic [8:0]  line_y0;
    logic [8:0]  line_x1;
    logic [8:0]  line_y1;
    logic [3:0]  line_color;
    logic [4:0]  line_radius;
    logic [10:0] line_threshold;
    logic        stroke_busy;

    logic       point_valid;
    logic       point_ready;
    logic [8:0] point_x;
    logic [8:0] point_y;
    logic       path_busy;

    logic stamp_done;
    logic renderer_busy;

    assign o_busy = stroke_busy | path_busy | renderer_busy;

    brush_stroke_controller U_STROKE_CONTROLLER (
        .clk              (clk),
        .rst              (rst),
        .i_frame_done     (i_frame_done),
        .i_pen_present    (i_pen_present),
        .i_x_center       (i_x_center),
        .i_y_center       (i_y_center),
        .i_pen_color      (i_pen_color),
        .i_eraser         (i_eraser),
        .i_size           (i_size),
        .i_line_ready     (line_ready),
        .i_line_done      (line_done),
        .o_line_start     (line_start),
        .o_line_x0        (line_x0),
        .o_line_y0        (line_y0),
        .o_line_x1        (line_x1),
        .o_line_y1        (line_y1),
        .o_line_color     (line_color),
        .o_line_radius    (line_radius),
        .o_line_threshold (line_threshold),
        .o_busy           (stroke_busy)
    );

    bresenham_interpolator U_BRESENHAM_INTERPOLATOR (
        .clk           (clk),
        .rst           (rst),
        .i_line_start  (line_start),
        .i_line_x0     (line_x0),
        .i_line_y0     (line_y0),
        .i_line_x1     (line_x1),
        .i_line_y1     (line_y1),
        .o_line_ready  (line_ready),
        .o_line_done   (line_done),
        .o_point_valid (point_valid),
        .i_point_ready (point_ready),
        .o_point_x     (point_x),
        .o_point_y     (point_y),
        .i_stamp_done  (stamp_done),
        .o_busy        (path_busy)
    );

    circular_brush_renderer U_CIRCULAR_BRUSH_RENDERER (
        .clk              (clk),
        .rst              (rst),
        .i_point_valid    (point_valid),
        .o_point_ready    (point_ready),
        .i_point_x        (point_x),
        .i_point_y        (point_y),
        .i_color          (line_color),
        .i_radius         (line_radius),
        .i_sq_threshold   (line_threshold),
        .i_texture_enable (i_texture_enable),
        .i_texture_shape  (i_texture_shape),
        .o_stamp_done     (stamp_done),
        .o_ram_we         (o_ram_we),
        .o_ram_waddr      (o_ram_waddr),
        .o_ram_wdata      (o_ram_wdata),
        .o_busy           (renderer_busy)
    );
endmodule
