module top_canvas (
    input logic i_rst, input logic i_vsync, input logic [2:0] i_pen_color,
    input logic i_eraser, input logic i_size, input logic i_texture_enable,
    input logic [2:0] i_texture_shape,
    input logic i_canvas_clear, input logic i_write_clk, input logic i_write_enable,
    input logic [$clog2(320 * 240)-1:0] i_write_addr, input logic [15:0] i_write_data,
    input logic i_read_clk, input logic [$clog2(320 * 240)-1:0] i_read_addr,
    output logic [15:0] o_canvas_pixel, output logic o_canvas_valid,
    output logic [8:0] o_x_center, output logic [8:0] o_y_center
);
    canvas_buffer_top U_CANVAS_BUFFER (
        .rst(i_rst), .vsync(i_vsync), .sw_pen_color(i_pen_color),
        .sw_eraser(i_eraser), .sw_size(i_size), .sw_texture_enable(i_texture_enable),
        .sw_texture_shape(i_texture_shape),
        .wclk(i_write_clk), .we(i_write_enable), .waddr(i_write_addr), .wdata(i_write_data),
        .rclk(i_read_clk), .raddr(i_read_addr), .rdata(o_canvas_pixel),
        .paint_sel(o_canvas_valid), .X_center(o_x_center), .Y_center(o_y_center),
        .canvas_clear(i_canvas_clear)
    );
endmodule
