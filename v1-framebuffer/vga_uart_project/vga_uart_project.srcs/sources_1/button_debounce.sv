`timescale 1ns / 1ps

// 택트 버튼 디바운서: 2FF 동기화 후 STABLE_CYCLES 동안 레벨이 유지되면
// 확정하고, 눌림(0->1) 확정 시점에 1클럭 펄스를 낸다.
// (ov7670_sccb_ctrl의 start_btn 디바운스와 같은 패턴)
module button_debounce #(
    parameter int STABLE_CYCLES = 1_000_000  // 10ms @ 100MHz
) (
    input  logic clk,
    input  logic rst,
    input  logic btn_in,
    output logic pulse
);
    logic meta, sync, stable_level;
    logic [$clog2(STABLE_CYCLES)-1:0] cnt;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            meta         <= 1'b0;
            sync         <= 1'b0;
            stable_level <= 1'b0;
            cnt          <= '0;
            pulse        <= 1'b0;
        end else begin
            meta  <= btn_in;
            sync  <= meta;
            pulse <= 1'b0;

            if (sync == stable_level) begin
                cnt <= '0;
            end else if (cnt == STABLE_CYCLES - 1) begin
                stable_level <= sync;
                cnt          <= '0;
                pulse        <= sync;  // 눌림 확정일 때만 펄스
            end else begin
                cnt <= cnt + 1;
            end
        end
    end
endmodule
