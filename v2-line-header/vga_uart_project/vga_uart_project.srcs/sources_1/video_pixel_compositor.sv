module video_pixel_compositor (
    input  logic        i_pixel_good,
    input  logic        i_canvas_valid,
    input  logic [11:0] i_canvas_rgb,
    input  logic        i_paper,
    input  logic        i_freeze,
    input  logic [11:0] i_camera_rgb,
    input  logic        i_header_enable,
    input  logic [11:0] i_header_rgb,
    output logic [11:0] o_pixel_rgb
);
    logic [11:0] base_rgb;

    always_comb begin
        base_rgb = 12'h000;
        if (i_pixel_good) begin
            if (i_canvas_valid)
                base_rgb = i_canvas_rgb;
            else if (i_freeze)
                base_rgb = 12'h888;
            else
                base_rgb = i_paper ? 12'hfff : i_camera_rgb;
        end
        o_pixel_rgb = (i_pixel_good && i_header_enable) ? i_header_rgb : base_rgb;
    end
endmodule
