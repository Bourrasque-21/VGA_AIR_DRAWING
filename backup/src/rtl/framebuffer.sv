module framebuffer (
    // wrtie side
    input  logic                       wclk,
    input  logic                       we,
    input  logic [$clog2(320*240)-1:0] waddr,
    input  logic [               15:0] wdata,
    // read side
    input  logic                       rclk,
    input  logic [$clog2(320*240)-1:0] raddr,
    output logic [               15:0] rdata
);

    logic [15:0] mem[0:(320*240)-1];

    always_ff @(posedge wclk) begin
        if (we) begin
            mem[waddr] <= wdata;
        end
    end

    always_ff @(posedge rclk) begin
        rdata <= mem[raddr];
    end

endmodule
