/*
 * 비활성 레거시 모듈
 *
 * 현재 설계는 pen_filter.sv의 bbox_center_accum과 coord_filter를 사용합니다.
 * 이 모듈은 마지막으로 검출된 녹색 픽셀 좌표만 저장하는 이전 구현이며,
 * 합성 경로에서 인스턴스되지 않으므로 참고용으로만 보관합니다.
 *
`timescale 1ns / 1ps

module pen_pos_tracker (
    input  logic                       pclk,
    input  logic                       reset,
    input  logic                       vsync,
    input  logic                       we,
    input  logic                       green_detected,

    output logic [                8:0] X_center, // 0~319
    output logic [                7:0] Y_center, // 0~239
    output logic                       frame_done,    // 1클럭 펄스 (중점 갱신 완료 알림)
    output logic                       pen_present    // 현재 프레임에 펜이 존재했는지 여부
);

    logic [8:0] x_cnt;
    logic [7:0] y_cnt;

    // 1. 카메라 스캔 동작 기반 픽셀 좌표 디코더 (나눗셈 제거용 카운터 구성)
    always_ff @(posedge pclk or posedge reset) begin
        if (reset) begin
            x_cnt <= 0;
            y_cnt <= 0;
        end else if (vsync) begin
            x_cnt <= 0;
            y_cnt <= 0;
        end else if (we) begin
            if (x_cnt == 9'd319) begin
                x_cnt <= 0;
                if (y_cnt == 8'd239) begin
                    y_cnt <= 0;
                end else begin
                    y_cnt <= y_cnt + 1;
                end
            end else begin
                x_cnt <= x_cnt + 1;
            end
        end
    end

    // 2. 가변 나눗셈기(/)를 완전히 제거하고 센서 잡음을 필터링하기 위한 카운터 기반 로직
    logic [8:0] saved_x;
    logic [7:0] saved_y;
    logic [16:0] count; // 한 프레임 동안 감지된 초록색 픽셀 수

    logic vsync_d1;
    always_ff @(posedge pclk or posedge reset) begin
        if (reset) begin
            vsync_d1 <= 1'b0;
        end else begin
            vsync_d1 <= vsync;
        end
    end

    // VSYNC 상승 엣지 검출 (프레임 캡쳐 완료 시점)
    logic vsync_posedge;
    assign vsync_posedge = vsync && !vsync_d1;

    // 대표 좌표 갱신 및 리셋 FSM
    always_ff @(posedge pclk or posedge reset) begin
        if (reset) begin
            saved_x          <= 0;
            saved_y          <= 0;
            count            <= 0;
            X_center         <= 0;
            Y_center         <= 0;
            frame_done       <= 1'b0;
            pen_present      <= 1'b0;
        end else begin
            frame_done <= 1'b0; // 디폴트 비활성화

            if (vsync_posedge) begin
                // 프레임 끝에서 검출 횟수 확인 (최소 15픽셀 이상 면적 검출 시에만 유효한 펜으로 판정)
                if (count >= 17'd15) begin
                    X_center    <= saved_x;
                    Y_center    <= saved_y;
                    pen_present <= 1'b1;
                end else begin
                    pen_present <= 1'b0;
                end
                frame_done <= 1'b1; // 엔진 시작 트리거 펄스 출력

                // 다음 프레임을 위한 준비
                count <= 0;
            end else if (!vsync) begin
                // 프레임 진행 중 G 펜이 검출되면 좌표 저장 및 카운터 증가
                if (we && green_detected) begin
                    saved_x <= x_cnt;
                    saved_y <= y_cnt;
                    count   <= count + 1;
                end
            end
        end
    end

endmodule
*/
