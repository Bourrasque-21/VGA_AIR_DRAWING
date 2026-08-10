module async_line_fifo #(
    parameter int WIDTH = 15,
    parameter int ADDR_W = 7
) (
    input  logic              i_wclk,
    input  logic              i_wrst,
    input  logic              i_wpush,
    input  logic [WIDTH-1:0]  i_wdata,
    output logic              o_wfull,
    output logic [ADDR_W-1:0] o_wslot,
    input  logic              i_rclk,
    input  logic              i_rrst,
    input  logic              i_rpop,
    output logic [WIDTH-1:0]  o_rdata,
    output logic              o_rempty,
    output logic [ADDR_W:0]   o_rcount
);
    localparam int PTR_W = ADDR_W + 1;
    (* ram_style = "distributed" *) logic [WIDTH-1:0] mem [0:(1<<ADDR_W)-1];
    logic [PTR_W-1:0] wbin, wgray, rbin, rgray;
    (* ASYNC_REG = "TRUE" *) logic [PTR_W-1:0] rgray_w1, rgray_w2;
    (* ASYNC_REG = "TRUE" *) logic [PTR_W-1:0] wgray_r1, wgray_r2;
    logic [PTR_W-1:0] wbin_next, wgray_next, rbin_next, rgray_next, wbin_sync_r;

    function automatic logic [PTR_W-1:0] gray(input logic [PTR_W-1:0] b);
        gray = (b >> 1) ^ b;
    endfunction

    function automatic logic [PTR_W-1:0] bin(input logic [PTR_W-1:0] g);
        bin[PTR_W-1] = g[PTR_W-1];
        for (int n = PTR_W-2; n >= 0; n--) bin[n] = bin[n+1] ^ g[n];
    endfunction

    assign wbin_next = wbin + (i_wpush && !o_wfull);
    assign wgray_next = gray(wbin_next);
    assign rbin_next = rbin + (i_rpop && !o_rempty);
    assign rgray_next = gray(rbin_next);
    assign o_wslot = wbin[ADDR_W-1:0];
    assign o_rdata = mem[rbin[ADDR_W-1:0]];
    assign o_rempty = (rgray == wgray_r2);
    assign wbin_sync_r = bin(wgray_r2);
    assign o_rcount = wbin_sync_r - rbin;

    always_ff @(posedge i_wclk)
        if (i_wpush && !o_wfull) mem[wbin[ADDR_W-1:0]] <= i_wdata;

    always_ff @(posedge i_wclk) begin
        if (i_wrst) begin
            wbin <= '0;
            wgray <= '0;
            rgray_w1 <= '0;
            rgray_w2 <= '0;
            o_wfull <= 1'b0;
        end else begin
            rgray_w1 <= rgray;
            rgray_w2 <= rgray_w1;
            o_wfull <= (wgray_next ==
                       {~rgray_w2[PTR_W-1:PTR_W-2], rgray_w2[PTR_W-3:0]});
            if (i_wpush && !o_wfull) begin
                wbin <= wbin_next;
                wgray <= wgray_next;
            end
        end
    end

    always_ff @(posedge i_rclk) begin
        if (i_rrst) begin
            rbin <= '0;
            rgray <= '0;
            wgray_r1 <= '0;
            wgray_r2 <= '0;
        end else begin
            wgray_r1 <= wgray;
            wgray_r2 <= wgray_r1;
            if (i_rpop && !o_rempty) begin
                rbin <= rbin_next;
                rgray <= rgray_next;
            end
        end
    end
endmodule
