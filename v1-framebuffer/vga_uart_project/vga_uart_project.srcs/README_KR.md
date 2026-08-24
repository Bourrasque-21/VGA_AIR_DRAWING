# UART 양방향 패킷 규격

PC UI와 FPGA는 115200 baud, 8N1 형식의 UART로 마커 좌표와 도구 설정을 교환함. FPGA는 프레임마다 현재 좌표와 실효 상태를 전송하고, PC는 사용자가 설정을 변경한 경우에만 제어 패킷을 전송함.

| 방향 | 길이 | 전송 시점 | 내용 |
| --- | ---: | --- | --- |
| FPGA → PC | 6byte | 카메라 프레임당 1회 | 마커 좌표와 FPGA 실효 상태 |
| PC → FPGA | 4byte | UI 설정 변경 시 | 도구·색상·배경·캡처 설정 |

## 1. FPGA → PC 패킷

`uart_packet_sender`는 카메라 `vsync`마다 좌표와 `pen_config_controller`의 실효 상태를 래치한 후 6byte 패킷을 전송함.

```text
[0] 0xAA          start byte
[1] X[8:1]        마커 X 좌표, LSB 1bit 제외
[2] Y[7:0]        마커 Y 좌표
[3] control       도구·굵기·색상·지우기 상태
[4] state         캘리그래피/스프레이 모양·도화지·캡처 상태
[5] 0x55          end byte
```

PC에서 좌표를 복원하는 방식은 다음과 같음.

```text
x = packet[1] << 1
y = packet[2]
```

### `control` byte

```text
bit[7] texture_enable
bit[6] eraser
bit[5] size
bit[4] red
bit[3] green
bit[2] blue
bit[1] clear
bit[0] reserved = 0
```

### `state` byte

```text
bit[7:5] reserved = 0
bit[4]   freeze
bit[3]   paper
bit[2:0] texture_shape
```

## 2. PC → FPGA 패킷

PC UI는 도구 설정이 변경된 경우 `uart_packet_decoder`로 4byte 패킷을 전송함.

```text
[0] 0xA5          start byte
[1] control       도구·굵기·색상·지우기 명령
[2] state         캘리그래피/스프레이 모양·도화지·캡처 명령
[3] 0x5A          end byte
```

`control`과 `state`의 비트 배치는 FPGA → PC 패킷과 동일함. 수신한 값은 패킷 검사가 완료된 경우에만 `pen_config_controller`에 전달됨.

종료 바이트가 `0x5A`가 아니면 패킷 전체를 폐기함. 바이트 사이의 간격이 3byte 전송 시간을 초과하면 현재 수신 상태를 초기화하고 다음 `0xA5`를 대기함.

## 3. 도구 모양 값

| `texture_shape` | 도구 | 굵기 |
| ---: | --- | --- |
| 0 | 스프레이 | 작게 |
| 1 | 스프레이 | 중간 |
| 2 | 스프레이 | 크게 |
| 3 | 캘리그래피 | 얇게 |
| 4 | 캘리그래피 | 굵게 |

일반 볼펜은 `texture_enable=0`, 지우개는 `eraser=1`로 선택함. `size`는 볼펜과 지우개의 2단계 굵기에 사용되며, 스프레이와 캘리그래피에서는 `texture_shape` 값과 함께 갱신됨.

## 4. 상태 동기화

`pen_config_controller`가 도구 상태의 단일 소유자로 동작함. PC 명령과 물리 버튼 입력을 같은 상태 레지스터에 반영하며, 같은 clock에 두 입력이 겹치면 물리 버튼을 우선함.

FPGA는 적용된 실효 상태를 다음 FPGA → PC 패킷으로 다시 전송함. PC UI는 자신이 송신한 값을 즉시 확정하지 않고 FPGA가 echo한 상태로 화면을 갱신하므로 보드와 UI의 표시가 일치함.

## 5. UART 설정 및 전송 시간

```text
baud rate : 115200
format    : 8N1
6byte TX  : 60bit / 115200 ≈ 0.521 ms
4byte RX  : 40bit / 115200 ≈ 0.347 ms
```

6byte 상태 패킷의 전송 시간은 30fps 기준 한 프레임 시간인 약 33.33ms보다 짧으므로 프레임당 1회 전송에 충분한 여유가 있음.

## 6. 관련 RTL

| 모듈 | 역할 |
| --- | --- |
| `uart_packet_sender.sv` | 좌표와 실효 상태를 6byte 패킷으로 변환함 |
| `uart_packet_decoder.sv` | PC의 4byte 패킷을 검사하고 설정값을 복원함 |
| `uart_tx.sv` | UART byte 송신을 수행함 |
| `uart_rx.sv` | UART byte 수신을 수행함 |
| `baud_tick_16oversample.v` | 송수신 baud tick을 생성함 |
| `pen_config_controller.sv` | UART와 물리 버튼의 상태를 통합함 |

Basys 3 USB-UART 핀은 다음과 같이 연결됨.

```text
RX: PACKAGE_PIN B18
TX: PACKAGE_PIN A18
```
