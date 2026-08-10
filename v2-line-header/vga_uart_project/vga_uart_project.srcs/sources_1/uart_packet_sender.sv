module uart_packet_sender #(
    parameter int CLK_FREQ  = 100_000_000,
    parameter int BAUD_RATE = 115_200
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       i_send_trigger,
    input  logic [8:0] i_x_center,
    input  logic [8:0] i_y_center,
    input  logic       i_paint_red,
    input  logic       i_paint_green,
    input  logic       i_paint_blue,
    input  logic       i_eraser,
    input  logic       i_size,
    input  logic       i_texture_enable,
    input  logic [2:0] i_texture_shape,
    input  logic       i_paper,
    input  logic       i_freeze,
    input  logic       i_clear,
    output logic       o_tx,
    output logic       o_busy
);
    localparam int PACKET_LEN = 6;

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

    typedef enum logic [1:0] {
        UART_IDLE,
        UART_START_BYTE,
        UART_WAIT_BYTE
    } uart_sender_state_t;

    uart_sender_state_t state;

    logic trigger_meta;
    logic trigger_sync;
    logic trigger_sync_d;
    logic trigger_pulse;

    logic [7:0] x_packet_latched;
    logic [7:0] y_packet_latched;
    logic [7:0] control_latched;
    logic [2:0] texture_shape_latched;
    logic       paper_latched;
    logic       freeze_latched;

    logic [2:0] byte_index;
    logic [7:0] tx_data;
    logic       tx_start;
    logic       tx_busy;
    logic       tx_done;
    logic       baud_tick;

    assign trigger_pulse = trigger_sync & ~trigger_sync_d;
    assign o_busy          = (state != UART_IDLE);

    always_comb begin
        case (byte_index)
            3'd0: tx_data = 8'hAA;
            3'd1: tx_data = x_packet_latched;              // X[8:1], X LSB dropped
            3'd2: tx_data = y_packet_latched;              // Y[7:0], valid for 0..239
            3'd3: tx_data = control_latched;
            3'd4: tx_data = {3'b0, freeze_latched, paper_latched,
                             texture_shape_latched};
            3'd5: tx_data = 8'h55;
            default: tx_data = 8'h55;
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            trigger_meta          <= 1'b0;
            trigger_sync          <= 1'b0;
            trigger_sync_d        <= 1'b0;
            state                 <= UART_IDLE;
            x_packet_latched      <= 8'd0;
            y_packet_latched      <= 8'd0;
            control_latched       <= 8'd0;
            texture_shape_latched <= 3'd0;
            paper_latched         <= 1'b0;
            freeze_latched        <= 1'b0;
            byte_index            <= 3'd0;
            tx_start              <= 1'b0;
        end else begin
            trigger_meta   <= i_send_trigger;
            trigger_sync   <= trigger_meta;
            trigger_sync_d <= trigger_sync;
            tx_start       <= 1'b0;

            case (state)
                UART_IDLE: begin
                    if (trigger_pulse) begin
                        x_packet_latched <= i_x_center[8:1];
                        y_packet_latched <= i_y_center[7:0];
                        control_latched <= {
                            i_texture_enable,
                            i_eraser,
                            i_size,
                            i_paint_red,
                            i_paint_green,
                            i_paint_blue,
                            i_clear,
                            1'b0
                        };
                        texture_shape_latched <= i_texture_shape;
                        paper_latched         <= i_paper;
                        freeze_latched        <= i_freeze;
                        byte_index            <= 3'd0;
                        state                 <= UART_START_BYTE;
                    end
                end

                UART_START_BYTE: begin
                    if (!tx_busy) begin
                        tx_start <= 1'b1;
                        state    <= UART_WAIT_BYTE;
                    end
                end

                UART_WAIT_BYTE: begin
                    if (tx_done) begin
                        if (byte_index == PACKET_LEN - 1) begin
                            state <= UART_IDLE;
                        end else begin
                            byte_index <= byte_index + 3'd1;
                            state      <= UART_START_BYTE;
                        end
                    end
                end

                default: state <= UART_IDLE;
            endcase
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

    uart_tx U_UART_TX (
        .clk         (clk),
        .rst         (rst),
        .i_baud_tick (baud_tick),
        .i_start     (tx_start),
        .i_data      (tx_data),
        .o_busy      (tx_busy),
        .o_done      (tx_done),
        .o_tx        (o_tx)
    );
endmodule
