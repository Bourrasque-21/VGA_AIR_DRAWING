module top_framebuffer (
    input logic i_write_clk, input logic i_write_enable,
    input logic [$clog2(320 * 240)-1:0] i_write_addr, input logic [15:0] i_write_data,
    input logic i_read_clk, input logic i_display_enable,
    input logic [9:0] i_x_pixel, input logic [9:0] i_y_pixel,
    input logic [15:0] i_display_pixel,
    output logic [15:0] o_frame_pixel,
    output logic [$clog2(320 * 240)-1:0] o_selected_read_addr,
    output logic [11:0] o_qvga_pixel_rgb
);
    framebuffer U_FRAMEBUFFER (
        .wclk(i_write_clk), .we(i_write_enable), .waddr(i_write_addr), .wdata(i_write_data),
        .rclk(i_read_clk), .raddr(o_selected_read_addr), .rdata(o_frame_pixel)
    );

    framebuffer_reader U_FRAMEBUFFER_READER (
        .de(i_display_enable), .x_pixel(i_x_pixel), .y_pixel(i_y_pixel),
        .addr(o_selected_read_addr), .imgPxlData(i_display_pixel),
        .port_red(o_qvga_pixel_rgb[11:8]), .port_green(o_qvga_pixel_rgb[7:4]),
        .port_blue(o_qvga_pixel_rgb[3:0])
    );
endmodule
