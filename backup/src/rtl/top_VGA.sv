`timescale 1ns / 1ps

module top_VGA (
    input logic clk,
    input logic reset,

    // OV7670
    input  logic       pclk,
    input  logic       href,
    input  logic       vsync,
    input  logic [7:0] pdata,
    output logic       xclk,

    // VGA side
    output logic       h_sync,
    output logic       v_sync,
    output logic [3:0] port_red,
    output logic [3:0] port_green,
    output logic [3:0] port_blue,

    // SCCB
    input  logic start_btn,
    input  logic clear_btn,
    output logic scl,
    inout  logic sda,

    input logic sw_red,
    input logic sw_green,
    input logic sw_blue,
    input logic sw_gray,
    input logic sw_upscale,

    input logic sw_paint_red,
    input logic sw_paint_green,
    input logic sw_paint_blue,
    input logic sw_eraser,
    input logic sw_size
);

    logic [                9:0] x_pixel;
    logic [                9:0] y_pixel;
    logic                       de;

    logic [$clog2(320*240)-1:0] addr;
    logic [               15:0] imgPxlData;

    logic [$clog2(320*240)-1:0] upscale_addr;
    logic [               15:0] upscale_imgPxlData;
    logic [               11:0] upscale_port_rgb;

    logic [$clog2(320*240)-1:0] qvga_addr;
    logic [               15:0] qvga_imgPxlData;
    logic [               11:0] qvga_port_rgb;

    logic [               11:0] rgb_org;
    logic [               11:0] rgb_filter_o;
    logic [               11:0] rgb_gray;

    logic                       we;
    logic [$clog2(320*240)-1:0] waddr;
    logic [               15:0] wdata;

    logic clk_100, clk_25, rclk;
    logic [15:0] canvas_data_o, live_data_o;
    logic paint_sel;

    assign xclk = clk_25;

    assign rgb_org = sw_upscale ? upscale_port_rgb : qvga_port_rgb;

    mux_2x1 #(
        .PORT_WIDTH(16)
    ) U_MUX_CANVAS_DATA (
        .sel(paint_sel),
        .x0 (live_data_o),
        .x1 (canvas_data_o),
        .y  (imgPxlData)
    );


    canvas_buffer_top U_CANVAS_BUFFER_TOP (
        .rst         (reset),
        .vsync       (vsync),
        .sw_pen_color({sw_paint_red, sw_paint_green, sw_paint_blue}),
        .sw_eraser   (sw_eraser),
        .sw_size     (sw_size),
        // wrtie side
        .wclk        (pclk),
        .we          (we),
        .waddr       (waddr),
        .wdata       (wdata),
        // read side
        .rclk        (clk_100),
        .raddr       (addr),
        .rdata       (canvas_data_o),
        .paint_sel   (paint_sel),
        .canvas_clear(clear_btn)
    );

    ov7670_sccb_ctrl U_OV7670_SCCB_CTRL (
        .clk(clk_25),
        .rst(reset),
        .start_btn(start_btn),
        .scl(scl),
        .sda(sda)
    );

    clk_wiz_0 U_CLOCK_WIZARD (
        // Clock out ports
        .clk_out1(clk_100),     // output clk_out1 100Mhz
        .clk_out2(clk_25),     // output clk_out2 25Mhz
        // Status and control signals
        .reset(reset), // input reset
        // Clock in ports
        .clk_in1(clk) // input clk_in1 50Mhz
    );

    VGA_Decoder U_VGA_Decoder (
        .clk    (clk_100),
        .rclk   (rclk),
        .reset  (reset),
        .h_sync (h_sync),
        .v_sync (v_sync),
        .x_pixel(x_pixel),
        .y_pixel(y_pixel),
        .de     (de)
    );

    framebuffer_reader U_FRAME_BUFFER_READER (
        .de        (de),
        .x_pixel   (x_pixel),
        .y_pixel   (y_pixel),
        .addr      (qvga_addr),
        .imgPxlData(qvga_imgPxlData),
        .port_red  (qvga_port_rgb[11:8]),
        .port_green(qvga_port_rgb[7:4]),
        .port_blue (qvga_port_rgb[3:0])
    );

    UpScaleImage U_UpScaleImage (
        .de        (de),
        .x_pixel   (x_pixel),
        .y_pixel   (y_pixel),
        .addr      (upscale_addr),
        .imgPxlData(upscale_imgPxlData),
        .port_red  (upscale_port_rgb[11:8]),
        .port_green(upscale_port_rgb[7:4]),
        .port_blue (upscale_port_rgb[3:0])
    );

    mux_2x1 #(
        .PORT_WIDTH($clog2(320 * 240))
    ) U_MUX_READ_ADDR (
        .sel(sw_upscale),
        .x0 (qvga_addr),
        .x1 (upscale_addr),
        .y  (addr)
    );

    demux_2x1 #(
        .PORT_WIDTH(16)
    ) U_DEMUX_READ_DATA (
        .sel(sw_upscale),
        .y  (imgPxlData),
        .x0 (qvga_imgPxlData),
        .x1 (upscale_imgPxlData)
    );

    framebuffer U_FRAME_BUFFER (
        // write side
        .wclk (pclk),
        .we   (we),
        .waddr(waddr),
        .wdata(wdata),
        // read side
        .rclk (clk_100),
        .raddr(addr),
        .rdata(live_data_o)
    );

    ov7670_memcontroller U_OV7670_Memcontroller (
        // system
        .pclk (pclk),
        .reset(reset),
        // ov767 side
        .href (href),
        .vsync(vsync),
        .pdata(pdata),
        // frame-buffer side
        .we   (we),
        .waddr(waddr),
        .wdata(wdata)
    );

    gray_filter U_GRAY_FILTER (
        .sw   (sw_gray),
        .i_rgb(rgb_org),
        .o_rgb(rgb_gray)
    );

    rgb_filter U_RGB_FILTER (
        .r_in     (rgb_org[11:8]),
        .g_in     (rgb_org[7:4]),
        .b_in     (rgb_org[3:0]),
        .sw_filter({sw_red, sw_green, sw_blue}),
        .r_out    (rgb_filter_o[11:8]),
        .g_out    (rgb_filter_o[7:4]),
        .b_out    (rgb_filter_o[3:0])
    );

    assign {port_red, port_green, port_blue} = sw_gray ? rgb_gray : rgb_filter_o;
endmodule




module mux_2x1 #(
    parameter PORT_WIDTH = 12
) (
    input  logic                  sel,
    input  logic [PORT_WIDTH-1:0] x0,
    input  logic [PORT_WIDTH-1:0] x1,
    output logic [PORT_WIDTH-1:0] y
);
    assign y = sel ? x1 : x0;
endmodule




module demux_2x1 #(
    parameter PORT_WIDTH = 12
) (
    input  logic                  sel,
    input  logic [PORT_WIDTH-1:0] y,
    output logic [PORT_WIDTH-1:0] x0,
    output logic [PORT_WIDTH-1:0] x1
);
    always_comb begin
        x0 = 0;
        x1 = 0;
        case (sel)
            1'b0: begin
                x0 = y;
            end
            1'b1: begin
                x1 = y;
            end
            default: begin
                x0 = 0;
                x1 = 0;
            end
        endcase

    end
endmodule




module rgb_filter (
    input  logic [3:0] r_in,
    input  logic [3:0] g_in,
    input  logic [3:0] b_in,
    input  logic [2:0] sw_filter,
    output logic [3:0] r_out,
    output logic [3:0] g_out,
    output logic [3:0] b_out
);

    assign r_out = (sw_filter[2]) ? r_in : 0;
    assign g_out = (sw_filter[1]) ? g_in : 0;
    assign b_out = (sw_filter[0]) ? b_in : 0;
endmodule




module gray_filter (
    input  logic        sw,
    input  logic [11:0] i_rgb,
    output logic [11:0] o_rgb
);

    logic [11:0] gray;
    logic [11:0] r;
    logic [11:0] g;
    logic [11:0] b;

    // RGB->grayscale 
    assign r = {8'd0, i_rgb[11:8]};
    assign g = {8'd0, i_rgb[7:4]};
    assign b = {8'd0, i_rgb[3:0]};
    assign gray = ((r << 6) + (r << 3) + (r << 2))
                + ((g << 7) + (g << 4) + (g << 3) + (g << 1))
                + ((b << 4) + (b << 3) + (b << 1));
    assign o_rgb = sw ? {gray[11:8], gray[11:8], gray[11:8]} : i_rgb;
endmodule
