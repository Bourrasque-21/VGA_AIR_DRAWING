`timescale 1ns / 1ps

module uart_packet_sender #(
    parameter int CLK_FREQ  = 100_000_000,
    parameter int BAUD_RATE = 115_200
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       send_trigger,
    input  logic [8:0] X_center,
    input  logic [8:0] Y_center,
    input  logic       sw_paint_red,
    input  logic       sw_paint_green,
    input  logic       sw_paint_blue,
    input  logic       sw_eraser,
    input  logic       sw_size,
    input  logic       sw_texture_enable,
    input  logic [2:0] texture_shape,
    input  logic       paper,
    input  logic       freeze,
    input  logic       clear_btn,
    output logic       tx,
    output logic       busy
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
    assign busy          = (state != UART_IDLE);

    always_comb begin
        case (byte_index)
            3'd0: tx_data = 8'hAA;
            3'd1: tx_data = x_packet_latched;              // X[8:1], X LSB dropped
            3'd2: tx_data = y_packet_latched;              // Y[7:0], valid for 0..239
            3'd3: tx_data = control_latched;
            3'd4: tx_data = {3'b0, freeze_latched, paper_latched, texture_shape_latched};  // bit4 freeze, bit3 paper
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
            trigger_meta   <= send_trigger;
            trigger_sync   <= trigger_meta;
            trigger_sync_d <= trigger_sync;
            tx_start       <= 1'b0;

            case (state)
                UART_IDLE: begin
                    if (trigger_pulse) begin
                        x_packet_latched <= X_center[8:1];
                        y_packet_latched <= Y_center[7:0];
                        control_latched <= {
                            sw_texture_enable,
                            sw_eraser,
                            sw_size,
                            sw_paint_red,
                            sw_paint_green,
                            sw_paint_blue,
                            clear_btn,
                            1'b0
                        };
                        texture_shape_latched <= texture_shape;
                        paper_latched         <= paper;
                        freeze_latched        <= freeze;
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
        .SYS_CLK  (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) U_BAUD_TICK_16 (
        .clk       (clk),
        .reset     (rst),
        .i_baud_sel(BAUD_SEL),
        .baud_tick (baud_tick)
    );

    uart_tx U_UART_TX (
        .clk     (clk),
        .rst     (rst),
        .b_tick  (baud_tick),
        .tx_start(tx_start),
        .tx_data (tx_data),
        .tx_busy (tx_busy),
        .tx_done (tx_done),
        .uart_tx (tx)
    );
endmodule
