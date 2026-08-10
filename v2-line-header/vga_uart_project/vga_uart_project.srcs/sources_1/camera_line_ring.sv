module camera_line_ring (
    input  logic        i_write_rst,
    input  logic        i_wclk,
    input  logic        i_we,
    input  logic [18:0] i_waddr,
    input  logic [15:0] i_wdata,
    input  logic        i_rclk,
    input  logic        i_read_rst,
    input  logic        i_pop,
    output logic        o_empty,
    output logic [6:0]  o_count,
    output logic [5:0]  o_bank,
    output logic [7:0]  o_frame_id,
    output logic [8:0]  o_y,
    input  logic [5:0]  i_read_bank,
    input  logic [9:0]  i_read_x,
    output logic [11:0] o_read_pixel
);
    localparam int LINE_COUNT  = 64;
    localparam int LINE_PIXELS = 640;

    logic [5:0]  write_bank;
    logic        input_synced;
    logic        capture_line;
    logic [9:0]  source_x;
    logic [8:0]  source_y;
    logic        fifo_full;
    logic [5:0]  fifo_slot;
    logic [22:0] fifo_data;
    logic [7:0]  frame_id, line_frame_id;
    logic [15:0] write_addr, read_addr;
    logic        line_start, write_pixel;

    // Keep source position advancing if the FIFO ever fills.  Stopping in the
    // middle of HREF would splice two camera rows into one stored line.
    assign line_start = (i_waddr == 0) || (input_synced && (source_x == 0));
    assign write_pixel = i_we && ((line_start && !fifo_full) ||
                                  (!line_start && capture_line));
    assign write_addr = ((line_start ? fifo_slot : write_bank) * LINE_PIXELS) +
                        (line_start ? 10'd0 : source_x);
    assign read_addr = (i_read_bank * LINE_PIXELS) + i_read_x;
    assign fifo_data = {line_frame_id, source_y, write_bank};

    async_line_fifo #(
        .WIDTH  (23),
        .ADDR_W (6)
    ) U_DESC_FIFO (
        .i_wclk   (i_wclk),
        .i_wrst   (i_write_rst),
        .i_wpush  (i_we && input_synced && capture_line && (source_x == 10'd639)),
        .i_wdata  (fifo_data),
        .o_wfull  (fifo_full),
        .o_wslot  (fifo_slot),
        .i_rclk   (i_rclk),
        .i_rrst   (i_read_rst),
        .i_rpop   (i_pop),
        .o_rdata  ({o_frame_id, o_y, o_bank}),
        .o_rempty (o_empty),
        .o_rcount (o_count)
    );

    xpm_memory_tdpram #(
        .ADDR_WIDTH_A            (16),
        .ADDR_WIDTH_B            (16),
        .AUTO_SLEEP_TIME         (0),
        .BYTE_WRITE_WIDTH_A      (12),
        .CLOCKING_MODE           ("independent_clock"),
        .MEMORY_INIT_FILE        ("none"),
        .MEMORY_INIT_PARAM       ("0"),
        .MEMORY_OPTIMIZATION     ("true"),
        .MEMORY_PRIMITIVE        ("block"),
        .MEMORY_SIZE             (LINE_COUNT * LINE_PIXELS * 12),
        .MESSAGE_CONTROL         (0),
        .READ_DATA_WIDTH_A       (12),
        .READ_DATA_WIDTH_B       (12),
        .READ_LATENCY_A          (1),
        .READ_LATENCY_B          (1),
        .READ_RESET_VALUE_A      ("0"),
        .READ_RESET_VALUE_B      ("0"),
        .RST_MODE_A              ("SYNC"),
        .RST_MODE_B              ("SYNC"),
        .USE_EMBEDDED_CONSTRAINT (0),
        .USE_MEM_INIT            (0),
        .WAKEUP_TIME             ("disable_sleep"),
        .WRITE_DATA_WIDTH_A      (12),
        .WRITE_DATA_WIDTH_B      (12),
        .WRITE_MODE_A            ("no_change"),
        .WRITE_MODE_B            ("read_first")
    ) U_LINE_RAM (
        .clka           (i_wclk),
        .clkb           (i_rclk),
        .ena            (1'b1),
        .enb            (1'b1),
        .regcea         (1'b1),
        .regceb         (1'b1),
        .wea            (write_pixel),
        .web            (1'b0),
        .addra          (write_addr),
        .addrb          (read_addr),
        .dina           ({i_wdata[15:12], i_wdata[10:7], i_wdata[4:1]}),
        .dinb           (12'd0),
        .douta          (),
        .doutb          (o_read_pixel),
        .rsta           (1'b0),
        .rstb           (1'b0),
        .sleep          (1'b0),
        .injectsbiterra (1'b0),
        .injectdbiterra (1'b0),
        .injectsbiterrb (1'b0),
        .injectdbiterrb (1'b0)
    );

    always_ff @(posedge i_wclk) begin
        if (i_write_rst) begin
            write_bank   <= 6'd0;
            input_synced <= 1'b0;
            capture_line <= 1'b0;
            source_x     <= 10'd0;
            source_y     <= 9'd0;
            frame_id     <= 8'd0;
            line_frame_id <= 8'd0;
        end else if (i_we) begin
            if (i_waddr == 0) begin
                input_synced <= 1'b1;
                capture_line <= !fifo_full;
                source_x <= 10'd1;
                source_y <= 9'd0;
                frame_id <= frame_id + 1'b1;
                if (!fifo_full) begin
                    write_bank <= fifo_slot;
                    line_frame_id <= frame_id + 1'b1;
                end
            end else if (input_synced) begin
                if (source_x == 10'd0) begin
                    capture_line <= !fifo_full;
                    source_x <= 10'd1;
                    if (!fifo_full) begin
                        write_bank <= fifo_slot;
                        line_frame_id <= frame_id;
                    end
                end else if (source_x == 10'd639) begin
                    capture_line <= 1'b0;
                    source_x <= 10'd0;
                    source_y <= (source_y == 9'd479) ? 9'd0 : source_y + 1'b1;
                end else begin
                    source_x <= source_x + 1'b1;
                end
            end
        end
    end
endmodule
