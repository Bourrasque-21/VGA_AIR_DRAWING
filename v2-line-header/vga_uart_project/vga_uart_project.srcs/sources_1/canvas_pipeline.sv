module canvas_pipeline (
    input  logic        i_capture_rst,
    input  logic        i_camera_vsync,
    input  logic        i_capture_clk,
    input  logic        i_capture_enable,
    input  logic [18:0] i_capture_addr,
    input  logic [15:0] i_capture_rgb565,
    input  logic        i_read_clk,
    input  logic [9:0]  i_source_x,
    input  logic [8:0]  i_source_y,
    input  logic [2:0]  i_pen_color,
    input  logic        i_eraser,
    input  logic        i_size,
    input  logic        i_texture_enable,
    input  logic [2:0]  i_texture_shape,
    input  logic        i_canvas_clear,
    output logic [11:0] o_canvas_rgb,
    output logic        o_canvas_valid,
    output logic [8:0]  o_x_center,
    output logic [8:0]  o_y_center
);
    logic        sample_valid;
    logic        pen_present;
    logic        frame_done;
    logic        canvas_write_enable;
    logic [16:0] canvas_write_addr;
    logic [3:0]  canvas_write_data;
    logic [16:0] canvas_read_addr;
    logic [3:0]  canvas_read_data;

    assign canvas_read_addr =
        ({9'd0, i_source_y[8:1]} << 8) +
        ({9'd0, i_source_y[8:1]} << 6) +
        {8'd0, i_source_x[9:1]};

    camera_to_canvas_sampler U_CAMERA_TO_CANVAS_SAMPLER (
        .clk            (i_capture_clk),
        .rst            (i_capture_rst),
        .i_vsync        (i_camera_vsync),
        .i_write_enable (i_capture_enable),
        .i_write_addr   (i_capture_addr),
        .o_sample_valid (sample_valid)
    );

    pen_tracker U_PEN_TRACKER (
        .i_pixel_clk     (i_capture_clk),
        .i_vsync         (i_camera_vsync),
        .i_sample_valid  (sample_valid),
        .i_pixel_rgb565  (i_capture_rgb565),
        .o_x_center      (o_x_center),
        .o_y_center      (o_y_center),
        .o_pen_present   (pen_present),
        .o_frame_done    (frame_done)
    );

    brush_draw_engine U_BRUSH_DRAW_ENGINE (
        .clk              (i_capture_clk),
        .rst              (i_capture_rst),
        .i_frame_done     (frame_done),
        .i_pen_present    (pen_present),
        .i_x_center       (o_x_center),
        .i_y_center       (o_y_center),
        .i_pen_color      (i_pen_color),
        .i_eraser         (i_eraser),
        .i_size           (i_size),
        .i_texture_enable (i_texture_enable),
        .i_texture_shape  (i_texture_shape),
        .o_ram_we         (canvas_write_enable),
        .o_ram_waddr      (canvas_write_addr),
        .o_ram_wdata      (canvas_write_data),
        .o_busy           ()
    );

    canvas_buffer U_CANVAS_BUFFER (
        .i_write_clk    (i_capture_clk),
        .i_clear        (i_canvas_clear),
        .i_write_enable (canvas_write_enable),
        .i_write_addr   (canvas_write_addr),
        .i_write_data   (canvas_write_data),
        .i_read_clk     (i_read_clk),
        .i_read_addr    (canvas_read_addr),
        .o_read_data    (canvas_read_data)
    );

    canvas_pixel_decoder U_CANVAS_PIXEL_DECODER (
        .i_canvas_pixel (canvas_read_data),
        .o_canvas_valid (o_canvas_valid),
        .o_canvas_rgb   (o_canvas_rgb)
    );
endmodule
