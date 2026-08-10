module canvas_pixel_decoder (
    input  logic [3:0]  i_canvas_pixel,
    output logic        o_canvas_valid,
    output logic [11:0] o_canvas_rgb
);
    assign o_canvas_valid = i_canvas_pixel[3];
    assign o_canvas_rgb = {
        {4{i_canvas_pixel[2]}},
        {4{i_canvas_pixel[1]}},
        {4{i_canvas_pixel[0]}}
    };
endmodule
