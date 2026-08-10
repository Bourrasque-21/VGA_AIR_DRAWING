module colour_detector (
    input  logic [15:0] wdata,
    output logic        green_detected
);

    logic [5:0] r_6bit;
    logic [5:0] g_6bit;
    logic [5:0] b_6bit;

    always_comb begin
        r_6bit = {wdata[15:11], 1'b0};
        g_6bit = wdata[10:5];
        b_6bit = {wdata[4:0], 1'b0};

        if ((g_6bit >= 6'd36) && 
            ((g_6bit > r_6bit) && (g_6bit - r_6bit >= 6'd16)) && 
            ((g_6bit > b_6bit) && (g_6bit - b_6bit >= 6'd16))) begin
            green_detected = 1'b1;
        end else begin
            green_detected = 1'b0;
        end
    end
endmodule
