# UART 펜 설정 패킷 구조

현재 UART 송신 패킷은 **프레임당 6바이트**입니다.

```text
[0] 0xAA              // start byte
[1] X_center[8:1]     // X 좌표, LSB 1비트 버림
[2] Y_center[7:0]     // Y 좌표, 0~239 표현 가능
[3] control           // 펜 설정 비트필드
[4] texture_shape     // 펜 질감 모드 번호
[5] 0x55              // end byte
```

수신 측 좌표 복원:

```text
x = packet[1] << 1
y = packet[2]
```

`control` 바이트 구조:

```text
bit[7] sw_texture_enable
bit[6] sw_eraser
bit[5] sw_size
bit[4] sw_paint_red
bit[3] sw_paint_green
bit[2] sw_paint_blue
bit[1] clear_btn
bit[0] reserved, 0
```

`texture_shape` 값:

```text
0: spray small
1: spray medium
2: spray large
3: diagonal thin
4: diagonal wide
```

UART 설정:

```text
baud rate: 115200
format: 8N1
packet bits: 6 bytes * 10 bits = 60 bits
packet time: 약 0.521 ms
30 fps frame time: 약 33.33 ms
```

30fps 기준 한 프레임 안에 6바이트 전송은 충분히 여유가 있습니다.

## 포함 파일

이 번들은 기존 VGA 프로젝트에 덮어씌우거나 비교 적용하기 위한 변경/추가 파일 묶음입니다.

```text
sources_1/imports/rtl/top_VGA.sv
sources_1/imports/rtl/canvas_buffer.sv
sources_1/imports/rtl/brush_draw_engine.sv
sources_1/imports/rtl/circular_brush_renderer.sv
sources_1/imports/rtl/uart_packet_sender.sv
sources_1/imports/rtl/uart_tx.sv
sources_1/imports/rtl/baud_tick_16oversample.v
constrs_1/imports/constraints/Basys-3-Master.xdc
project_reference/VGA_0713_ver1.xpr
```

`project_reference/VGA_0713_ver1.xpr`는 현재 Vivado 프로젝트 파일의 참조본입니다. 다른 프로젝트에 합칠 때는 XPR을 그대로 쓰기보다 RTL 파일을 sources에 추가하는 쪽이 안전합니다.

## Top 연결 요약

`top_VGA.sv`에 UART TX 출력이 추가되었습니다.

```systemverilog
output logic tx
```

`canvas_buffer_top`에서 필터링된 좌표와 현재 질감 모드를 top으로 내보냅니다.

```systemverilog
.X_center         (X_center_o),
.Y_center         (Y_center_o),
.pen_texture_shape(pen_texture_shape_o)
```

`uart_packet_sender`는 `clk_100`에서 동작하며, `vsync` rising edge를 동기화해서 프레임당 한 번 패킷을 전송합니다.

## 핀/스위치 매핑

UART TX:

```text
tx -> Basys3 USB-RS232 TX, PACKAGE_PIN A18
```

펜 질감 스위치:

```text
SW5 / V15: sw_texture_enable
SW6 / W14: sw_texture_shape_up
SW7 / W13: sw_texture_shape_down
```

기존 펜 설정:

```text
sw_paint_red
sw_paint_green
sw_paint_blue
sw_eraser
sw_size
clear_btn
```

## 펜 질감 기능

기존 원형 브러시 외에 질감 모드가 켜져 있을 때 다음 5개 모드를 순환합니다.

```text
0: 스프레이 작게
1: 스프레이 중간
2: 스프레이 크게
3: 대각 직사각형 얇게
4: 대각 직사각형 굵게
```

별, 삼각형, 스마일 모드는 제거했습니다.

## UART 모듈 구성

다운로드 폴더의 UART 패키지에서 아래 2개 파일만 사용합니다.

```text
uart_tx.sv
baud_tick_16oversample.v
```

`uart_top.sv`와 `uart_rx.sv`는 이번 송신 전용 패킷 구조에는 사용하지 않습니다. `uart_top.sv`는 RX/FIFO echo 구조이고, 원본 패키지에 필요한 `fifo`, `baud_gen` 파일이 포함되어 있지 않아 제외했습니다.

새로 추가한 `uart_packet_sender.sv`가 좌표/펜 설정을 패킷으로 만들어 `uart_tx`에 한 바이트씩 넣습니다.

## 검증 결과

현재 작업본 기준으로 다음 검증을 통과했습니다.

```text
xvlog -sv 전체 RTL 문법 체크 통과
Vivado synth_design -rtl -top top_VGA 통과
0 Warnings, 0 Critical Warnings, 0 Errors
```

