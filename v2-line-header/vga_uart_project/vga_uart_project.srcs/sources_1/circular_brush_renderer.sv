module circular_brush_renderer (
    input  logic                       clk,
    input  logic                       rst,
    input  logic                       i_point_valid,
    output logic                       o_point_ready,
    input  logic [ 8:0]                i_point_x,
    input  logic [ 8:0]                i_point_y,
    input  logic [ 3:0]                i_color,
    input  logic [ 4:0]                i_radius,
    input  logic [ 10:0]               i_sq_threshold,
    input  logic                       i_texture_enable,
    input  logic [ 2:0]                i_texture_shape,
    output logic                       o_stamp_done,
    output logic                       o_ram_we,
    output logic [$clog2(320*240)-1:0] o_ram_waddr,
    output logic [ 3:0]                o_ram_wdata,
    output logic                       o_busy
);
    localparam logic TEXTURE_SPRAY    = 1'b0;
    localparam logic TEXTURE_DIAGONAL = 1'b1;

    logic [8:0] center_x;
    logic [8:0] center_y;
    logic [3:0] color_reg;
    logic [4:0] radius_reg;
    logic [10:0] threshold_reg;

    logic       texture_on_reg;
    logic       texture_kind_reg;
    logic [2:0] spray_density_reg;
    logic [2:0] diagonal_half_width_reg;

    logic signed [5:0] offset_x;
    logic signed [5:0] offset_y;
    logic signed [5:0] radius_signed;

    logic start_texture_on;
    logic start_texture_kind;
    logic [4:0] start_radius;
    logic [2:0] start_spray_density;
    logic [2:0] start_diagonal_half_width;

    logic signed [11:0] canvas_x;
    logic signed [11:0] canvas_y;
    logic [6:0] abs_offset_x;
    logic [6:0] abs_offset_y;
    logic [14:0] offset_x_sq;
    logic [14:0] offset_y_sq;
    logic [14:0] distance_sq;
    logic [14:0] radius_extend;
    logic [14:0] radius_sq;
    logic in_bounds;
    logic plain_circle_mask;
    logic texture_circle_mask;

    logic [7:0] spray_hash;
    logic spray_mask;

    logic signed [6:0] diagonal_delta;
    logic [6:0] abs_diagonal_delta;
    logic diagonal_rect_mask;

    logic draw_pixel;

    assign o_point_ready = !o_busy;

    function automatic logic [6:0] abs_s7(input logic signed [6:0] value);
        logic signed [6:0] neg_value;
        begin
            neg_value = -value;
            abs_s7 = (value < 0) ? neg_value[6:0] : value[6:0];
        end
    endfunction

    function automatic logic [4:0] texture_radius(
        input logic [4:0] base_radius,
        input logic [4:0] add_radius,
        input logic [4:0] min_radius
    );
        logic [5:0] sum_radius;
        begin
            sum_radius = {1'b0, base_radius} + {1'b0, add_radius};

            if (sum_radius < {1'b0, min_radius}) begin
                texture_radius = min_radius;
            end else if (sum_radius > 6'd11) begin
                texture_radius = 5'd11;
            end else begin
                texture_radius = sum_radius[4:0];
            end
        end
    endfunction

    // 1. Pick the stamp profile that will be latched when a new point starts.
    always_comb begin
        start_texture_on          = i_texture_enable && i_color[3];
        start_texture_kind        = TEXTURE_SPRAY;
        start_radius              = i_radius;
        start_spray_density       = 3'd2;
        start_diagonal_half_width = 3'd1;

        if (start_texture_on) begin
            case (i_texture_shape)
                3'd0: begin
                    start_texture_kind  = TEXTURE_SPRAY;
                    start_radius        = texture_radius(i_radius, 5'd2, 5'd5);
                    start_spray_density = 3'd1;
                end
                3'd1: begin
                    start_texture_kind  = TEXTURE_SPRAY;
                    start_radius        = texture_radius(i_radius, 5'd4, 5'd7);
                    start_spray_density = 3'd2;
                end
                3'd2: begin
                    start_texture_kind  = TEXTURE_SPRAY;
                    start_radius        = texture_radius(i_radius, 5'd6, 5'd9);
                    start_spray_density = 3'd3;
                end
                3'd3: begin
                    start_texture_kind        = TEXTURE_DIAGONAL;
                    start_radius              = texture_radius(i_radius, 5'd2, 5'd5);
                    start_diagonal_half_width = 3'd1;
                end
                3'd4: begin
                    start_texture_kind        = TEXTURE_DIAGONAL;
                    start_radius              = texture_radius(i_radius, 5'd4, 5'd7);
                    start_diagonal_half_width = 3'd2;
                end
                default: begin
                    start_texture_kind  = TEXTURE_SPRAY;
                    start_radius        = texture_radius(i_radius, 5'd2, 5'd5);
                    start_spray_density = 3'd1;
                end
            endcase
        end
    end

    // 2. Convert the current raster offset into canvas coordinates and common geometry.
    always_comb begin
        radius_signed = $signed({1'b0, radius_reg});

        canvas_x = $signed({1'b0, center_x}) + offset_x;
        canvas_y = $signed({1'b0, center_y}) + offset_y;

        abs_offset_x = abs_s7($signed({offset_x[5], offset_x}));
        abs_offset_y = abs_s7($signed({offset_y[5], offset_y}));

        offset_x_sq = {8'd0, abs_offset_x} * {8'd0, abs_offset_x};
        offset_y_sq = {8'd0, abs_offset_y} * {8'd0, abs_offset_y};
        distance_sq = offset_x_sq + offset_y_sq;

        radius_extend = {10'd0, radius_reg};
        radius_sq     = radius_extend * radius_extend;

        plain_circle_mask   = (distance_sq <= {4'd0, threshold_reg});
        texture_circle_mask = (distance_sq <= radius_sq);

        in_bounds = (canvas_x >= 0) && (canvas_x < 320) &&
                    (canvas_y >= 0) && (canvas_y < 240);
    end

    // 3. Build texture masks.
    always_comb begin
        spray_hash = {3'b000, canvas_x[4:0]} ^
                     ({3'b000, canvas_y[4:0]} << 1) ^
                     {2'b00, center_x[5:0]} ^
                     ({2'b00, center_y[5:0]} << 2) ^
                     {2'b00, offset_x[2:0], offset_y[2:0]};

        spray_mask = texture_circle_mask && (spray_hash[2:0] <= spray_density_reg);

        diagonal_delta     = $signed({offset_y[5], offset_y}) -
                             $signed({offset_x[5], offset_x});
        abs_diagonal_delta = abs_s7(diagonal_delta);

        diagonal_rect_mask = (abs_diagonal_delta <= {4'd0, diagonal_half_width_reg}) &&
                             (abs_offset_x <= {2'd0, radius_reg}) &&
                             (abs_offset_y <= {2'd0, radius_reg});
    end

    // 4. Select the final pixel for this raster location.
    always_comb begin
        draw_pixel = plain_circle_mask;

        if (texture_on_reg) begin
            case (texture_kind_reg)
                TEXTURE_SPRAY:    draw_pixel = spray_mask;
                TEXTURE_DIAGONAL: draw_pixel = diagonal_rect_mask;
            endcase
        end
    end

    // 5. Scan the stamp area one pixel per clock and write selected pixels.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            center_x                <= 9'd0;
            center_y                <= 9'd0;
            color_reg               <= 4'b0000;
            radius_reg              <= 5'd2;
            threshold_reg           <= 11'd6;
            texture_on_reg          <= 1'b0;
            texture_kind_reg        <= TEXTURE_SPRAY;
            spray_density_reg       <= 3'd2;
            diagonal_half_width_reg <= 3'd1;
            offset_x                <= -6'sd2;
            offset_y                <= -6'sd2;
            o_stamp_done              <= 1'b0;
            o_ram_we                  <= 1'b0;
            o_ram_waddr               <= '0;
            o_ram_wdata               <= 4'b0000;
            o_busy                    <= 1'b0;
        end else begin
            o_ram_we     <= 1'b0;
            o_stamp_done <= 1'b0;

            if (!o_busy) begin
                if (i_point_valid) begin
                    center_x                <= i_point_x;
                    center_y                <= i_point_y;
                    color_reg               <= i_color;
                    radius_reg              <= start_radius;
                    threshold_reg           <= i_sq_threshold;
                    texture_on_reg          <= start_texture_on;
                    texture_kind_reg        <= start_texture_kind;
                    spray_density_reg       <= start_spray_density;
                    diagonal_half_width_reg <= start_diagonal_half_width;
                    offset_x                <= -$signed({1'b0, start_radius});
                    offset_y                <= -$signed({1'b0, start_radius});
                    o_busy                    <= 1'b1;
                end
            end else begin
                if (draw_pixel && in_bounds) begin
                    o_ram_we    <= 1'b1;
                    o_ram_waddr <= $unsigned(canvas_y) * 320 + $unsigned(canvas_x);
                    o_ram_wdata <= color_reg;
                end

                if (offset_x == radius_signed) begin
                    offset_x <= -radius_signed;
                    if (offset_y == radius_signed) begin
                        o_busy       <= 1'b0;
                        o_stamp_done <= 1'b1;
                    end else begin
                        offset_y <= offset_y + 6'sd1;
                    end
                end else begin
                    offset_x <= offset_x + 6'sd1;
                end
            end
        end
    end
endmodule
