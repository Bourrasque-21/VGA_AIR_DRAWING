`timescale 1ns / 1ps

module uart_rx (
    input  logic       clk,
    input  logic       rst,
    input  logic       b_tick,
    input  logic       rx,
    output logic [7:0] rx_data,
    output logic       rx_done
);

    typedef enum logic [1:0] {
        IDLE,
        START,
        DATA,
        STOP
    } state_t;
    state_t c_state, n_state;

    logic rx_sync1, rx_sync2;
    logic [3:0] b_tick_cnt_reg, b_tick_cnt_next;
    logic [2:0] bit_cnt_reg, bit_cnt_next;
    logic [7:0] data_buf_reg, data_buf_next;
    logic done_reg, done_next;

    assign rx_data = data_buf_reg;
    assign rx_done = done_reg;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            c_state        <= IDLE;
            b_tick_cnt_reg <= 4'd0;
            bit_cnt_reg    <= 3'd0;
            done_reg       <= 1'b0;
            data_buf_reg   <= 8'd0;
            // 2FF Synchronizer
            rx_sync1       <= 1'b1;
            rx_sync2       <= 1'b1;
        end else begin
            c_state        <= n_state;
            b_tick_cnt_reg <= b_tick_cnt_next;
            bit_cnt_reg    <= bit_cnt_next;
            done_reg       <= done_next;
            data_buf_reg   <= data_buf_next;
            
            rx_sync1       <= rx;
            rx_sync2       <= rx_sync1;
        end
    end

    always_comb begin
        n_state         = c_state;
        b_tick_cnt_next = b_tick_cnt_reg;
        bit_cnt_next    = bit_cnt_reg;
        done_next       = done_reg;
        data_buf_next   = data_buf_reg;
        case (c_state)
            IDLE: begin
                b_tick_cnt_next = 4'd0;
                bit_cnt_next    = 3'd0;
                done_next       = 1'b0;
                if (b_tick & !rx_sync2) begin
                    data_buf_next = 8'd0;
                    n_state = START;
                end
            end

            START: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 7) begin
                        b_tick_cnt_next = 4'd0;
                        if (!rx_sync2) begin
                            n_state = DATA;
                        end else begin
                            n_state = IDLE;
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end

            DATA: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 4'd15) begin
                        b_tick_cnt_next = 4'd0;
                        data_buf_next   = {rx_sync2, data_buf_reg[7:1]};
                        if (bit_cnt_reg == 3'd7) begin
                            n_state = STOP;
                        end else begin
                            bit_cnt_next = bit_cnt_reg + 1;
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end

            STOP: begin
                if (b_tick) begin
                    if (b_tick_cnt_reg == 15) begin
                        b_tick_cnt_next = 4'd0;
                        n_state = IDLE;
                        if (rx_sync2) begin
                            done_next = 1'b1;
                        end
                    end else begin
                        b_tick_cnt_next = b_tick_cnt_reg + 1;
                    end
                end
            end
            default: n_state = IDLE;
        endcase
    end

endmodule
