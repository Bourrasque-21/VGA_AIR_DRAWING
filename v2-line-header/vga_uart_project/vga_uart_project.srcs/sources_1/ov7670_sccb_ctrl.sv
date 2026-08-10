import ov7670_pkg::*;

module ov7670_sccb_ctrl (
    input  logic clk,
    input  logic rst,
    input  logic i_tick_25,
    input  logic i_start_btn,
    input  logic i_camera_vsync,
    output logic o_init_done,
    output logic o_scl,
    inout  logic io_sda
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
        .clk         (clk),
        .rst         (rst),
        .i_tick_25   (i_tick_25),
        .i_cmd_start (cmd_start),
        .i_cmd_write (cmd_write),
        .i_cmd_read  (cmd_read),
        .i_cmd_stop  (cmd_stop),
        .i_tx_data   (tx_data),
        .i_ack_in    (ack_in),
        .o_busy      (busy),
        .o_done      (done),
        .o_ack_out   (ack_out),
        .o_rx_data   (rx_data),
        .o_scl       (o_scl),
        .io_sda      (io_sda)
    );

    localparam OV7670_ADDR = 7'h21;

    logic [ 6:0] reg_idx;
    logic [31:0] delay_cnt;
    logic [31:0] delay_target;

    localparam logic [31:0] STARTUP_DELAY_CYCLES = 32'd750_000;   // 30 ms for XCLK/PLL to settle
    localparam logic [31:0] RESET_DELAY_CYCLES   = 32'd750_000;   // 30 ms after COM7 reset
    localparam logic [31:0] REG_DELAY_CYCLES     = 32'd25_000;    // 1 ms between registers
    localparam logic [31:0] BTN_DEBOUNCE_CYCLES = 32'd250_000;    // 10 ms at 25 MHz tick
    localparam logic [31:0] MANUAL_ALIGN_TIMEOUT_CYCLES = 32'd2_500_000; // 100 ms

    logic        start_meta;
    logic        start_sync;
    logic        start_stable;
    logic        start_pulse;
    logic [31:0] start_debounce_cnt;
    logic        init_started;
    logic        manual_pending;
    logic [31:0] manual_wait_cnt;
    logic [31:0] startup_cnt;
    (* ASYNC_REG = "TRUE" *) logic camera_vsync_meta;
    (* ASYNC_REG = "TRUE" *) logic camera_vsync_sync;
    logic camera_vsync_prev;

    assign delay_target = (reg_idx == 0) ? RESET_DELAY_CYCLES : REG_DELAY_CYCLES;
    assign ack_in = 1'b1;

    // The camera VSYNC originates in the PCLK domain.  Manual COM7 reset is
    // deferred until vertical blanking so btnC can never cut an active row.
    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            camera_vsync_meta <= 1'b0;
            camera_vsync_sync <= 1'b0;
        end else begin
            camera_vsync_meta <= i_camera_vsync;
            camera_vsync_sync <= camera_vsync_meta;
        end
    end

    always_ff @(posedge clk, posedge rst) begin
        if (rst) begin
            start_meta         <= 1'b0;
            start_sync         <= 1'b0;
            start_stable       <= 1'b0;
            start_pulse        <= 1'b0;
            start_debounce_cnt <= 32'd0;
        end else begin
            start_meta  <= i_start_btn;
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
            manual_pending <= 1'b0;
            manual_wait_cnt <= 32'd0;
            startup_cnt <= 32'd0;
            camera_vsync_prev <= 1'b0;
            o_init_done <= 1'b0;
        end else if (i_tick_25) begin
            cmd_start <= 1'b0;
            cmd_write <= 1'b0;
            cmd_read  <= 1'b0;
            cmd_stop  <= 1'b0;
            camera_vsync_prev <= camera_vsync_sync;
            if (start_pulse)
                manual_pending <= 1'b1;
            case (state)
                IDLE: begin
                    // 카메라는 리셋 해제 후 자동으로 한 번 초기화한다.
                    // start_btn에 의존하면 전원 재인가 때 영상이 시작되지 않는다.
                    if (!init_started) begin
                        manual_wait_cnt <= 32'd0;
                        // At power-up the camera XCLK MMCM is released shortly
                        // before this controller.  Wait before sending COM7
                        // reset and the native-VGA register table.
                        if (startup_cnt >= (STARTUP_DELAY_CYCLES - 1)) begin
                            startup_cnt <= 32'd0;
                            reg_idx   <= 0;
                            cmd_start <= 1'b1;
                            state     <= SEND_DEV_ADDR;
                            init_started <= 1'b1;
                            o_init_done <= 1'b0;
                        end else begin
                            startup_cnt <= startup_cnt + 1'b1;
                        end
                    end else if (manual_pending) begin
                        // Prefer a fresh VSYNC rising edge so COM7 never cuts
                        // an active row.  If a broken camera has no VSYNC,
                        // force service after 100 ms so btnC can still recover.
                        if ((camera_vsync_sync && !camera_vsync_prev) ||
                            (manual_wait_cnt >= (MANUAL_ALIGN_TIMEOUT_CYCLES - 1))) begin
                            reg_idx         <= 0;
                            cmd_start       <= 1'b1;
                            state           <= SEND_DEV_ADDR;
                            manual_pending  <= 1'b0;
                            manual_wait_cnt <= 32'd0;
                            o_init_done       <= 1'b0;
                        end else begin
                            manual_wait_cnt <= manual_wait_cnt + 1'b1;
                        end
                    end else begin
                        manual_wait_cnt <= 32'd0;
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
                            // A request received while busy remains pending in
                            // IDLE until the next vertical blanking interval.
                            state <= IDLE;
                            // SCCB phase-3 is a don't-care bit on some OV7670
                            // modules; completion means the final STOP ran.
                            o_init_done <= 1'b1;
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
