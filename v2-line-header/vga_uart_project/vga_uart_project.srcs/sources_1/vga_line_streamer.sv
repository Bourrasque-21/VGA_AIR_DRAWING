module vga_line_streamer (
    input  logic        clk,
    input  logic        rst,
    input  logic        i_tick,
    input  logic        i_de,
    input  logic [9:0]  i_x,
    input  logic [9:0]  i_y,
    input  logic        i_empty,
    input  logic [6:0]  i_count,
    input  logic [5:0]  i_next_bank,
    input  logic [7:0]  i_next_frame,
    input  logic [8:0]  i_next_y,
    output logic        o_pop,
    output logic [5:0]  o_bank,
    output logic [9:0]  o_source_x,
    output logic        o_pixel_good,
    output logic        o_line_valid,
    output logic [7:0]  o_line_frame,
    output logic [8:0]  o_line_y
);
    localparam logic [6:0] PREBUFFER_LINES = 7'd24;
    localparam logic [6:0] LOW_WATER_LINES = 7'd8;

    logic running, held;
    logic [5:0] bank;
    logic [8:0] line_y;
    logic [7:0] line_frame;

    assign o_bank = bank;
    assign o_source_x = (i_x < 640) ? i_x : 10'd0;
    assign o_pixel_good = held && i_de && (i_x < 640) && (i_y < 480);
    assign o_line_valid = held;
    assign o_line_frame = line_frame;
    assign o_line_y = line_y;

    always_ff @(posedge clk) begin
        if (rst) begin
            running <= 1'b0;
            held <= 1'b0;
            o_pop <= 1'b0;
            bank <= 6'd0;
            line_y <= 9'd0;
            line_frame <= 8'd0;
        end else begin
            o_pop <= 1'b0;
            if (i_tick) begin
                // Finish after the second row.  At low water retain this line
                // for one more slot rather than reading an unwritten bank.
                if (held && (i_x == 10'd639) && (i_y < 480) && i_y[0]) begin
                    if (i_count > LOW_WATER_LINES) begin
                        o_pop <= 1'b1;
                        held <= 1'b0;
                    end
                end

                // Load in horizontal blank immediately before the next even
                // visible row.  Row 520 precedes row zero in the 521-line mode.
                if ((i_x == 10'd799) &&
                    (((i_y < 10'd479) && i_y[0]) || (i_y == 10'd520))) begin
                    if (!running) begin
                        if (!i_empty && (i_count >= PREBUFFER_LINES)) begin
                            running <= 1'b1;
                            held <= 1'b1;
                            bank <= i_next_bank;
                            line_y <= i_next_y;
                            line_frame <= i_next_frame;
                        end
                    end else if (!held) begin
                        if (!i_empty) begin
                            held <= 1'b1;
                            bank <= i_next_bank;
                            line_y <= i_next_y;
                            line_frame <= i_next_frame;
                        end else begin
                            running <= 1'b0;
                        end
                    end
                end
            end
        end
    end
endmodule
