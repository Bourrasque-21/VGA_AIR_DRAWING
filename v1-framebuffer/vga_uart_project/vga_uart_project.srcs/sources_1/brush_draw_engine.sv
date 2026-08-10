`timescale 1ns / 1ps

// Coordinates the stroke, path interpolation, and brush rendering modules.
module brush_draw_engine (
    input  logic                       clk,
    input  logic                       rst,
    input  logic                       frame_done,
    input  logic                       pen_present,
    input  logic [                8:0] X_center,
    input  logic [                8:0] Y_center,
    input  logic [                2:0] sw_pen_color,
    input  logic                       sw_eraser,
    input  logic                       sw_size,
    input  logic                       pen_texture_enable,
    input  logic [                2:0] pen_texture_shape,

    output logic                       ram_we,
    output logic [$clog2(320*240)-1:0] ram_waddr,
    output logic [                3:0] ram_wdata,
    output logic                       engine_busy
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

    assign engine_busy = stroke_busy | path_busy | renderer_busy;

    brush_stroke_controller U_STROKE_CONTROLLER (
        .clk              (clk),
        .rst              (rst),
        .frame_done       (frame_done),
        .pen_present      (pen_present),
        .X_center         (X_center),
        .Y_center         (Y_center),
        .sw_pen_color     (sw_pen_color),
        .sw_eraser        (sw_eraser),
        .sw_size          (sw_size),
        .line_ready       (line_ready),
        .line_done        (line_done),
        .line_start       (line_start),
        .line_x0          (line_x0),
        .line_y0          (line_y0),
        .line_x1          (line_x1),
        .line_y1          (line_y1),
        .line_color       (line_color),
        .line_radius      (line_radius),
        .line_threshold   (line_threshold),
        .busy             (stroke_busy)
    );

    bresenham_interpolator U_BRESENHAM_INTERPOLATOR (
        .clk          (clk),
        .rst          (rst),
        .line_start   (line_start),
        .line_x0      (line_x0),
        .line_y0      (line_y0),
        .line_x1      (line_x1),
        .line_y1      (line_y1),
        .line_ready   (line_ready),
        .line_done    (line_done),
        .point_valid  (point_valid),
        .point_ready  (point_ready),
        .point_x      (point_x),
        .point_y      (point_y),
        .stamp_done   (stamp_done),
        .busy         (path_busy)
    );

    circular_brush_renderer U_CIRCULAR_BRUSH_RENDERER (
        .clk          (clk),
        .rst          (rst),
        .point_valid  (point_valid),
        .point_ready  (point_ready),
        .point_x      (point_x),
        .point_y      (point_y),
        .color        (line_color),
        .radius       (line_radius),
        .sq_threshold (line_threshold),
        .texture_enable(pen_texture_enable),
        .texture_shape (pen_texture_shape),
        .stamp_done   (stamp_done),
        .ram_we       (ram_we),
        .ram_waddr    (ram_waddr),
        .ram_wdata    (ram_wdata),
        .busy         (renderer_busy)
    );
endmodule

