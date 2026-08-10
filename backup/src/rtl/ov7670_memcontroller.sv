`timescale 1ns / 1ps

module ov7670_memcontroller (
    input  logic                       pclk,
    input  logic                       reset,
    // ov767 side
    input  logic                       href,
    input  logic                       vsync,
    input  logic [                7:0] pdata,
    // frame-buffer side
    output logic                       we,
    output logic [$clog2(320*240)-1:0] waddr,
    output logic [               15:0] wdata
);

    logic [15:0] pixeldata;
    logic        pixelevenodd;

    assign wdata = pixeldata;

    always_ff @(posedge pclk, posedge reset) begin
        if (reset) begin
            we           <= 1'b0;
            pixeldata    <= 0;
            waddr        <= 0;
            pixelevenodd <= 1'b0;
        end else begin
            if (we) begin
                waddr <= waddr + 1;
            end

            if (href) begin
                if (pixelevenodd == 1'b0) begin
                    we              <= 1'b0;
                    pixeldata[15:8] <= pdata;
                    pixelevenodd    <= ~pixelevenodd;
                end else begin
                    we             <= 1'b1;
                    pixeldata[7:0] <= pdata;
                    pixelevenodd   <= ~pixelevenodd;
                end
            end else begin
                we           <= 1'b0;
                pixeldata    <= 0;
                pixelevenodd <= 1'b0;
            end
            if (vsync) begin
                we           <= 1'b0;
                pixeldata    <= 0;
                waddr        <= 0;
                pixelevenodd <= 1'b0;
            end
        end
    end
endmodule

/*
module ov7670_memcontroller (
    input  logic                       pclk,
    input  logic                       reset,
    // ov7670 side
    input  logic                       href,
    input  logic                       vsync,
    input  logic [                7:0] pdata,
    // framebuffer side
    output logic                       we,
    output logic [$clog2(320*240)-1:0] waddr,
    output logic [               15:0] wdata

);

    logic [15:0] pixelData;
    logic pixelEvenOdd;
    logic [$clog2(320*240)-1:0] nextWAddr;

    always_ff @(posedge pclk, posedge reset) begin
        if (reset) begin
            waddr        <= 0;
            nextWAddr    <= 0;
            wdata        <= 0;
            pixelData    <= 0;
            pixelEvenOdd <= 1'b0;
            we           <= 1'b0;
        end else begin
            if (href) begin
                if (pixelEvenOdd == 1'b0) begin
                    pixelData[15:8] <= pdata;
                    pixelEvenOdd    <= ~pixelEvenOdd;
                    we              <= 1'b0;
                end else begin
                    wdata          <= {pixelData[15:8], pdata};
                    waddr          <= nextWAddr;
                    nextWAddr      <= nextWAddr + 1'b1;
                    pixelData[7:0] <= pdata;
                    pixelEvenOdd   <= ~pixelEvenOdd;
                    we             <= 1'b1;
                end
            end else begin
                we           <= 1'b0;
                pixelData    <= 0;
                pixelEvenOdd <= 1'b0;
            end
            if (vsync) begin
                waddr        <= 0;
                nextWAddr    <= 0;
                wdata        <= 0;
                pixelData    <= 0;
                pixelEvenOdd <= 1'b0;
                we           <= 1'b0;
            end
        end
    end

endmodule
*/