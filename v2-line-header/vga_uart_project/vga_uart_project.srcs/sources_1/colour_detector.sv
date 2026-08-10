module colour_detector #(
    parameter logic [5:0] MIN_GREEN  = 6'd16,
    parameter logic [5:0] MIN_EXCESS = 6'd8
) (
    input  logic [15:0] i_wdata,
    output logic        o_green_detected
);
    logic [5:0] red;
    logic [5:0] green;
    logic [5:0] blue;
    logic [5:0] other_max;
    logic [5:0] green_excess;

    always_comb begin
        red          = {i_wdata[15:11], 1'b0};
        green        = i_wdata[10:5];
        blue         = {i_wdata[4:0], 1'b0};
        other_max    = (red > blue) ? red : blue;
        green_excess = (green > other_max) ? green - other_max : 6'd0;

        o_green_detected = (green >= MIN_GREEN) && (green_excess > MIN_EXCESS);
    end
endmodule
