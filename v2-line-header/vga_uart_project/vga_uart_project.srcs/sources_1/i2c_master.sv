module i2c_master (
    input  logic       clk,
    input  logic       rst,
    input  logic       i_tick_25,
    input  logic       i_cmd_start,
    input  logic       i_cmd_write,
    input  logic       i_cmd_read,
    input  logic       i_cmd_stop,
    input  logic [7:0] i_tx_data,
    input  logic       i_ack_in,
    output logic       o_busy,
    output logic       o_done,
    output logic       o_ack_out,
    output logic [7:0] o_rx_data,
    output logic       o_scl,
    output logic       o_sda,
    input  logic       i_sda
);

    typedef enum logic [2:0] {
        IDLE,
        START,
        WAIT_CMD,
        DATA,
        DATA_ACK,
        STOP
    } i2c_state_e;
    i2c_state_e state;

    // Internal SCL/SDA control registers
    logic scl_r, sda_r;  // sda_r: 1 = release 'Z', 0 = drive low

    logic [7:0] div_cnt;
    logic       qtr_tick;

    logic [1:0] step;
    logic [7:0] tx_shift_reg, rx_shift_reg;
    logic [2:0] bit_cnt;
    logic is_read, ack_in_r;  //  ack_in_r: latched ACK/NACK to send after read byte

    assign o_scl   = scl_r;
    assign o_sda = sda_r;
    assign o_busy  = (state != IDLE);

    // Quarter-tick generator for approximately 100 kHz I2C SCL.
    // The state machine advances on the 25 MHz clock-enable tick.
    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            div_cnt  <= 0;
            qtr_tick <= 0;
        end else if (i_tick_25) begin
            if (div_cnt == 63 - 1) begin
                div_cnt  <= 0;
                qtr_tick <= 1'b1;
            end else begin
                qtr_tick <= 1'b0;
                div_cnt  <= div_cnt + 1;
            end
        end
    end

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            state        <= IDLE;
            scl_r        <= 1'b1;
            sda_r        <= 1'b1;
            step         <= 1'b0;
            o_done         <= 1'b0;
            tx_shift_reg <= 8'h0;
            rx_shift_reg <= 8'h0;
            bit_cnt      <= 3'b0;
            o_ack_out      <= 1'b0;
            o_rx_data      <= 8'd0;
            is_read      <= 1'b0;
            ack_in_r     <= 1'b0;
        end else if (i_tick_25) begin
            o_done <= 1'b0;
            case (state)
                IDLE: begin
                    scl_r <= 1'b1;
                    sda_r <= 1'b1;
                    if (i_cmd_start) begin
                        state <= START;
                        step  <= 1'b0;
                    end
                end

                START: begin
                    if (qtr_tick) begin
                        case (step)
                            2'd0: begin
                                scl_r <= 1'b1;
                                sda_r <= 1'b1;
                                step  <= 2'd1;
                            end

                            2'd1: begin
                                sda_r <= 1'b0;
                                step  <= 2'd2;
                            end

                            2'd2: begin
                                step <= 2'd3;
                            end

                            2'd3: begin
                                scl_r <= 1'b0;
                                step  <= 2'd0;
                                o_done  <= 1'b1;
                                state <= WAIT_CMD;
                            end
                        endcase
                    end
                end

                WAIT_CMD: begin
                    step <= 0;
                    if (i_cmd_write) begin
                        tx_shift_reg <= i_tx_data;
                        bit_cnt      <= 3'd0;
                        is_read      <= 1'b0;
                        state        <= DATA;
                    end else if (i_cmd_read) begin
                        rx_shift_reg <= 0;
                        bit_cnt      <= 0;
                        is_read      <= 1'b1;
                        ack_in_r     <= i_ack_in;  // Latch read response
                        state        <= DATA;
                    end else if (i_cmd_stop) begin
                        state <= STOP;
                    end else if (i_cmd_start) begin
                        state <= START;
                    end
                end

                DATA: begin
                    if (qtr_tick) begin
                        case (step)
                            2'd0: begin
                                scl_r <= 1'b0;
                                // Read = SDA release 'Z', Write = transmit current bit
                                sda_r <= is_read ? 1'b1 : tx_shift_reg[7];
                                step  <= 2'd1;
                            end

                            2'd1: begin
                                scl_r <= 1'b1;
                                step  <= 2'd2;
                            end

                            2'd2: begin
                                scl_r <= 1'b1;
                                if (is_read) begin
                                    rx_shift_reg <= {rx_shift_reg[6:0], i_sda};
                                end
                                step <= 2'd3;
                            end

                            2'd3: begin
                                scl_r <= 1'b0;
                                if (!is_read) begin
                                    // Shift TX data
                                    tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                                end
                                step <= 2'd0;
                                if (bit_cnt == 7) begin
                                    state <= DATA_ACK;
                                end else begin
                                    bit_cnt <= bit_cnt + 1'b1;
                                end
                            end
                        endcase
                    end
                end

                DATA_ACK: begin
                    if (qtr_tick) begin
                        case (step)
                            2'd0: begin
                                scl_r <= 1'b0;
                                if (is_read) begin
                                    sda_r <= ack_in_r;  // Read: send ACK(0) or NACK(1) to slave
                                end else begin
                                    sda_r <= 1'b1;  //  Write: release SDA 'Z' so slave can drive ACK/NACK
                                end
                                step <= 2'd1;
                            end

                            2'd1: begin
                                scl_r <= 1'b1;
                                step  <= 2'd2;
                            end

                            2'd2: begin
                                scl_r <= 1'b1;
                                if (!is_read) begin  //  Write: receive ACK/NACK from slave
                                    o_ack_out <= i_sda;  // Sample slave response (0: ACK, 1: NACK)
                                end
                                if (is_read) begin
                                    o_rx_data <= rx_shift_reg;
                                end
                                step <= 2'd3;
                            end

                            2'd3: begin
                                scl_r <= 1'b0;
                                o_done  <= 1'b1;
                                step  <= 2'd0;
                                state <= WAIT_CMD;
                            end
                        endcase
                    end
                end

                STOP: begin
                    if (qtr_tick) begin
                        case (step)
                            2'd0: begin
                                scl_r <= 1'b0;
                                sda_r <= 1'b0;
                                step  <= 2'd1;
                            end
                            2'd1: begin
                                scl_r <= 1'b1;
                                step  <= 2'd2;
                            end
                            2'd2: begin
                                sda_r <= 1'b1;
                                step  <= 2'd3;
                            end
                            2'd3: begin
                                step  <= 2'd0;
                                o_done  <= 1'b1;
                                state <= IDLE;
                            end
                            default: begin
                                state <= IDLE;
                            end
                        endcase
                    end
                end
            endcase
        end
    end

endmodule
