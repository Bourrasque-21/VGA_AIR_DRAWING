module ov7670_capture_frontend (
    input  logic       clk,
    input  logic       rst,
    input  logic       i_href,
    input  logic       i_vsync,
    input  logic [7:0] i_data,
    input  logic       i_init_done,
    output logic       o_href,
    output logic       o_vsync,
    output logic [7:0] o_data,
    output logic       o_capture_accept
);
    (* IOB = "TRUE" *) logic camera_href_q;
    (* IOB = "TRUE" *) logic camera_vsync_q;
    (* IOB = "TRUE" *) logic [7:0] camera_data_q;
    (* ASYNC_REG = "TRUE" *) logic init_done_meta;
    (* ASYNC_REG = "TRUE" *) logic init_done_sync;

    always_ff @(posedge clk) begin
        camera_href_q  <= i_href;
        camera_vsync_q <= i_vsync;
        camera_data_q  <= i_data;
    end

    assign o_href  = camera_href_q;
    assign o_vsync = camera_vsync_q;
    assign o_data  = camera_data_q;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            init_done_meta  <= 1'b0;
            init_done_sync  <= 1'b0;
            o_capture_accept <= 1'b0;
        end else begin
            init_done_meta <= i_init_done;
            init_done_sync <= init_done_meta;
            if (!init_done_sync) begin
                o_capture_accept <= 1'b0;
            end else if (camera_vsync_q) begin
                o_capture_accept <= 1'b1;
            end
        end
    end
endmodule
