module overlay_pixel_mux (
    input  logic        i_canvas_valid,
    input  logic [15:0] i_frame_pixel,
    input  logic [15:0] i_canvas_pixel,
    output logic [15:0] o_display_pixel
);
    assign o_display_pixel = i_canvas_valid ? i_canvas_pixel : i_frame_pixel;
endmodule
