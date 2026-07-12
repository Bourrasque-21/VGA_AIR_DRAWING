`timescale 1ns / 1ps

//================================================================================
//  Module Name : brush_draw_engine
//  Description : Bresenham 선 보간 FSM + 가변 원형 브러시(5x5 원형 / 7x7 원형) 그리기 엔진
//
//  [동작 방식]
//  - 마커 펜이 감지되면(pen_present=1) 이전 펜 위치와 현재 펜 위치 사이에
//    브레젠험(Bresenham) 알고리즘으로 누락된 직선 좌표들을 보간합니다.
//  - 각 보간 좌표마다 sw_size 스위치 설정에 맞게 가변 크기 브러시를 메모리에 그립니다.
//    * sw_size = 0 : 5x5 크기 원형 브러시 (모퉁이 제외 총 21픽셀 기입)
//    * sw_size = 1 : 7x7 크기 원형 브러시 (모퉁이 제외 총 37픽셀 기입 - 대폭 상향!)
//  - sw_eraser = 1 인 경우 BRAM에 4'b0000(투명)을 써서 선을 지우는 지우개 모드로 동작합니다.
//================================================================================
module brush_draw_engine (
    input  logic                       clk,           // BRAM 쓰기 클럭 (pclk)
    input  logic                       rst,           // 시스템 리셋
    input  logic                       frame_done,    // 필터로부터 프레임 캡처 완료 신호
    input  logic                       pen_present,   // 현재 펜 검출 상태
    input  logic [                8:0] X_center,      // 평활화된 펜 X 좌표
    input  logic [                7:0] Y_center,      // 평활화된 펜 Y 좌표
    input  logic [                2:0] sw_pen_color,  // 사용자 펜 색상 조합 스위치
    input  logic                       sw_eraser,     // 지우개 스위치
    input  logic                       sw_size,       // 브러시 두께 선택 스위치 (0=5x5 얇음, 1=7x7 굵음)

    output logic                       ram_we,        // BRAM 쓰기 신호
    output logic [$clog2(320*240)-1:0] ram_waddr,     // BRAM 쓰기 주소
    output logic [                3:0] ram_wdata,     // BRAM 쓰기 데이터 ([3]=valid, [2:0]=RGB)
    output logic                       engine_busy    // 그리기 FSM 작동 중 플래그
);

    typedef enum logic [1:0] {
        STATE_IDLE       = 2'b00,
        STATE_PREP_LINE  = 2'b01,
        STATE_DRAW_BRUSH = 2'b10,
        STATE_NEXT_POINT = 2'b11
    } state_t;

    state_t state;

    // 현재 프레임 펜 위치 및 색상 레지스터
    logic [ 8:0] X_center_reg;
    logic [ 7:0] Y_center_reg;
    logic [ 3:0] color_reg;

    // 이전 프레임의 펜 위치 레지스터
    logic [ 8:0] X_prev;
    logic [ 7:0] Y_prev;
    logic        prev_valid; // 이전 좌표의 유효 여부

    // 브레젠험 라인 알고리즘 부호 있는 변수들
    logic signed [9:0] x_line;
    logic signed [9:0] y_line;
    logic signed [9:0] dx_l;
    logic signed [9:0] dy_l;
    logic signed [9:0] sx;
    logic signed [9:0] sy;
    logic signed [9:0] err;
    logic signed [10:0] e2;

    // 브러시 내부 로컬 오프셋 스캔 변수
    logic signed [3:0] dx_b;
    logic signed [3:0] dy_b;

    // 최종 메모리에 기입할 픽셀 좌표 (라인 보간 좌표 + 브러시 오프셋)
    logic signed [11:0] cur_x;
    logic signed [10:0] cur_y;

    assign cur_x = x_line + dx_b;
    assign cur_y = y_line + dy_b;

    // 5x5 / 7x7 원형 브러시 동적 제어 매개변수 (0=5x5 모드(limit 2), 1=7x7 모드(limit 3))
    logic signed [2:0] brush_limit;
    logic [3:0] sq_threshold;

    assign brush_limit  = sw_size ? 3'sd3 : 3'sd2;
    assign sq_threshold = sw_size ? 4'd12 : 4'd6;   // 제곱합 원형 반경 기준값 (7x7=12, 5x5=6)

    // 하드웨어 자원을 거의 먹지 않는 컴바이너리 절대값 제곱 연산 (오프셋 0~3 대상)
    logic [3:0] dx_b_sq;
    logic [3:0] dy_b_sq;
    assign dx_b_sq = (dx_b < 0) ? $unsigned(-dx_b) * $unsigned(-dx_b) : $unsigned(dx_b) * $unsigned(dx_b);
    assign dy_b_sq = (dy_b < 0) ? $unsigned(-dy_b) * $unsigned(-dy_b) : $unsigned(dy_b) * $unsigned(dy_b);

    // 제곱 거리 공식을 이용한 정밀 가변 원형 마스크 조건 (dx^2 + dy^2 <= Threshold)
    logic is_inside_circle;
    assign is_inside_circle = (dx_b_sq + dy_b_sq <= sq_threshold);

    assign engine_busy = (state != STATE_IDLE);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= STATE_IDLE;
            X_center_reg <= 0;
            Y_center_reg <= 0;
            color_reg    <= 4'b0000;
            X_prev       <= 0;
            Y_prev       <= 0;
            prev_valid   <= 1'b0;
            x_line       <= 0;
            y_line       <= 0;
            dx_l         <= 0;
            dy_l         <= 0;
            sx           <= 0;
            sy           <= 0;
            err          <= 0;
            dx_b         <= -2;
            dy_b         <= -2;
            ram_we       <= 1'b0;
            ram_waddr    <= 0;
            ram_wdata    <= 4'b0000;
        end else begin
            ram_we <= 1'b0; // 기본적으로 쓰기 비활성화

            case (state)
                STATE_IDLE: begin
                    if (frame_done) begin
                        if (pen_present) begin
                            X_center_reg <= X_center;
                            Y_center_reg <= Y_center;
                            // 지우개 모드 동작 시 valid=0(4'b0000), 평상시 그리기 모드는 valid=1(4'b1xxx) + 스위치 색상 기입
                            color_reg    <= sw_eraser ? 4'b0000 : {1'b1, sw_pen_color};
                            state        <= STATE_PREP_LINE;
                        end else begin
                            // 펜이 화면에서 벗어나면 이전 펜 히스토리 무효화
                            prev_valid   <= 1'b0;
                        end
                    end
                end

                STATE_PREP_LINE: begin
                    if (!prev_valid) begin
                        // 펜이 새로 닿았을 때: 1개의 독립된 점으로 그리기 시작
                        X_prev     <= X_center_reg;
                        Y_prev     <= Y_center_reg;
                        prev_valid <= 1'b1;
                        x_line     <= $signed({1'b0, X_center_reg});
                        y_line     <= $signed({1'b0, Y_center_reg});
                        dx_l       <= 0;
                        dy_l       <= 0;
                        sx         <= 0;
                        sy         <= 0;
                        err        <= 0;
                    end else begin
                        // 연속 그리기 모드: 이전 펜 위치부터 이번 펜 위치까지 라인 보간 파라미터 계산
                        x_line     <= $signed({1'b0, X_prev});
                        y_line     <= $signed({1'b0, Y_prev});
                        dx_l       <= (X_center_reg >= X_prev) ? $signed({1'b0, X_center_reg - X_prev}) : $signed({1'b0, X_prev - X_center_reg});
                        dy_l       <= (Y_center_reg >= Y_prev) ? -$signed({1'b0, Y_center_reg - Y_prev}) : -$signed({1'b0, Y_prev - Y_center_reg});
                        sx         <= (X_prev < X_center_reg) ? 10'sd1 : -10'sd1;
                        sy         <= (Y_prev < Y_center_reg) ? 10'sd1 : -10'sd1;
                        err        <= ((X_center_reg >= X_prev) ? $signed({1'b0, X_center_reg - X_prev}) : $signed({1'b0, X_prev - X_center_reg})) + 
                                      ((Y_center_reg >= Y_prev) ? -$signed({1'b0, Y_center_reg - Y_prev}) : -$signed({1'b0, Y_prev - Y_center_reg}));
                    end
                    // 브러시 크기(sw_size)에 맞춰 루프 시작 오프셋 동적 인가 (-3 또는 -2)
                    dx_b  <= sw_size ? -3 : -2;
                    dy_b  <= sw_size ? -3 : -2;
                    state <= STATE_DRAW_BRUSH;
                end

                STATE_DRAW_BRUSH: begin
                    // 원형 브러시 범위 내이고 가로 320, 세로 240 화면 영역 안일 때만 BRAM 기입
                    if (is_inside_circle && cur_x >= 0 && cur_x < 320 && cur_y >= 0 && cur_y < 240) begin
                        ram_we    <= 1'b1;
                        ram_waddr <= $unsigned(cur_y) * 320 + $unsigned(cur_x);
                        ram_wdata <= color_reg;
                    end

                    // 브러시 2D 격자 스캔 루프 (brush_limit에 의존)
                    if (dx_b == brush_limit) begin
                        dx_b <= sw_size ? -3 : -2; // 가로 시작점으로 롤백
                        if (dy_b == brush_limit) begin
                            state <= STATE_NEXT_POINT; // 현재 점의 브러시 그리기 완료 ➔ 다음 보간 점 판정으로 전이
                        end else begin
                            dy_b <= dy_b + 1;
                        end
                    end else begin
                        dx_b <= dx_b + 1;
                    end
                end

                STATE_NEXT_POINT: begin
                    if (x_line == $signed({1'b0, X_center_reg}) && y_line == $signed({1'b0, Y_center_reg})) begin
                        // 라인의 종점까지 다 도달했으면 이 프레임 보간 완료 ➔ IDLE로 전이
                        X_prev <= X_center_reg;
                        Y_prev <= Y_center_reg;
                        state  <= STATE_IDLE;
                    end else begin
                        // 상호 배제적 브레젠험 알고리즘으로 다음 보간 점 좌표 갱신
                        e2 = 2 * err;
                        if (e2 >= dy_l && e2 <= dx_l) begin
                            err    <= err + dy_l + dx_l;
                            x_line <= x_line + sx;
                            y_line <= y_line + sy;
                        end else if (e2 >= dy_l) begin
                            err    <= err + dy_l;
                            x_line <= x_line + sx;
                        end else if (e2 <= dx_l) begin
                            err    <= err + dx_l;
                            y_line <= y_line + sy;
                        end
                        // 새로운 보간 점의 브러시 기입을 위한 스캔 시작 오프셋 인가
                        dx_b  <= sw_size ? -3 : -2;
                        dy_b  <= sw_size ? -3 : -2;
                        state <= STATE_DRAW_BRUSH;
                    end
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

endmodule
