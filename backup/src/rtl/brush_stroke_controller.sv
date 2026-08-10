`timescale 1ns / 1ps

// Buffers frame events and maintains stroke continuity across rendered lines.
module brush_stroke_controller (
    input  logic        clk,
    input  logic        rst,
    input  logic        frame_done,
    input  logic        pen_present,
    input  logic [8:0]  X_center,
    input  logic [8:0]  Y_center,
    input  logic [2:0]  sw_pen_color,
    input  logic        sw_eraser,
    input  logic        sw_size,

    input  logic        line_ready,
    input  logic        line_done,
    output logic        line_start,
    output logic [8:0]  line_x0,
    output logic [8:0]  line_y0,
    output logic [8:0]  line_x1,
    output logic [8:0]  line_y1,
    output logic [3:0]  line_color,
    output logic [4:0]  line_radius,
    output logic [10:0] line_threshold,
    output logic        busy
);
    logic       active;
    logic       prev_valid;
    logic [8:0] prev_x;
    logic [8:0] prev_y;
    logic [8:0] active_end_x;
    logic [8:0] active_end_y;

    logic        pending_valid;
    logic        pending_pen;
    logic [8:0]  pending_x;
    logic [8:0]  pending_y;
    logic [3:0]  pending_color;
    logic [4:0]  pending_radius;
    logic [10:0] pending_threshold;

    // Remains set until the next Pen Down is consumed, so a brief Pen Up
    // cannot be overwritten by a newer pending coordinate.
    logic break_pending;

    assign busy = active | pending_valid | line_start;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            active            <= 1'b0;
            prev_valid        <= 1'b0;
            prev_x            <= 9'd0;
            prev_y            <= 9'd0;
            active_end_x      <= 9'd0;
            active_end_y      <= 9'd0;
            pending_valid     <= 1'b0;
            pending_pen       <= 1'b0;
            pending_x         <= 9'd0;
            pending_y         <= 9'd0;
            pending_color     <= 4'b0000;
            pending_radius    <= 5'd2;
            pending_threshold <= 11'd6;
            break_pending     <= 1'b0;
            line_start        <= 1'b0;
            line_x0           <= 9'd0;
            line_y0           <= 9'd0;
            line_x1           <= 9'd0;
            line_y1           <= 9'd0;
            line_color        <= 4'b0000;
            line_radius       <= 5'd2;
            line_threshold    <= 11'd6;
        end else begin
            line_start <= 1'b0;

            if (line_done) begin
                active <= 1'b0;
                if (break_pending || (frame_done && !pen_present)) begin
                    prev_valid <= 1'b0;
                end else begin
                    prev_x     <= active_end_x;
                    prev_y     <= active_end_y;
                    prev_valid <= 1'b1;
                end
            end

            if (frame_done) begin
                pending_valid <= 1'b1;
                pending_pen   <= pen_present;
                pending_x     <= X_center;
                pending_y     <= Y_center;
                pending_color <= sw_eraser ? 4'b0000 : {1'b1, sw_pen_color};

                case ({sw_eraser, sw_size})
                    2'b00: begin
                        pending_radius    <= 5'd2;
                        pending_threshold <= 11'd6;
                    end
                    2'b01: begin
                        pending_radius    <= 5'd3;
                        pending_threshold <= 11'd12;
                    end
                    2'b10: begin
                        pending_radius    <= 5'd5;
                        pending_threshold <= 11'd25;
                    end
                    2'b11: begin
                        pending_radius    <= 5'd7;
                        pending_threshold <= 11'd49;
                    end
                    default: begin
                        pending_radius    <= 5'd2;
                        pending_threshold <= 11'd6;
                    end
                endcase

                if (!pen_present) begin
                    break_pending <= 1'b1;
                    prev_valid    <= 1'b0;
                end
            end

            // Delay consumption when a newer frame is arriving in this cycle.
            if (!active && pending_valid && line_ready && !frame_done) begin
                pending_valid <= 1'b0;

                if (pending_pen) begin
                    line_x0 <= (prev_valid && !break_pending) ? prev_x : pending_x;
                    line_y0 <= (prev_valid && !break_pending) ? prev_y : pending_y;
                    line_x1 <= pending_x;
                    line_y1 <= pending_y;
                    line_color     <= pending_color;
                    line_radius    <= pending_radius;
                    line_threshold <= pending_threshold;
                    active_end_x   <= pending_x;
                    active_end_y   <= pending_y;
                    line_start     <= 1'b1;
                    active         <= 1'b1;
                    break_pending  <= 1'b0;
                end else begin
                    prev_valid    <= 1'b0;
                    break_pending <= 1'b0;
                end
            end
        end
    end
endmodule
