`timescale 1ns / 1ps

module framebuffer_reader (
    input  logic                       de,
    input  logic [                9:0] x_pixel,
    input  logic [                9:0] y_pixel,
    output logic [$clog2(320*240)-1:0] addr,
    input  logic [               15:0] imgPxlData,
    output logic [                3:0] port_red,
    output logic [                3:0] port_green,
    output logic [                3:0] port_blue
);
    logic qvga_area;

    assign qvga_area = (x_pixel < 320) && (y_pixel < 240);

    assign addr = qvga_area ? (320 * y_pixel + x_pixel) : 0;
    assign {port_red, port_green, port_blue} = qvga_area ? {imgPxlData[15:12], imgPxlData[10:7], imgPxlData[4:1]} : 0;
endmodule
