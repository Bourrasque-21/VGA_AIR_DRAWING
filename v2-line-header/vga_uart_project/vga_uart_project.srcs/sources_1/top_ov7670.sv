module top_ov7670 (
    input  logic                         clk,
    input  logic                         i_ctrl_rst,
    input  logic                         i_capture_rst,
    input  logic                         i_tick_25,
    input  logic                         i_start_btn,
    output logic                         o_scl,
    inout  logic                         io_sda,
    input  logic                         i_camera_pclk,
    input  logic                         i_camera_href,
    input  logic                         i_camera_vsync,
    input  logic [7:0]                   i_camera_data,
    output logic                         o_camera_vsync,
    output logic                         o_frame_write_enable,
    output logic [$clog2(640 * 480)-1:0] o_frame_write_addr,
    output logic [15:0]                  o_frame_write_data
);
    logic camera_href;
    logic camera_vsync;
    logic [7:0] camera_data;
    logic init_done;
    logic capture_accept;
    logic frame_write_enable_raw;

    assign o_camera_vsync = camera_vsync;

    ov7670_capture_frontend U_CAPTURE_FRONTEND (
        .clk              (i_camera_pclk),
        .rst              (i_capture_rst),
        .i_href           (i_camera_href),
        .i_vsync          (i_camera_vsync),
        .i_data           (i_camera_data),
        .i_init_done      (init_done),
        .o_href           (camera_href),
        .o_vsync          (camera_vsync),
        .o_data           (camera_data),
        .o_capture_accept (capture_accept)
    );

    ov7670_sccb_ctrl U_SCCB_CTRL (
        .clk            (clk),
        .rst            (i_ctrl_rst),
        .i_tick_25      (i_tick_25),
        .i_start_btn    (i_start_btn),
        .i_camera_vsync (camera_vsync),
        .o_init_done    (init_done),
        .o_scl          (o_scl),
        .io_sda         (io_sda)
    );
    ov7670_memcontroller U_MEMCONTROLLER (
        .i_pclk  (i_camera_pclk),
        .rst     (i_capture_rst),
        .i_href  (camera_href),
        .i_vsync (camera_vsync),
        .i_pdata (camera_data),
        .o_we    (frame_write_enable_raw),
        .o_waddr (o_frame_write_addr),
        .o_wdata (o_frame_write_data)
    );
    assign o_frame_write_enable = frame_write_enable_raw && capture_accept;
endmodule
