module vga_transport_header_encoder (
    input  logic [9:0]  i_screen_x,
    input  logic [9:0]  i_screen_y,
    input  logic        i_line_valid,
    input  logic [7:0]  i_frame_id,
    input  logic [8:0]  i_source_y,
    output logic        o_header_enable,
    output logic [11:0] o_header_rgb
);
    logic [4:0] bit_index;
    logic [3:0] checksum;
    logic       data_bit;

    always_comb begin
        checksum = i_frame_id[3:0] ^ i_source_y[3:0] ^ i_source_y[7:4] ^
                   {3'b000, i_source_y[8]} ^ 4'hA;
        bit_index = (i_screen_x >= 619) ? (i_screen_x - 10'd619) : 5'd0;
        o_header_enable = (i_screen_y < 480) && i_screen_y[0] &&
                          (i_screen_x >= 619) && (i_screen_x < 640);
        data_bit = 1'b0;
        case (bit_index)
            0:       data_bit = 1'b1;
            1:       data_bit = 1'b0;
            2:       data_bit = 1'b1;
            3:       data_bit = i_line_valid;
            4:       data_bit = i_frame_id[0];
            5:       data_bit = i_frame_id[1];
            6:       data_bit = i_frame_id[2];
            7:       data_bit = i_frame_id[3];
            8:       data_bit = i_source_y[0];
            9:       data_bit = i_source_y[1];
            10:      data_bit = i_source_y[2];
            11:      data_bit = i_source_y[3];
            12:      data_bit = i_source_y[4];
            13:      data_bit = i_source_y[5];
            14:      data_bit = i_source_y[6];
            15:      data_bit = i_source_y[7];
            16:      data_bit = i_source_y[8];
            17:      data_bit = checksum[0];
            18:      data_bit = checksum[1];
            19:      data_bit = checksum[2];
            20:      data_bit = checksum[3];
            default: data_bit = 1'b0;
        endcase

        o_header_rgb = data_bit ? 12'hfff : 12'h000;
    end
endmodule
