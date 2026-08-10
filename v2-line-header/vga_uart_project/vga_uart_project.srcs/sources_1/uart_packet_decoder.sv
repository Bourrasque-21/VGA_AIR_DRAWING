module uart_packet_decoder #(
    parameter int CLK_FREQ  = 100_000_000,
    parameter int BAUD_RATE = 115_200
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       i_rx,
    output logic [2:0] o_pen_color,
    output logic       o_eraser,
    output logic       o_size,
    output logic       o_texture_enable,
    output logic [2:0] o_texture_shape,
    output logic       o_paper,
    output logic       o_freeze,
    output logic       o_clear_pulse,
    output logic       o_packet_valid
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
        .SYS_CLK   (CLK_FREQ),
        .BAUD_RATE (BAUD_RATE)
    ) U_BAUD_TICK_16 (
        .clk         (clk),
        .rst         (rst),
        .i_baud_sel  (BAUD_SEL),
        .o_baud_tick (baud_tick)
    );

    uart_rx U_UART_RX (
        .clk         (clk),
        .rst         (rst),
        .i_baud_tick (baud_tick),
        .i_rx        (i_rx),
        .o_rx_data   (rx_data),
        .o_rx_done   (rx_done)
    );
endmodule
