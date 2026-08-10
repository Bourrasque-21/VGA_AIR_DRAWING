module ov7670_memcontroller (
    input  logic                       i_pclk,
    input  logic                       rst,
    input  logic                       i_href,
    input  logic                       i_vsync,
    input  logic [ 7:0]                i_pdata,
    output logic                       o_we,
    output logic [$clog2(640*480)-1:0] o_waddr,
    output logic [ 15:0]               o_wdata
);

    logic [15:0] pixeldata;
    logic        pixelevenodd;

    assign o_wdata = pixeldata;

    // rst is generated in the PCLK domain.  Synchronous rst guarantees
    // that byte phase and address restart together on the qualified frame edge.
    always_ff @(posedge i_pclk) begin
        if (rst) begin
            o_we           <= 1'b0;
            pixeldata    <= 0;
            o_waddr        <= 0;
            pixelevenodd <= 1'b0;
        end else begin
            if (o_we) begin
                o_waddr <= o_waddr + 1;
            end

            if (i_href) begin
                if (pixelevenodd == 1'b0) begin
                    o_we              <= 1'b0;
                    pixeldata[15:8] <= i_pdata;
                    pixelevenodd    <= ~pixelevenodd;
                end else begin
                    o_we             <= 1'b1;
                    pixeldata[7:0] <= i_pdata;
                    pixelevenodd   <= ~pixelevenodd;
                end
            end else begin
                o_we           <= 1'b0;
                pixeldata    <= 0;
                pixelevenodd <= 1'b0;
            end
            // Some OV7670 modules assert VSYNC on the final active-byte edge.
            // Do not discard that byte: finish HREF first, then rst during
            // vertical blanking when HREF is low.  Losing that last byte kept
            // source line 479 from ever completing in the line ring.
            if (i_vsync && !i_href) begin
                o_we           <= 1'b0;
                pixeldata    <= 0;
                o_waddr        <= 0;
                pixelevenodd <= 1'b0;
            end
        end
    end
endmodule
