module canvas_buffer_top (
    input  logic                       rst,          // 시스템 리셋
    input  logic                       vsync,        // 카메라 프레임 vsync
    input  logic [                2:0] sw_pen_color, // 펜 색상 (pen_config_controller에서 공급)
    input  logic                       sw_eraser,     // 지우개
    input  logic                       sw_size,       // 펜/지우개 두께
    input  logic                       sw_texture_enable,
    input  logic [                2:0] sw_texture_shape, // 질감 모드 직접 입력 (상태는 pen_config_controller가 소유)

    // wrtie side
    input  logic                       wclk,
    input  logic                       we,
    input  logic [$clog2(320*240)-1:0] waddr,
    input  logic [               15:0] wdata,
    // read side
    input  logic                       rclk,
    input  logic [$clog2(320*240)-1:0] raddr,
    output logic [               15:0] rdata,

    output logic [                8:0] X_center,
    output logic [                8:0] Y_center,
    input  logic canvas_clear,
    output logic paint_sel
);
    logic       green_detected;
    logic       frame_done;
    logic       pen_present;

    logic       engine_we;
    logic [$clog2(320*240)-1:0] engine_waddr;
    logic [3:0] engine_wdata; // 4비트
    logic [3:0] o_canvas;     // 4비트

    // 필터 연동용 신호 선언
    logic [8:0] X_raw;
    logic [8:0] Y_raw;
    logic       pen_raw;
    logic       valid_raw;

    // 1. 초록색 감지 모듈
    colour_detector U_colour_detector (
        .wdata         (wdata),
        .green_detected(green_detected)
    );

    // 2. BBox 중심 연산기 모듈 (나눗셈 제거 + Erosion 잡음 제거)
    bbox_center_accum #(
        .PEN_MIN (15),
        .ERODE   (1'b1)
    ) U_bbox_center_accum (
        .pclk (wclk),
        .vsync(vsync),
        .we   (we),
        .hit  (green_detected),
        .cx   (X_raw),
        .cy   (Y_raw),
        .pen  (pen_raw),
        .valid(valid_raw)
    );

    // 3. 이동 평균 필터 모듈 (과도응답 방지 + 나누기 5 곱셈 대체 고속 연산)
    coord_filter U_coord_filter (
        .pclk   (wclk),
        .valid  (valid_raw),
        .cx     (X_raw),
        .cy     (Y_raw),
        .pen_in (pen_raw),
        .ax     (X_center),
        .ay     (Y_center),
        .pen    (pen_present),
        .valid_o(frame_done)
    );

    // 3. 브러시 그리기 엔진 모듈 (4비트 데이터 출력 및 지우개 스위치 수신)
    brush_draw_engine U_brush_draw_engine (
        .clk          (wclk),
        .rst          (rst),
        .frame_done   (frame_done),
        .pen_present  (pen_present),
        .X_center     (X_center),
        .Y_center     (Y_center),
        .sw_pen_color (sw_pen_color),
        .sw_eraser    (sw_eraser),
        .sw_size      (sw_size),
        .pen_texture_enable(sw_texture_enable),
        .pen_texture_shape (sw_texture_shape),
        .ram_we       (engine_we),
        .ram_waddr    (engine_waddr),
        .ram_wdata    (engine_wdata),
        .engine_busy  ()
    );

    // 4. 4비트 Canvas Buffer
    canvas_buffer U_canvas_buffer (
        .wclk        (wclk),
        .canvas_clear(canvas_clear),
        .we          (engine_we), 
        .waddr       (engine_waddr),
        .wdata       (engine_wdata),
        .rclk        (rclk),
        .raddr       (raddr),
        .rdata       (o_canvas)
    );

    // 4비트 픽셀 직결 디코딩 (R[2], G[1], B[0] 비트를 복사하여 RGB565 변환, MSB[3]은 paint_sel 결선)
    always_comb begin
        paint_sel = o_canvas[3]; // valid 플래그에 따라 배경 투과 여부 직결
        rdata     = { {5{o_canvas[2]}}, {6{o_canvas[1]}}, {5{o_canvas[0]}} }; // 비트 다이렉트 맵핑
    end

endmodule




module canvas_buffer (
    // write side (wclk 도메인)
    input  logic                       wclk,
    input  logic                       canvas_clear,
    input  logic                       we,
    input  logic [$clog2(320*240)-1:0] waddr,
    input  logic [                3:0] wdata,
    // read side (rclk 도메인)
    input  logic                       rclk,
    input  logic [$clog2(320*240)-1:0] raddr,
    output logic [                3:0] rdata
);

    // 100% BRAM 추론을 위한 4비트 76,800깊이의 메모리 어레이 선언 (초기값 0000(투명))
    logic [3:0] mem[0:(320*240)-1] = '{default: 4'b0000};

    logic clearing;
    logic [$clog2(320*240)-1:0] cnt;

    // 1. 클리어 제어 로직 (Sequential)
    always_ff @(posedge wclk) begin
        if (canvas_clear) begin
            cnt      <= 0;
            clearing <= 1'b1;
        end else if (clearing) begin
            if (cnt == (320 * 240 - 1)) begin
                clearing <= 1'b0;
            end else begin
                cnt <= cnt + 1;
            end
        end
    end

    // 2. RAM 입력 신호 MUX (Combinational -> 추가 딜레이 없음)
    logic                       ram_we;
    logic [$clog2(320*240)-1:0] ram_waddr;
    logic [3:0]                 ram_wdata;

    assign ram_we    = clearing ? 1'b1   : we;
    assign ram_waddr = clearing ? cnt    : waddr;
    assign ram_wdata = clearing ? 4'b0000 : wdata; // 초기화 시 4'b0000(투명) 기입

    // 3. 표준 BRAM 쓰기 포트 템플릿 (오직 하나의 always_ff 및 단일 주소/데이터/쓰기 변수)
    always_ff @(posedge wclk) begin
        if (ram_we) begin
            mem[ram_waddr] <= ram_wdata;
        end
    end

    // 4. 표준 BRAM 읽기 포트 템플릿
    always_ff @(posedge rclk) begin
        rdata <= mem[raddr];
    end

endmodule

