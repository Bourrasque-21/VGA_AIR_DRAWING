`timescale 1ns / 1ps

// 펜 설정의 단일 상태 소유자.
// UART 패킷 수신 이벤트와 버튼 이벤트(지우개 토글 / 펜모드 순환 / 두께 토글)를
// 같은 레지스터에 병합한다 (last-write-wins, 동시 발생 시 버튼 우선).
//
// 펜모드 순환: PEN -> SPRAY -> DIAG -> PEN. 모드 버튼은 지우개를 해제한다.
// 굵기 인코딩: PEN/지우개 = size 비트, SPRAY = shape 0(얇게)/2(굵게),
//              DIAG = shape 3(얇게)/4(굵게). 버튼은 size와 shape를 함께 갱신한다.
//
// 모든 상태는 clk(100MHz) 도메인. 드로잉 로직(wclk=pclk)은 프레임 경계에서만
// 설정을 래치하는 준정적(quasi-static) 소비자라 기존 스위치 직결과 동일하게
// 직접 연결한다. clear는 1클럭 이벤트라서 pclk가 놓치지 않도록
// CLEAR_STRETCH 클럭만큼 늘려서 내보낸다.
module pen_config_controller #(
    parameter int CLEAR_STRETCH = 256
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       i_uart_valid,
    input  logic [2:0] i_uart_pen_color,
    input  logic       i_uart_eraser,
    input  logic       i_uart_size,
    input  logic       i_uart_texture_enable,
    input  logic [2:0] i_uart_texture_shape,
    input  logic       i_uart_paper,
    input  logic       i_uart_freeze,
    input  logic       i_uart_clear_pulse,
    input  logic       i_btn_eraser,
    input  logic       i_btn_mode,
    input  logic       i_btn_size,
    output logic [2:0] o_pen_color,
    output logic       o_eraser,
    output logic       o_size,
    output logic       o_texture_enable,
    output logic [2:0] o_texture_shape,
    output logic       o_paper,
    output logic       o_freeze,
    output logic       o_clear
);
    localparam logic [2:0] SHAPE_MAX = 3'd4;

    logic [$clog2(CLEAR_STRETCH)-1:0] clear_cnt;
    logic clear_active;

    assign o_clear = clear_active;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            o_pen_color      <= 3'b100;  // 기본값: 빨강 펜, 얇게
            o_eraser         <= 1'b0;
            o_size           <= 1'b0;
            o_texture_enable <= 1'b0;
            o_texture_shape  <= 3'd0;
            o_paper          <= 1'b0;
            o_freeze         <= 1'b0;
            clear_cnt        <= '0;
            clear_active     <= 1'b0;
        end else begin
            if (i_uart_valid) begin
                o_pen_color      <= i_uart_pen_color;
                o_eraser         <= i_uart_eraser;
                o_size           <= i_uart_size;
                o_texture_enable <= i_uart_texture_enable;
                o_texture_shape  <= (i_uart_texture_shape > SHAPE_MAX)
                                    ? SHAPE_MAX : i_uart_texture_shape;
                o_paper          <= i_uart_paper;
                o_freeze         <= i_uart_freeze;
            end

            // 버튼 이벤트 (뒤에 배치되어 UART와 같은 클럭에 겹치면 버튼이 이김)
            if (i_btn_eraser) begin
                o_eraser <= ~o_eraser;
            end

            if (i_btn_size) begin
                o_size <= ~o_size;   // 새 굵기 = ~o_size
                if (o_texture_enable) begin
                    if (o_texture_shape <= 3'd2) begin
                        o_texture_shape <= (~o_size) ? 3'd2 : 3'd0;  // SPRAY
                    end else begin
                        o_texture_shape <= (~o_size) ? 3'd4 : 3'd3;  // DIAG
                    end
                end
            end

            if (i_btn_mode) begin
                o_eraser <= 1'b0;    // 도구를 고르면 지우개 해제
                if (!o_texture_enable) begin                 // PEN -> SPRAY
                    o_texture_enable <= 1'b1;
                    o_texture_shape  <= o_size ? 3'd2 : 3'd0;
                end else if (o_texture_shape <= 3'd2) begin  // SPRAY -> DIAG
                    o_texture_shape <= o_size ? 3'd4 : 3'd3;
                end else begin                               // DIAG -> PEN
                    o_texture_enable <= 1'b0;
                end
            end

            if (i_uart_clear_pulse) begin
                clear_active <= 1'b1;
                clear_cnt    <= '0;
            end else if (clear_active) begin
                if (clear_cnt == CLEAR_STRETCH - 1) begin
                    clear_active <= 1'b0;
                    clear_cnt    <= '0;
                end else begin
                    clear_cnt <= clear_cnt + 1;
                end
            end
        end
    end
endmodule
