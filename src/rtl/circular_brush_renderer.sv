`timescale 1ns / 1ps

// Rasterizes a circular stamp and generates clipped Canvas write addresses.
module circular_brush_renderer (
    input  logic                       clk,
    input  logic                       rst,
    input  logic                       point_valid,
    output logic                       point_ready,
    input  logic [                8:0] point_x,
    input  logic [                8:0] point_y,
    input  logic [                3:0] color,
    input  logic [                4:0] radius,
    input  logic [               10:0] sq_threshold,
    output logic                       stamp_done,

    output logic                       ram_we,
    output logic [$clog2(320*240)-1:0] ram_waddr,
    output logic [                3:0] ram_wdata,
    output logic                       busy
);
    logic [8:0] center_x;
    logic [8:0] center_y;
    logic [3:0] color_reg;
    logic [4:0] radius_reg;
    logic [10:0] threshold_reg;

    logic signed [5:0] offset_x;
    logic signed [5:0] offset_y;
    logic signed [5:0] radius_signed;
    logic signed [11:0] canvas_x;
    logic signed [11:0] canvas_y;

    logic [5:0] abs_offset_x;
    logic [5:0] abs_offset_y;
    logic [11:0] offset_x_sq;
    logic [11:0] offset_y_sq;
    logic [12:0] distance_sq;
    logic inside_circle;

    assign point_ready    = !busy;
    assign radius_signed  = $signed({1'b0, radius_reg});
    assign canvas_x       = $signed({1'b0, center_x}) + offset_x;
    assign canvas_y       = $signed({1'b0, center_y}) + offset_y;
    assign abs_offset_x   = (offset_x < 0) ? $unsigned(-offset_x) : $unsigned(offset_x);
    assign abs_offset_y   = (offset_y < 0) ? $unsigned(-offset_y) : $unsigned(offset_y);
    assign offset_x_sq    = {6'b0, abs_offset_x} * {6'b0, abs_offset_x};
    assign offset_y_sq    = {6'b0, abs_offset_y} * {6'b0, abs_offset_y};
    assign distance_sq    = {1'b0, offset_x_sq} + {1'b0, offset_y_sq};
    assign inside_circle  = (distance_sq <= {2'b0, threshold_reg});

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            center_x      <= 9'd0;
            center_y      <= 9'd0;
            color_reg     <= 4'b0000;
            radius_reg    <= 5'd2;
            threshold_reg <= 11'd6;
            offset_x      <= -6'sd2;
            offset_y      <= -6'sd2;
            stamp_done    <= 1'b0;
            ram_we        <= 1'b0;
            ram_waddr     <= '0;
            ram_wdata     <= 4'b0000;
            busy          <= 1'b0;
        end else begin
            ram_we     <= 1'b0;
            stamp_done <= 1'b0;

            if (!busy) begin
                if (point_valid) begin
                    center_x      <= point_x;
                    center_y      <= point_y;
                    color_reg     <= color;
                    radius_reg    <= radius;
                    threshold_reg <= sq_threshold;
                    offset_x      <= -$signed({1'b0, radius});
                    offset_y      <= -$signed({1'b0, radius});
                    busy          <= 1'b1;
                end
            end else begin
                if (inside_circle &&
                    (canvas_x >= 0) && (canvas_x < 320) &&
                    (canvas_y >= 0) && (canvas_y < 240)) begin
                    ram_we    <= 1'b1;
                    ram_waddr <= $unsigned(canvas_y) * 320 + $unsigned(canvas_x);
                    ram_wdata <= color_reg;
                end

                if (offset_x == radius_signed) begin
                    offset_x <= -radius_signed;
                    if (offset_y == radius_signed) begin
                        busy       <= 1'b0;
                        stamp_done <= 1'b1;
                    end else begin
                        offset_y <= offset_y + 6'sd1;
                    end
                end else begin
                    offset_x <= offset_x + 6'sd1;
                end
            end
        end
    end
endmodule
