module top_button (
    input  logic clk,
    input  logic rst,
    input  logic i_pen_mode,
    input  logic i_pen_size,
    input  logic i_eraser,
    output logic o_pen_mode_pulse,
    output logic o_pen_size_pulse,
    output logic o_eraser_pulse
);
    button_debounce U_MODE_DEBOUNCE (
        .clk     (clk),
        .rst     (rst),
        .i_btn   (i_pen_mode),
        .o_pulse (o_pen_mode_pulse)
    );

    button_debounce U_SIZE_DEBOUNCE (
        .clk     (clk),
        .rst     (rst),
        .i_btn   (i_pen_size),
        .o_pulse (o_pen_size_pulse)
    );

    button_debounce U_ERASER_DEBOUNCE (
        .clk     (clk),
        .rst     (rst),
        .i_btn   (i_eraser),
        .o_pulse (o_eraser_pulse)
    );
endmodule
