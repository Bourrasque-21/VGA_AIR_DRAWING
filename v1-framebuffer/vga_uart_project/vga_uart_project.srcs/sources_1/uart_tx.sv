`timescale 1ns / 1ps

module uart_tx (
    input  logic       clk,
    input  logic       rst,
    input  logic       b_tick,
    input  logic       tx_start,
    input  logic [7:0] tx_data,
    output logic       tx_busy,
    output logic       tx_done,
    output logic       uart_tx
);

    typedef enum logic [1:0] {
        IDLE,
        START,
        DATA,
        STOP
    } state_t;
    state_t c_state, n_state;

    logic [7:0] data_buf_reg, data_buf_next;
    logic [3:0] b_tick_cnt_reg, b_tick_cnt_next;
    logic [2:0] bit_cnt_reg, bit_cnt_next;
    logic tx_reg, tx_next;
    logic busy_reg, busy_next;
    logic done_reg, done_next;

    assign uart_tx = tx_reg;
    assign tx_busy = busy_reg;
    assign tx_done = done_reg;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            data_buf_reg   <= 8'd0;
            b_tick_cnt_reg <= 4'd0;
            bit_cnt_reg    <= 3'd0;
            tx_reg         <= 1'b1;
            busy_reg       <= 1'b0;
            done_reg       <= 1'b0;
            c_state        <= IDLE;
        end else begin
            data_buf_reg   <= data_buf_next;
            b_tick_cnt_reg <= b_tick_cnt_next;
            bit_cnt_reg    <= bit_cnt_next;
            tx_reg         <= tx_next;
            busy_reg       <= busy_next;
            done_reg       <= done_next;
            c_state        <= n_state;
        end
    end

    always_comb begin
        n_state         = c_state;
        data_buf_next   = data_buf_reg;
        b_tick_cnt_next = b_tick_cnt_reg;
        bit_cnt_next    = bit_cnt_reg;
        tx_next         = tx_reg;
        busy_next       = busy_reg;
        done_next       = done_reg;
        case (c_state)
            IDLE: begin
                tx_next         = 1'b1;
                b_tick_cnt_next = 4'd0;
                bit_cnt_next    = 3'd0;
                busy_next       = 1'b0;
                done_next       = 1'b0;
                if (tx_start) begin
                    n_state       = START;
                    busy_next     = 1'b1;
                    data_buf_next = tx_data;
                end
            end

            START: begin
                tx_next = 1'b0;
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        n_state = DATA;
                        b_tick_cnt_next = 4'd0;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end

            DATA: begin
                tx_next = data_buf_reg[0];
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        b_tick_cnt_next = 4'd0;
                        if (bit_cnt_reg == 7) begin
                            n_state = STOP;
                        end else begin
                            bit_cnt_next = bit_cnt_reg + 1;
                            data_buf_next = {1'b0, data_buf_reg[7:1]};
                            n_state = DATA;
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end

            STOP: begin
                tx_next = 1'b1;
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        done_next = 1'b1;
                        busy_next = 1'b0;
                        b_tick_cnt_next = 4'd0;
                        n_state = IDLE;
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            default: n_state = IDLE;
        endcase
    end
endmodule
