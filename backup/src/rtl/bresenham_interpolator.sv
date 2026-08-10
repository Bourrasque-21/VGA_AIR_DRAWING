`timescale 1ns / 1ps

// Emits each center-line point and waits for its brush stamp to finish.
module bresenham_interpolator (
    input  logic       clk,
    input  logic       rst,
    input  logic       line_start,
    input  logic [8:0] line_x0,
    input  logic [8:0] line_y0,
    input  logic [8:0] line_x1,
    input  logic [8:0] line_y1,
    output logic       line_ready,
    output logic       line_done,

    output logic       point_valid,
    input  logic       point_ready,
    output logic [8:0] point_x,
    output logic [8:0] point_y,
    input  logic       stamp_done,
    output logic       busy
);
    typedef enum logic [1:0] {
        PATH_IDLE,
        PATH_ISSUE_POINT,
        PATH_WAIT_STAMP
    } path_state_t;

    path_state_t state;
    logic signed [9:0] x_cur;
    logic signed [9:0] y_cur;
    logic signed [9:0] x_end;
    logic signed [9:0] y_end;
    logic signed [9:0] dx;
    logic signed [9:0] dy;
    logic signed [9:0] step_x;
    logic signed [9:0] step_y;
    logic signed [9:0] err;
    logic signed [10:0] err_twice;

    assign line_ready  = (state == PATH_IDLE);
    assign point_valid = (state == PATH_ISSUE_POINT);
    assign point_x     = x_cur[8:0];
    assign point_y     = y_cur[8:0];
    assign busy        = (state != PATH_IDLE);
    assign err_twice   = $signed({err[9], err}) <<< 1;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= PATH_IDLE;
            line_done <= 1'b0;
            x_cur     <= 10'sd0;
            y_cur     <= 10'sd0;
            x_end     <= 10'sd0;
            y_end     <= 10'sd0;
            dx        <= 10'sd0;
            dy        <= 10'sd0;
            step_x    <= 10'sd0;
            step_y    <= 10'sd0;
            err       <= 10'sd0;
        end else begin
            line_done <= 1'b0;

            case (state)
                PATH_IDLE: begin
                    if (line_start) begin
                        x_cur  <= $signed({1'b0, line_x0});
                        y_cur  <= $signed({1'b0, line_y0});
                        x_end  <= $signed({1'b0, line_x1});
                        y_end  <= $signed({1'b0, line_y1});
                        dx     <= (line_x1 >= line_x0)
                                  ? $signed({1'b0, line_x1 - line_x0})
                                  : $signed({1'b0, line_x0 - line_x1});
                        dy     <= (line_y1 >= line_y0)
                                  ? -$signed({1'b0, line_y1 - line_y0})
                                  : -$signed({1'b0, line_y0 - line_y1});
                        step_x <= (line_x0 < line_x1) ? 10'sd1 : -10'sd1;
                        step_y <= (line_y0 < line_y1) ? 10'sd1 : -10'sd1;
                        err    <= ((line_x1 >= line_x0)
                                  ? $signed({1'b0, line_x1 - line_x0})
                                  : $signed({1'b0, line_x0 - line_x1}))
                                  + ((line_y1 >= line_y0)
                                  ? -$signed({1'b0, line_y1 - line_y0})
                                  : -$signed({1'b0, line_y0 - line_y1}));
                        state <= PATH_ISSUE_POINT;
                    end
                end

                PATH_ISSUE_POINT: begin
                    if (point_ready) begin
                        state <= PATH_WAIT_STAMP;
                    end
                end

                PATH_WAIT_STAMP: begin
                    if (stamp_done) begin
                        if ((x_cur == x_end) && (y_cur == y_end)) begin
                            line_done <= 1'b1;
                            state     <= PATH_IDLE;
                        end else begin
                            if ((err_twice >= dy) && (err_twice <= dx)) begin
                                err   <= err + dy + dx;
                                x_cur <= x_cur + step_x;
                                y_cur <= y_cur + step_y;
                            end else if (err_twice >= dy) begin
                                err   <= err + dy;
                                x_cur <= x_cur + step_x;
                            end else if (err_twice <= dx) begin
                                err   <= err + dx;
                                y_cur <= y_cur + step_y;
                            end
                            state <= PATH_ISSUE_POINT;
                        end
                    end
                end

                default: state <= PATH_IDLE;
            endcase
        end
    end
endmodule
