module reset_controller (
    input  logic clk,
    input  logic rst,
    input  logic i_pclk,
    output logic o_clock_rst,
    output logic o_system_rst,
    output logic o_system_pclk_rst
);
    logic por_done = 1'b0;
    logic [23:0] por_count = 24'd0;
    (* ASYNC_REG = "TRUE" *) logic [1:0] system_reset_pipe = 2'b11;
    (* ASYNC_REG = "TRUE" *) logic [1:0] system_reset_pclk_pipe = 2'b11;

    always_ff @(posedge clk) begin
        if (!por_done) begin
            if (por_count == 24'd9_999_999) begin
                por_done <= 1'b1;
            end else begin
                por_count <= por_count + 1'b1;
            end
        end
    end

    assign o_clock_rst = ~por_done;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            system_reset_pipe <= 2'b11;
        end else if (!por_done) begin
            system_reset_pipe <= 2'b11;
        end else begin
            system_reset_pipe <= {system_reset_pipe[0], 1'b0};
        end
    end

    assign o_system_rst = system_reset_pipe[1];

    always_ff @(posedge i_pclk or posedge o_system_rst) begin
        if (o_system_rst) begin
            system_reset_pclk_pipe <= 2'b11;
        end else begin
            system_reset_pclk_pipe <= {system_reset_pclk_pipe[0], 1'b0};
        end
    end

    assign o_system_pclk_rst = system_reset_pclk_pipe[1];
endmodule
