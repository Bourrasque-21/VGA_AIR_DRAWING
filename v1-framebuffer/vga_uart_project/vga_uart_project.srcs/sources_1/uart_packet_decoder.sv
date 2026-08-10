`timescale 1ns / 1ps

// PC(Python UI) -> FPGA 펜 설정 수신 패킷 디코더.
// uart_packet_sender와 대칭 구조로 baud_tick_16 + uart_rx를 내장한다.
//
// 수신 패킷 (4바이트):
//   [0] 0xA5                start byte
//   [1] control             bit[7] texture_enable
//                           bit[6] eraser
//                           bit[5] size
//                           bit[4] paint_red
//                           bit[3] paint_green
//                           bit[2] paint_blue
//                           bit[1] clear 요청
//                           bit[0] reserved, 0
//   [2] shape               bit[2:0] texture_shape (0~4)
//                           bit[3]   paper 모드 (도화지)
//                           bit[4]   freeze (캡처: 배경 프레임버퍼 쓰기 정지)
//   [3] 0x5A                end byte
//
// end byte가 틀리면 패킷 전체를 버리고, 바이트 간 간격이 3바이트 시간을
// 넘으면 프레이밍이 어긋난 것으로 보고 WAIT_START로 복귀한다.
// 모든 출력은 clk(100MHz) 도메인이다. pclk 도메인에서 쓸 때는 2FF 동기화 필요.
module uart_packet_decoder #(
    parameter int CLK_FREQ  = 100_000_000,
    parameter int BAUD_RATE = 115_200
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       rx,

    output logic [2:0] o_pen_color,       // {red, green, blue}
    output logic       o_eraser,
    output logic       o_size,
    output logic       o_texture_enable,
    output logic [2:0] o_texture_shape,
    output logic       o_paper,
    output logic       o_freeze,          // 캡처 모드 (배경 정지)
    output logic       o_clear_pulse,     // 1클럭 펄스
    output logic       o_packet_valid     // 패킷 수신 완료 1클럭 펄스
);
    localparam logic [3:0] BAUD_SEL =
        (BAUD_RATE == 9_600)   ? 4'd0 :
        (BAUD_RATE == 14_400)  ? 4'd1 :
        (BAUD_RATE == 19_200)  ? 4'd2 :
        (BAUD_RATE == 38_400)  ? 4'd3 :
        (BAUD_RATE == 57_600)  ? 4'd4 :
        (BAUD_RATE == 115_200) ? 4'd5 :
        (BAUD_RATE == 230_400) ? 4'd6 :
        (BAUD_RATE == 460_800) ? 4'd7 :
        (BAUD_RATE == 921_600) ? 4'd8 : 4'd5;

    localparam logic [7:0] START_BYTE = 8'hA5;
    localparam logic [7:0] END_BYTE   = 8'h5A;

    // 바이트당 baud_tick 수 = 16틱 x 10비트(start+8data+stop) = 160.
    // 3바이트 시간(480틱) 동안 다음 바이트가 없으면 패킷 폐기.
    localparam int TIMEOUT_TICKS = 480;

    typedef enum logic [1:0] {
        WAIT_START,
        WAIT_CONTROL,
        WAIT_SHAPE,
        WAIT_END
    } decoder_state_t;

    decoder_state_t state;

    logic [7:0] rx_data;
    logic       rx_done;
    logic       baud_tick;

    logic [7:0] control_latched;
    logic [7:0] shape_latched;
    logic [$clog2(TIMEOUT_TICKS)-1:0] timeout_cnt;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state            <= WAIT_START;
            control_latched  <= 8'd0;
            shape_latched    <= 8'd0;
            timeout_cnt      <= '0;
            o_pen_color      <= 3'b000;
            o_eraser         <= 1'b0;
            o_size           <= 1'b0;
            o_texture_enable <= 1'b0;
            o_texture_shape  <= 3'd0;
            o_paper          <= 1'b0;
            o_freeze         <= 1'b0;
            o_clear_pulse    <= 1'b0;
            o_packet_valid   <= 1'b0;
        end else begin
            o_clear_pulse  <= 1'b0;
            o_packet_valid <= 1'b0;

            // 패킷 중간에서 바이트가 끊기면 처음으로 복귀
            if (state == WAIT_START) begin
                timeout_cnt <= '0;
            end else if (rx_done) begin
                timeout_cnt <= '0;
            end else if (baud_tick) begin
                if (timeout_cnt == TIMEOUT_TICKS - 1) begin
                    state       <= WAIT_START;
                    timeout_cnt <= '0;
                end else begin
                    timeout_cnt <= timeout_cnt + 1;
                end
            end

            if (rx_done) begin
                case (state)
                    WAIT_START: begin
                        if (rx_data == START_BYTE) begin
                            state <= WAIT_CONTROL;
                        end
                    end

                    WAIT_CONTROL: begin
                        control_latched <= rx_data;
                        state           <= WAIT_SHAPE;
                    end

                    WAIT_SHAPE: begin
                        shape_latched <= rx_data;
                        state         <= WAIT_END;
                    end

                    WAIT_END: begin
                        state <= WAIT_START;
                        if (rx_data == END_BYTE) begin
                            o_texture_enable <= control_latched[7];
                            o_eraser         <= control_latched[6];
                            o_size           <= control_latched[5];
                            o_pen_color      <= control_latched[4:2];
                            o_clear_pulse    <= control_latched[1];
                            o_texture_shape  <= shape_latched[2:0];
                            o_paper          <= shape_latched[3];
                            o_freeze         <= shape_latched[4];
                            o_packet_valid   <= 1'b1;
                        end
                    end

                    default: state <= WAIT_START;
                endcase
            end
        end
    end

    baud_tick_16 #(
        .SYS_CLK  (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) U_BAUD_TICK_16 (
        .clk       (clk),
        .reset     (rst),
        .i_baud_sel(BAUD_SEL),
        .baud_tick (baud_tick)
    );

    uart_rx U_UART_RX (
        .clk    (clk),
        .rst    (rst),
        .b_tick (baud_tick),
        .rx     (rx),
        .rx_data(rx_data),
        .rx_done(rx_done)
    );
endmodule
