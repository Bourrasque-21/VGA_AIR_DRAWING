import ov7670_pkg::*;

module ov7670_sccb_ctrl (
    input  logic clk,
    input  logic rst,
    input  logic i_tick_25,
    input  logic start_btn,
    output logic scl,
    inout  logic sda
);

    logic       cmd_start;
    logic       cmd_write;
    logic       cmd_read;
    logic       cmd_stop;
    logic [7:0] tx_data;
    logic       ack_in;
    logic       busy;
    logic       done;
    logic       ack_out;
    logic [7:0] rx_data;

    I2C_Master U_I2C_MASTER (
        .clk(clk),
        .rst(rst),
        .i_tick_25(i_tick_25),

        // Command port
        .cmd_start(cmd_start),
        .cmd_write(cmd_write),
        .cmd_read(cmd_read),
        .cmd_stop(cmd_stop),
        .tx_data(tx_data),
        .ack_in(ack_in),

        // Internal output
        .busy(busy),
        .done(done),
        .ack_out(ack_out),
        .rx_data(rx_data),

        // External I2C port
        .scl(scl),
        .sda(sda)
    );

    localparam OV7670_ADDR = 7'h21;

    logic [ 6:0] reg_idx;
    logic [31:0] delay_cnt;
    logic [31:0] delay_target;

    localparam logic [31:0] RESET_DELAY_CYCLES  = 32'd750_000;    // 30 ms at 25 MHz tick
    localparam logic [31:0] REG_DELAY_CYCLES    = 32'd25_000;     // 1 ms at 25 MHz tick
    localparam logic [31:0] BTN_DEBOUNCE_CYCLES = 32'd250_000;    // 10 ms at 25 MHz tick

    logic        start_meta;
    logic        start_sync;
    logic        start_stable;
    logic        start_pulse;
    logic [31:0] start_debounce_cnt;
    logic        init_started;

    assign delay_target = (reg_idx == 0) ? RESET_DELAY_CYCLES : REG_DELAY_CYCLES;
    assign ack_in = 1'b1;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            start_meta         <= 1'b0;
            start_sync         <= 1'b0;
            start_stable       <= 1'b0;
            start_pulse        <= 1'b0;
            start_debounce_cnt <= 32'd0;
        end else begin
            start_meta  <= start_btn;
            start_sync  <= start_meta;
            // The SCCB FSM samples this only on i_tick_25. Hold it until
            // the following tick instead of clearing it at 100 MHz.
            if (i_tick_25) start_pulse <= 1'b0;

            if (i_tick_25 && start_sync == start_stable) begin
                start_debounce_cnt <= 32'd0;
            end else if (i_tick_25 && start_debounce_cnt >= (BTN_DEBOUNCE_CYCLES - 1)) begin
                start_stable       <= start_sync;
                start_debounce_cnt <= 32'd0;
                start_pulse        <= start_sync;
            end else if (i_tick_25) begin
                start_debounce_cnt <= start_debounce_cnt + 1'b1;
            end
        end
    end

    typedef enum logic [2:0] {
        IDLE,
        SEND_DEV_ADDR,
        SEND_REG_ADDR,
        SEND_REG_DATA,
        SEND_STOP,
        WAIT_STOP_DONE,
        DELAY
    } i2c_state_e;

    i2c_state_e state;

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            state     <= IDLE;
            cmd_start <= 1'b0;
            cmd_write <= 1'b0;
            cmd_read  <= 1'b0;
            cmd_stop  <= 1'b0;
            reg_idx   <= 0;
            delay_cnt <= 0;
            init_started <= 1'b0;
        end else if (i_tick_25) begin
            cmd_start <= 1'b0;
            cmd_write <= 1'b0;
            cmd_read  <= 1'b0;
            cmd_stop  <= 1'b0;
            case (state)
                IDLE: begin
                    // 카메라는 리셋 해제 후 자동으로 한 번 초기화한다.
                    // start_btn에 의존하면 전원 재인가 때 영상이 시작되지 않는다.
                    if (!init_started) begin
                        reg_idx   <= 0;
                        cmd_start <= 1'b1;
                        state     <= SEND_DEV_ADDR;
                        init_started <= 1'b1;
                    end
                end
                SEND_DEV_ADDR: begin
                    if (done) begin
                        cmd_write <= 1'b1;
                        tx_data <= {OV7670_ADDR, 1'b0};
                        state <= SEND_REG_ADDR;
                    end
                end
                SEND_REG_ADDR: begin
                    if (done) begin
                        cmd_write <= 1'b1;
                        tx_data <= OV7670_REG_ROM[reg_idx].addr;
                        state <= SEND_REG_DATA;
                    end
                end
                SEND_REG_DATA: begin
                    if (done) begin
                        cmd_write <= 1'b1;
                        tx_data <= OV7670_REG_ROM[reg_idx].data;
                        state <= SEND_STOP;
                    end
                end
                SEND_STOP: begin
                    if (done) begin
                        cmd_stop <= 1'b1;
                        state <= WAIT_STOP_DONE;
                    end
                end
                WAIT_STOP_DONE: begin
                    if (done) begin
                        state <= DELAY;
                        delay_cnt <= 0;
                    end
                end
                DELAY: begin
                    delay_cnt <= delay_cnt + 1;
                    if (delay_cnt >= (delay_target - 1)) begin
                        delay_cnt <= 0;
                        if (reg_idx == TOTAL_REGS - 1) begin
                            state <= IDLE;
                        end else begin
                            reg_idx   <= reg_idx + 1;
                            cmd_start <= 1'b1;
                            state     <= SEND_DEV_ADDR;
                        end
                    end
                end
            endcase
        end
    end
endmodule
