module canvas_buffer (
    input  logic                       i_write_clk,
    input  logic                       i_clear,
    input  logic                       i_write_enable,
    input  logic [$clog2(320*240)-1:0] i_write_addr,
    input  logic [ 3:0]                i_write_data,
    input  logic                       i_read_clk,
    input  logic [$clog2(320*240)-1:0] i_read_addr,
    output logic [ 3:0]                o_read_data
);

    // 100% BRAM 추론을 위한 4비트 76,800깊이의 메모리 어레이 선언 (초기값 0000(투명))
    logic [3:0] mem[0:(320*240)-1] = '{default: 4'b0000};

    logic clearing;
    logic [$clog2(320*240)-1:0] cnt;

    // 1. 클리어 제어 로직 (Sequential)
    always_ff @(posedge i_write_clk) begin
        if (i_clear) begin
            cnt      <= 0;
            clearing <= 1'b1;
        end else if (clearing) begin
            if (cnt == (320 * 240 - 1)) begin
                clearing <= 1'b0;
            end else begin
                cnt <= cnt + 1;
            end
        end
    end

    // 2. RAM 입력 신호 MUX (Combinational -> 추가 딜레이 없음)
    logic                       ram_we;
    logic [$clog2(320*240)-1:0] ram_waddr;
    logic [3:0]                 ram_wdata;

    assign ram_we    = clearing ? 1'b1   : i_write_enable;
    assign ram_waddr = clearing ? cnt    : i_write_addr;
    assign ram_wdata = clearing ? 4'b0000 : i_write_data; // 초기화 시 4'b0000(투명) 기입

    // 3. 표준 BRAM 쓰기 포트 템플릿 (오직 하나의 always_ff 및 단일 주소/데이터/쓰기 변수)
    always_ff @(posedge i_write_clk) begin
        if (ram_we) begin
            mem[ram_waddr] <= ram_wdata;
        end
    end

    // 4. 표준 BRAM 읽기 포트 템플릿
    always_ff @(posedge i_read_clk) begin
        o_read_data <= mem[i_read_addr];
    end

endmodule
