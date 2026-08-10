`timescale 1ns / 1ps
module baud_tick_16 #(
    parameter integer SYS_CLK   = 100_000_000,
    parameter integer BAUD_RATE = 9600
)(
    input  wire clk,
    input  wire reset,
    input  wire [3:0] i_baud_sel,
    output reg  baud_tick
);

    localparam integer OVERSAMPLE = 16;
    localparam integer ACC_WIDTH  = 24;

    reg [ACC_WIDTH-1:0] phase_acc;
    reg [ACC_WIDTH-1:0] phase_inc;
    wire [ACC_WIDTH:0] phase_sum;

    function automatic [ACC_WIDTH-1:0] calc_phase_inc;
        input integer baud_rate;
        reg   [63:0] target_tick_hz;
        reg   [63:0] phase_inc_full;
        begin
            target_tick_hz = baud_rate * OVERSAMPLE;
            phase_inc_full = ((target_tick_hz << ACC_WIDTH) + (SYS_CLK / 2)) / SYS_CLK;
            if (phase_inc_full == 0) begin
                calc_phase_inc = {{(ACC_WIDTH-1){1'b0}}, 1'b1};
            end else begin
                calc_phase_inc = phase_inc_full[ACC_WIDTH-1:0];
            end
        end
    endfunction

    always @(*) begin
        case (i_baud_sel)
            4'd0:    phase_inc = calc_phase_inc(9600);
            4'd1:    phase_inc = calc_phase_inc(14400);
            4'd2:    phase_inc = calc_phase_inc(19200);
            4'd3:    phase_inc = calc_phase_inc(38400);
            4'd4:    phase_inc = calc_phase_inc(57600);
            4'd5:    phase_inc = calc_phase_inc(115200);
            4'd6:    phase_inc = calc_phase_inc(230400);
            4'd7:    phase_inc = calc_phase_inc(460800);
            4'd8:    phase_inc = calc_phase_inc(921600);
            default: phase_inc = calc_phase_inc(9600);
        endcase
    end

    assign phase_sum = {1'b0, phase_acc} + {1'b0, phase_inc};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            phase_acc <= {ACC_WIDTH{1'b0}};
            baud_tick <= 1'b0;
        end else begin
            phase_acc <= phase_sum[ACC_WIDTH-1:0];
            baud_tick <= phase_sum[ACC_WIDTH];
        end
    end

endmodule
