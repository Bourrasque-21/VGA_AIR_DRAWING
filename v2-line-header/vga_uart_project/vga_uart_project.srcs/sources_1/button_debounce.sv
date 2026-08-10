module button_debounce #(
    parameter int STABLE_CYCLES = 1_000_000
) (
    input  logic clk,
    input  logic rst,
    input  logic i_btn,
    output logic o_pulse
);
    logic meta;
    logic sync;
    logic stable_level;
    logic [$clog2(STABLE_CYCLES)-1:0] count;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            meta         <= 1'b0;
            sync         <= 1'b0;
            stable_level <= 1'b0;
            count        <= '0;
            o_pulse      <= 1'b0;
        end else begin
            meta    <= i_btn;
            sync    <= meta;
            o_pulse <= 1'b0;

            if (sync == stable_level) begin
                count <= '0;
            end else if (count == STABLE_CYCLES - 1) begin
                stable_level <= sync;
                count        <= '0;
                o_pulse      <= sync;
            end else begin
                count <= count + 1'b1;
            end
        end
    end
endmodule
