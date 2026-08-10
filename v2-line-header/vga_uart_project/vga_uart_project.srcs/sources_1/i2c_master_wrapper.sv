module I2C_Master (
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
    inout  logic       io_sda
);
    logic sda_o;
    logic sda_i;

    assign sda_i  = io_sda;
    assign io_sda = sda_o ? 1'bz : 1'b0;

    i2c_master U_I2C_MASTER (
        .clk         (clk),
        .rst         (rst),
        .i_tick_25   (i_tick_25),
        .i_cmd_start (i_cmd_start),
        .i_cmd_write (i_cmd_write),
        .i_cmd_read  (i_cmd_read),
        .i_cmd_stop  (i_cmd_stop),
        .i_tx_data   (i_tx_data),
        .i_ack_in    (i_ack_in),
        .o_busy      (o_busy),
        .o_done      (o_done),
        .o_ack_out   (o_ack_out),
        .o_rx_data   (o_rx_data),
        .o_scl       (o_scl),
        .o_sda       (sda_o),
        .i_sda       (sda_i)
    );
endmodule
