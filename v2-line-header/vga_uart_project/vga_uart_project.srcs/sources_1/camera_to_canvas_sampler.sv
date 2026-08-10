module camera_to_canvas_sampler (
    input  logic        clk,
    input  logic        rst,
    input  logic        i_vsync,
    input  logic        i_write_enable,
    input  logic [18:0] i_write_addr,
    output logic        o_sample_valid
);
    logic [9:0] camera_x;
    logic [8:0] camera_y;

    assign o_sample_valid = i_write_enable && !i_vsync &&
                            !camera_x[0] && !camera_y[0];

    always_ff @(posedge clk) begin
        if (rst) begin
            camera_x <= 10'd0;
            camera_y <= 9'd0;
        end else if (i_vsync) begin
            camera_x <= 10'd0;
            camera_y <= 9'd0;
        end else if (i_write_enable) begin
            if (i_write_addr == 0) begin
                camera_x <= 10'd1;
                camera_y <= 9'd0;
            end else if (camera_x == 10'd639) begin
                camera_x <= 10'd0;
                camera_y <= (camera_y == 9'd479) ? 9'd0 : camera_y + 1'b1;
            end else begin
                camera_x <= camera_x + 1'b1;
            end
        end
    end
endmodule
