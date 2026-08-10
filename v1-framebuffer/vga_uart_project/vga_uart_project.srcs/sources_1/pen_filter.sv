`timescale 1ns / 1ps

//================================================================================
//  Module Name : bbox_center_accum
//  Description : 초록색 마커 펜의 Bounding Box 중심 검출 모듈
//  
//  [하드웨어 최적화 & 동작 원리]
//  1. Bounding Box (BBox) 방식 채택:
//     - 프레임 내 검출된 픽셀의 상하좌우 최소/최대값만 추적하고,
//       프레임 끝(VSYNC 상승엣지)에서 (min + max) >> 1 연산으로 BBox 중심을 구합니다.
//     - 검출 픽셀 전체의 평균을 구하는 실제 무게중심 연산과는 구분됩니다.
//
//  2. 1D Erosion (침식) 필터 내장 (소금 노이즈 차단):
//     - BBox 방식의 약점은 단 1픽셀짜리 미세 잡음광에도 경계선이 크게 늘어난다는 점입니다.
//     - 이를 방지하기 위해 가로로 연속 3픽셀 검출(hit & hit_d1 & hit_d2)이 이루어진
//       경우에만 유효한 마커 영역으로 쳐서 노이즈가 중심을 왜곡시키는 것을 방지합니다.
//
//  3. 10비트 오버플로우 방지 (Addition Extension):
//     - minx + maxx 합산 시 9비트 한계인 511을 초과하는 520(우측 화면 경계) 등의 상황에서
//       잘려 나가지 않도록 10비트 제로 확장 덧셈을 구현하여 우측 터치 차단 버그를 수정했습니다.
//================================================================================
module bbox_center_accum #(
    parameter int PEN_MIN = 15,   // 마커로 인정할 최소 검출 픽셀 개수
    parameter bit ERODE   = 1'b1  // 1 = 가로 연속 3픽셀 검출 필터 활성화
) (
    input  logic       pclk,       // 카메라 픽셀 쓰기 클럭 (pclk)
    input  logic       vsync,      // 카메라 VSYNC 신호 (Active High = 블랭킹 구간)
    input  logic       we,         // 픽셀 유효 기입 활성 신호
    input  logic       hit,        // 색상 검출기로부터 들어온 초록색 마커 판단 결과
    output logic [8:0] cx,         // BBox 기준 최종 중심 X 좌표 (0 ~ 319)
    output logic [8:0] cy,         // BBox 기준 최종 중심 Y 좌표 (0 ~ 239)
    output logic       pen,        // 검출 픽셀 수가 PEN_MIN 이상인 경우 유효 펜(Pen Down) 표시
    output logic       valid       // 프레임이 완료되어 새로운 중심좌표가 업데이트됨을 알리는 펄스 (1클럭)
);
    logic [8:0]  x = '0, y = '0;               // 320x240 화면을 스캔하는 가로/세로 좌표 카운터
    logic [8:0]  minx = 9'd511, maxx = '0;     // Bounding Box 경계 레지스터
    logic [8:0]  miny = 9'd511, maxy = '0;
    logic [16:0] cnt = '0;                     // 프레임당 검출된 유효 픽셀 수 카운터
    logic        vsync_d = 1'b0;
    logic        hit_d1 = 1'b0, hit_d2 = 1'b0; // Erosion용 딜레이 파이프라인 레지스터
    wire         vs_rise  = vsync & ~vsync_d;  // VSYNC의 라이징 엣지 검출 (프레임 캡처 종료 시점)
    wire         line_end = (x == 9'd319);     // 가로 끝 도달
    wire         eff_hit  = ERODE ? (hit & hit_d1 & hit_d2) : hit; // 3픽셀 연속 감지 조건
    wire [8:0]   eff_x    = ERODE ? (x - 9'd1) : x; // 3픽셀 윈도우의 중앙 X 좌표

    always_ff @(posedge pclk) begin
        vsync_d <= vsync;
        valid   <= 1'b0;

        if (vsync) begin
            // 카메라의 VSYNC 블랭킹 구간 (프레임 종료 및 리셋 구간)
            if (vs_rise) begin
                // 프레임이 끝난 찰나에 직전 수집된 경계선 데이터로 최종 중심좌표 도출
                if (cnt != 0) begin
                    // 10비트 임시 확장 덧셈을 수행하여 우측 화면 합산 시 오버플로우(>511)가 나는 버그를 방지
                    cx <= ( {1'b0, minx} + {1'b0, maxx} ) >> 1;
                    cy <= ( {1'b0, miny} + {1'b0, maxy} ) >> 1;
                end
                pen   <= (cnt >= PEN_MIN); // 최소 검출 픽셀 수를 넘으면 진짜 펜으로 마킹
                valid <= 1'b1;             // 새 좌표 갱신 완료 스트로브 출력
            end
            // 다음 프레임을 위한 내부 상태 리셋
            x <= 9'd0; y <= 9'd0; cnt <= 17'd0;
            minx <= 9'd511; maxx <= 9'd0; miny <= 9'd511; maxy <= 9'd0;
            hit_d1 <= 1'b0; hit_d2 <= 1'b0;

        end else if (we) begin
            // 가로 라인이 바뀔 때는 이전 라인의 끝 픽셀이 다음 라인의 시작 픽셀과 연결되어
            // 침식(Erosion) 필터가 세로 라인을 통과시키는 왜곡을 방지하기 위해 라인 끝에서 필터 리셋
            hit_d1 <= hit & ~line_end;
            hit_d2 <= hit_d1 & ~line_end;

            // 스캔 카운터 증가
            if (line_end) begin 
                x <= 9'd0; 
                y <= y + 9'd1; 
            end else begin
                x <= x + 9'd1;
            end

            // 잡음 침식(Erosion) 필터를 무사히 통과한 유효 픽셀만 BBox 경계선 갱신에 참여
            if (eff_hit) begin
                cnt <= cnt + 17'd1;
                if (eff_x < minx) minx <= eff_x;
                if (eff_x > maxx) maxx <= eff_x;
                if (y < miny) miny <= y;
                if (y > maxy) maxy <= y;
            end
        end
    end
endmodule


//================================================================================
//  Module Name : coord_filter
//  Description : 마커 좌표의 미세 떨림(Jitter) 및 순간이동(Spike)을 잡는 평활화 이동평균 필터
//  
//  [하드웨어 최적화 & 동작 원리]
//  1. 원형 큐(Circular Queue) 및 러닝 섬(Running Sum) 방식:
//     - 최근 5개 프레임의 좌표 정보를 원형 큐(크기 N=5)에 넣고 보관합니다.
//     - 매번 5개 데이터를 싹 더하는 무거운 가산기 트리 대신,
//       새로운 합 = 기존 합 - 가장 오래된 값 + 신규 입력 값 공식을 활용해 단 1클럭 O(1)로 러닝 섬을 연산합니다.
//
//  2. 고정소수점 나누기 5 (Divider-less 1/5):
//     - 5로 나누는 연산은 하드웨어 연산기가 매우 무겁게 설계됩니다.
//     - 이를 극복하기 위해 (합 * 205) >> 10 기법을 사용합니다.
//     - 205/1024 = 0.200195로, 1/5 = 0.2의 물리 오차 범위 내에서 나눗셈 없이 오직 곱셈기 한 개만으로 구현합니다.
//
//  3. 과도응답 제거를 위한 큐 자동 초기화 (Pre-fill):
//     - 펜이 화면 밖으로 나갔다가 다시 등장할 때 큐 내부에 이전 0 좌표가 남아있으면,
//       평균 필터 연산 때문에 펜이 (0,0) 모퉁이에서부터 쫙 끌려오면서 긴 실선 노이즈가 생깁니다.
//     - 이를 완벽 차단하기 위해 펜이 최초 감지된 시점(have_hist=0)에 큐 전체 5개 칸을 현재 입력 좌표로
//       한꺼번에 다 덮어쓰는(Pre-fill) 초기화 로직을 두어 딜레이 없이 펜 위치부터 그림이 그려지게 설계했습니다.
//================================================================================
module coord_filter (
    input  logic       pclk,       // 카메라 픽셀 클럭 (프레임 속도와 동기)
    input  logic       valid,      // bbox_center_accum 로부터 새로운 좌표가 들어왔음을 알리는 동기 스트로브
    input  logic [8:0] cx,         // bbox_center_accum 이 찾은 이번 프레임의 원시 X 좌표
    input  logic [8:0] cy,         // bbox_center_accum 이 찾은 이번 프레임의 원시 Y 좌표
    input  logic       pen_in,     // bbox_center_accum 에 의해 검출된 이번 프레임의 펜 상태
    output logic [8:0] ax,         // 최종 평활화(이동평균) 처리가 완료된 X 좌표
    output logic [8:0] ay,         // 최종 평활화(이동평균) 처리가 완료된 Y 좌표
    output logic       pen,        // 지연 시간 보정 처리가 들어간 최종 펜 상태
    output logic       valid_o     // 필터링된 평균 좌표가 준비 완료되었음을 알리는 출력 스트로브 (1클럭)
);
    localparam int N = 5;
    (* ram_style = "registers" *) logic [8:0] bx [0:N-1];  // X 좌표 히스토리용 최근 5개 피포(FIFO) 원형 큐
    (* ram_style = "registers" *) logic [8:0] by [0:N-1];
    logic [2:0]  head = '0;       // 가장 오래된 큐 칸을 가리키는 링 포인터
    logic [11:0] sx = '0, sy = '0;// 5개 픽셀 좌표의 러닝 썸 보관 레지스터 (최대 319*5 = 1595)
    logic        have_hist = 1'b0;// 큐 버퍼 초기화 완료 상태 플래그

    // O(1) 복잡도의 러닝 썸 계산 MUX 식 (새 합 = 이전합 - 오래된값 + 새값)
    wire [11:0] nsx = sx - {3'b0, bx[head]} + {3'b0, cx};
    wire [11:0] nsy = sy - {3'b0, by[head]} + {3'b0, cy};

    // 곱하기 205 연산 시 오버플로를 방지하기 위해 21비트 내부 레지스터 임시 확장 계산
    // 319 * 5 * 205 = 326,975 (최대 19비트 소요)
    wire [20:0] avx = nsx * 21'd205;
    wire [20:0] avy = nsy * 21'd205;

    always_ff @(posedge pclk) begin
        valid_o <= 1'b0;

        if (valid) begin
            valid_o <= 1'b1; // 펜이 화면에서 사라졌을 때도 FSM에 알려주어 펜업(선 끊기) 기회를 주기 위해 매 프레임 스트로브 발생
            
            if (pen_in) begin
                if (!have_hist) begin
                    // [과도응답 방지] 펜이 새로 닿은 첫 번째 프레임: 원형 큐 전체를 현재 점으로 가득 채움
                    for (int i = 0; i < N; i++) begin
                        bx[i] <= cx;
                        by[i] <= cy;
                    end
                    sx <= ({3'b0, cx} << 2) + {3'b0, cx};  // cx * 5 계산 우회
                    sy <= ({3'b0, cy} << 2) + {3'b0, cy};  // cy * 5 계산 우회
                    head <= 3'd0;
                    ax   <= cx;
                    ay   <= cy;
                    have_hist <= 1'b1;
                end else begin
                    // 일반적인 프레임 작동: 원형 큐의 가장 늙은 값을 새 좌표로 갱신
                    bx[head] <= cx;
                    by[head] <= cy;
                    sx <= nsx; 
                    sy <= nsy;
                    
                    // 포인터 회전
                    head <= (head == N-1) ? 3'd0 : head + 3'd1;
                    
                    // 최종 평균 연산 = 합 / 5 (즉, 합 * 205 >> 10)
                    ax <= avx[18:10];
                    ay <= avy[18:10];
                end
                pen <= 1'b1;
            end else begin
                // 펜이 감지되지 않으면 즉시 그리기 펜 중단(Pen Up) 처리 및 큐 유효 플래그 리셋
                pen       <= 1'b0;
                have_hist <= 1'b0;
            end
        end
    end
endmodule
