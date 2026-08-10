module centroid_accum #(
    parameter int PEN_MIN = 15,
    parameter int PEN_MAX = 1200,
    parameter bit ERODE   = 1'b1,
    parameter logic [8:0] GATE_RADIUS = 9'd48,
    parameter logic [2:0] LOST_FRAMES = 3'd3
) (
    input  logic       i_pclk,
    input  logic       i_vsync,
    input  logic       i_we,
    input  logic       i_hit,
    output logic [8:0] o_cx,
    output logic [8:0] o_cy,
    output logic       o_pen,
    output logic       o_valid
);
    localparam int SUM_W = 25;

    logic [8:0] x = '0, y = '0;
    logic [16:0] cnt = '0;
    logic [SUM_W-1:0] sum_x = '0, sum_y = '0;
    logic vsync_d = 1'b0, hit_d1 = 1'b0, hit_d2 = 1'b0;
    logic div_busy = 1'b0;
    logic [4:0] div_bit = '0;
    logic [16:0] div_den = '0;
    logic [SUM_W-1:0] div_x = '0, div_y = '0;
    logic [SUM_W:0] rem_x = '0, rem_y = '0;
    logic [8:0] quo_x = '0, quo_y = '0;
    logic [SUM_W:0] trial_x, trial_y;
    logic take_x, take_y;
    logic tracking = 1'b0;
    logic [8:0] track_x = '0, track_y = '0;
    logic [8:0] gate_x = '0, gate_y = '0;
    logic [8:0] gate_radius_x = GATE_RADIUS, gate_radius_y = GATE_RADIUS;
    logic [2:0] lost_count = '0;

    wire vs_rise = i_vsync & ~vsync_d;
    wire line_end = (x == 9'd319);
    wire eff_hit = ERODE ? (i_hit & hit_d1 & hit_d2) : i_hit;
    wire [8:0] eff_x = ERODE ? (x - 9'd1) : x;
    wire [8:0] dx = (eff_x >= gate_x) ? eff_x - gate_x : gate_x - eff_x;
    wire [8:0] dy = (y >= gate_y) ? y - gate_y : gate_y - y;
    wire gate_hit = eff_hit && (!tracking || ((dx <= gate_radius_x) && (dy <= gate_radius_y)));
    wire marker_valid = (cnt >= PEN_MIN) && (cnt <= PEN_MAX);

    always_comb begin
        trial_x = {rem_x[SUM_W-1:0], div_x[SUM_W-1]};
        trial_y = {rem_y[SUM_W-1:0], div_y[SUM_W-1]};
        take_x = (trial_x >= {{(SUM_W+1-17){1'b0}}, div_den});
        take_y = (trial_y >= {{(SUM_W+1-17){1'b0}}, div_den});
    end

    always_ff @(posedge i_pclk) begin
        vsync_d <= i_vsync;
        o_valid <= 1'b0;
        if (div_busy) begin
            div_x <= {div_x[SUM_W-2:0], 1'b0};
            div_y <= {div_y[SUM_W-2:0], 1'b0};
            rem_x <= take_x ? trial_x - {{(SUM_W+1-17){1'b0}}, div_den} : trial_x;
            rem_y <= take_y ? trial_y - {{(SUM_W+1-17){1'b0}}, div_den} : trial_y;
            quo_x <= {quo_x[7:0], take_x};
            quo_y <= {quo_y[7:0], take_y};
            if (div_bit == SUM_W-1) begin
                o_cx <= {quo_x[7:0], take_x};
                o_cy <= {quo_y[7:0], take_y};
                gate_radius_x <= GATE_RADIUS;
                gate_radius_y <= GATE_RADIUS;
                gate_x <= {quo_x[7:0], take_x};
                gate_y <= {quo_y[7:0], take_y};
                track_x <= {quo_x[7:0], take_x};
                track_y <= {quo_y[7:0], take_y};
                tracking <= 1'b1;
                lost_count <= '0;
                div_busy <= 1'b0;
                o_valid <= 1'b1;
            end else div_bit <= div_bit + 1'b1;
        end

        if (i_vsync) begin
            if (vs_rise) begin
                o_pen <= marker_valid || (tracking && (lost_count == 3'd0));
                if (marker_valid) begin
                    div_busy <= 1'b1;
                    div_bit <= '0;
                    div_den <= cnt;
                    div_x <= sum_x;
                    div_y <= sum_y;
                    rem_x <= '0;
                    rem_y <= '0;
                    quo_x <= '0;
                    quo_y <= '0;
                end else begin
                    o_valid <= 1'b1;
                    if (tracking) begin
                        if (lost_count == LOST_FRAMES - 1'b1) begin
                            tracking <= 1'b0;
                            lost_count <= '0;
                        end else lost_count <= lost_count + 1'b1;
                    end
                end
            end
            x <= '0; y <= '0; cnt <= '0; sum_x <= '0; sum_y <= '0;
            hit_d1 <= 1'b0; hit_d2 <= 1'b0;
        end else if (i_we) begin
            hit_d1 <= i_hit & ~line_end;
            hit_d2 <= hit_d1 & ~line_end;
            if (line_end) begin x <= '0; y <= y + 1'b1; end
            else x <= x + 1'b1;
            if (gate_hit) begin
                cnt <= cnt + 1'b1;
                sum_x <= sum_x + eff_x;
                sum_y <= sum_y + y;
            end
        end
    end
endmodule
