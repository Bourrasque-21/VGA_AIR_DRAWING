module top_ov7670 (
    input  logic        i_clk,
    input  logic        i_rst,
    input  logic        i_tick_25,
    input  logic        i_start_btn,
    output logic        o_scl,
    inout  logic        io_sda,
    input  logic        i_camera_pclk,
    input  logic        i_camera_href,
    input  logic        i_camera_vsync,
    input  logic [7:0]  i_camera_data,
    output logic        o_frame_write_enable,
    output logic [$clog2(320 * 240)-1:0] o_frame_write_addr,
    output logic [15:0] o_frame_write_data
);
    ov7670_sccb_ctrl U_SCCB_CTRL (
        .clk      (i_clk), .rst(i_rst), .i_tick_25(i_tick_25),
        .start_btn(i_start_btn), .scl(o_scl), .sda(io_sda)
    );
    ov7670_memcontroller U_MEMCONTROLLER (
        .pclk(i_camera_pclk), .reset(i_rst), .href(i_camera_href),
        .vsync(i_camera_vsync), .pdata(i_camera_data),
        .we(o_frame_write_enable), .waddr(o_frame_write_addr),
        .wdata(o_frame_write_data)
    );
endmodule
