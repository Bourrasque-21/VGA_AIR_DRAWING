module coord_filter (
    input  logic       i_pclk,
    input  logic       i_valid,
    input  logic [8:0] i_cx,
    input  logic [8:0] i_cy,
    input  logic       i_pen,
    output logic [8:0] o_x,
    output logic [8:0] o_y,
    output logic       o_pen,
    output logic       o_valid
);
    localparam int N = 5;
    (* ram_style = "registers" *) logic [8:0] bx [0:N-1];  // X 좌표 히스토리용 최근 5개 피포(FIFO) 원형 큐
    (* ram_style = "registers" *) logic [8:0] by [0:N-1];
    logic [2:0]  head = '0;       // 가장 오래된 큐 칸을 가리키는 링 포인터
    logic [11:0] sx = '0, sy = '0;// 5개 픽셀 좌표의 러닝 썸 보관 레지스터 (최대 319*5 = 1595)
    logic        have_hist = 1'b0;// 큐 버퍼 초기화 완료 상태 플래그

    // O(1) 복잡도의 러닝 썸 계산 MUX 식 (새 합 = 이전합 - 오래된값 + 새값)
    wire [11:0] nsx = sx - {3'b0, bx[head]} + {3'b0, i_cx};
    wire [11:0] nsy = sy - {3'b0, by[head]} + {3'b0, i_cy};

    // 곱하기 205 연산 시 오버플로를 방지하기 위해 21비트 내부 레지스터 임시 확장 계산
    // 319 * 5 * 205 = 326,975 (최대 19비트 소요)
    wire [20:0] avx = nsx * 21'd205;
    wire [20:0] avy = nsy * 21'd205;

    always_ff @(posedge i_pclk) begin
        o_valid <= 1'b0;

        if (i_valid) begin
            o_valid <= 1'b1; // 펜이 화면에서 사라졌을 때도 FSM에 알려주어 펜업(선 끊기) 기회를 주기 위해 매 프레임 스트로브 발생
            
            if (i_pen) begin
                if (!have_hist) begin
                    // [과도응답 방지] 펜이 새로 닿은 첫 번째 프레임: 원형 큐 전체를 현재 점으로 가득 채움
                    for (int i = 0; i < N; i++) begin
                        bx[i] <= i_cx;
                        by[i] <= i_cy;
                    end
                    sx <= ({3'b0, i_cx} << 2) + {3'b0, i_cx};  // i_cx * 5 계산 우회
                    sy <= ({3'b0, i_cy} << 2) + {3'b0, i_cy};  // i_cy * 5 계산 우회
                    head <= 3'd0;
                    o_x   <= i_cx;
                    o_y   <= i_cy;
                    have_hist <= 1'b1;
                end else begin
                    // 일반적인 프레임 작동: 원형 큐의 가장 늙은 값을 새 좌표로 갱신
                    bx[head] <= i_cx;
                    by[head] <= i_cy;
                    sx <= nsx; 
                    sy <= nsy;
                    
                    // 포인터 회전
                    head <= (head == N-1) ? 3'd0 : head + 3'd1;
                    
                    // 최종 평균 연산 = 합 / 5 (즉, 합 * 205 >> 10)
                    o_x <= avx[18:10];
                    o_y <= avy[18:10];
                end
                o_pen <= 1'b1;
            end else begin
                // 펜이 감지되지 않으면 즉시 그리기 펜 중단(Pen Up) 처리 및 큐 유효 플래그 리셋
                o_pen       <= 1'b0;
                have_hist <= 1'b0;
            end
        end
    end
endmodule
