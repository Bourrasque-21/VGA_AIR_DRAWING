module bresenham_interpolator (
    input  logic       clk,
    input  logic       rst,
    input  logic       i_line_start,
    input  logic [8:0] i_line_x0,
    input  logic [8:0] i_line_y0,
    input  logic [8:0] i_line_x1,
    input  logic [8:0] i_line_y1,
    output logic       o_line_ready,
    output logic       o_line_done,
    output logic       o_point_valid,
    input  logic       i_point_ready,
    output logic [8:0] o_point_x,
    output logic [8:0] o_point_y,
    input  logic       i_stamp_done,
    output logic       o_busy
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

    assign o_line_ready  = (state == PATH_IDLE);
    assign o_point_valid = (state == PATH_ISSUE_POINT);
    assign o_point_x     = x_cur[8:0];
    assign o_point_y     = y_cur[8:0];
    assign o_busy        = (state != PATH_IDLE);
    assign err_twice   = $signed({err[9], err}) <<< 1;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= PATH_IDLE;
            o_line_done <= 1'b0;
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
            o_line_done <= 1'b0;

            case (state)
                PATH_IDLE: begin
                    if (i_line_start) begin
                        x_cur  <= $signed({1'b0, i_line_x0});
                        y_cur  <= $signed({1'b0, i_line_y0});
                        x_end  <= $signed({1'b0, i_line_x1});
                        y_end  <= $signed({1'b0, i_line_y1});
                        dx     <= (i_line_x1 >= i_line_x0)
                                  ? $signed({1'b0, i_line_x1 - i_line_x0})
                                  : $signed({1'b0, i_line_x0 - i_line_x1});
                        dy     <= (i_line_y1 >= i_line_y0)
                                  ? -$signed({1'b0, i_line_y1 - i_line_y0})
                                  : -$signed({1'b0, i_line_y0 - i_line_y1});
                        step_x <= (i_line_x0 < i_line_x1) ? 10'sd1 : -10'sd1;
                        step_y <= (i_line_y0 < i_line_y1) ? 10'sd1 : -10'sd1;
                        err    <= ((i_line_x1 >= i_line_x0)
                                  ? $signed({1'b0, i_line_x1 - i_line_x0})
                                  : $signed({1'b0, i_line_x0 - i_line_x1}))
                                  + ((i_line_y1 >= i_line_y0)
                                  ? -$signed({1'b0, i_line_y1 - i_line_y0})
                                  : -$signed({1'b0, i_line_y0 - i_line_y1}));
                        state <= PATH_ISSUE_POINT;
                    end
                end

                PATH_ISSUE_POINT: begin
                    if (i_point_ready) begin
                        state <= PATH_WAIT_STAMP;
                    end
                end

                PATH_WAIT_STAMP: begin
                    if (i_stamp_done) begin
                        if ((x_cur == x_end) && (y_cur == y_end)) begin
                            o_line_done <= 1'b1;
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
