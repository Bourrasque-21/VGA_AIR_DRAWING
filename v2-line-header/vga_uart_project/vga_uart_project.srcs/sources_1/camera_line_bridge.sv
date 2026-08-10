module camera_line_bridge (
    input  logic        i_write_rst,
    input  logic        i_read_rst,
    input  logic        i_write_clk,
    input  logic        i_write_enable,
    input  logic [18:0] i_write_addr,
    input  logic [15:0] i_write_data,
    input  logic        i_read_clk,
    input  logic        i_pixel_tick,
    input  logic        i_display_enable,
    input  logic [9:0]  i_screen_x,
    input  logic [9:0]  i_screen_y,
    output logic [11:0] o_camera_rgb,
    output logic        o_pixel_good,
    output logic        o_line_valid,
    output logic [9:0]  o_source_x,
    output logic [8:0]  o_source_y,
    output logic [7:0]  o_frame_id
);
    logic       ring_empty;
    logic       ring_pop;
    logic [6:0] ring_count;
    logic [5:0] next_bank;
    logic [7:0] next_frame_id;
    logic [8:0] next_source_y;
    logic [5:0] read_bank;
    logic [9:0] read_x;

    camera_line_ring U_CAMERA_LINE_RING (
        .i_write_rst  (i_write_rst),
        .i_wclk       (i_write_clk),
        .i_we         (i_write_enable),
        .i_waddr      (i_write_addr),
        .i_wdata      (i_write_data),
        .i_rclk       (i_read_clk),
        .i_read_rst   (i_read_rst),
        .i_pop        (ring_pop),
        .o_empty      (ring_empty),
        .o_count      (ring_count),
        .o_bank       (next_bank),
        .o_frame_id   (next_frame_id),
        .o_y          (next_source_y),
        .i_read_bank  (read_bank),
        .i_read_x     (read_x),
        .o_read_pixel (o_camera_rgb)
    );

    vga_line_streamer U_VGA_LINE_STREAMER (
        .clk           (i_read_clk),
        .rst           (i_read_rst),
        .i_tick        (i_pixel_tick),
        .i_de          (i_display_enable),
        .i_x           (i_screen_x),
        .i_y           (i_screen_y),
        .i_empty       (ring_empty),
        .i_count       (ring_count),
        .i_next_bank   (next_bank),
        .i_next_frame  (next_frame_id),
        .i_next_y      (next_source_y),
        .o_pop         (ring_pop),
        .o_bank        (read_bank),
        .o_source_x    (read_x),
        .o_pixel_good  (o_pixel_good),
        .o_line_valid  (o_line_valid),
        .o_line_frame  (o_frame_id),
        .o_line_y      (o_source_y)
    );

    assign o_source_x = read_x;
endmodule
