# OV7670 VGA Air Drawing

## 1. 프로젝트 개요

이 프로젝트는 OV7670이 출력하는 640×480 RGB565 영상을 Basys 3에서 받아 VGA로 내보내고, VGA 캡처카드와 UART를 통해 PC의 `air_draw_ui.py`에 전달하는 시스템이다.

전체 데이터 흐름은 다음과 같다.

1. Basys 3가 약 22.981 MHz의 XCLK를 OV7670에 공급한다.
2. OV7670은 PCLK, VSYNC, HREF, D[7:0]으로 640×480 RGB565 영상을 출력한다.
3. FPGA는 D[7:0]의 연속된 두 바이트를 RGB565 한 픽셀로 조립한다.
4. 한 프레임 전체를 저장하지 않고 640픽셀 × 64라인 링 버퍼에 순서대로 저장한다.
5. 저장된 라인을 VGA 640×480 화면에 흘려보내면서 각 라인에 frame ID와 원래 y 좌표를 표시하는 21픽셀 헤더를 붙인다.
6. VGA 캡처카드는 이 화면을 640×480 MJPEG 영상으로 PC에 전달한다.
7. Python은 21픽셀 헤더를 읽어 각 라인이 어느 카메라 프레임의 몇 번째 줄인지 알아낸다.
8. Python이 0번부터 479번까지 모든 라인을 모으면 완전한 640×480 프레임 하나를 UI에 표시한다.
9. 펜 위치와 도구 설정은 영상과 별도로 115200 baud UART로 양방향 전달한다.

현재 안정 설정은 XCLK 약 22.981 MHz, OV7670 `CLKRC=0x02`, 실측 PCLK 약 15.15 MHz, 카메라 약 20 fps다. 이보다 PCLK를 높이면 밝은 장면에서 보라색·노란색 결점이 발생했기 때문에 현재 값이 기준이다.

## 2. 폴더 구조

- `vga_project`
  - `README.md`: 프로젝트 전체 동작을 설명하는 기준 문서
  - `requirements.txt`: OpenCV, NumPy, pyserial 의존성
  - `.gitignore`: Vivado 생성물, Python 캐시, 가상환경 제외 규칙
  - `python_ui`
    - `.venv`: Python 실행 가상환경
    - `air_draw_ui.py`: 캡처카드 영상 재조립, UART 통신, Air Draw UI
    - `capture_probe.py`: UVC 수신, 고유 전송 화면, 완성 프레임 속도 진단
    - `assets`: 펜, 스프레이, 대각선 브러시, 지우개 마커 이미지
    - `captures`: UI의 SAVE 버튼으로 저장한 PNG 이미지(처음 저장할 때 생성)
  - `vga_uart_project`
    - `vga_uart_project.xpr`: Vivado 2020.2 프로젝트 파일
    - `vga_uart_project.srcs/sources_1`: SystemVerilog RTL 소스
    - `vga_uart_project.srcs/constrs_1/Basys-3-Master.xdc`: Basys 3 핀과 타이밍 제약
    - `vga_uart_project.runs/impl_1/top_airDrawing.bit`: 생성된 bitstream
    - `.cache`, `.gen`, `.hw`, `.ip_user_files`: Vivado가 자동으로 만드는 파일

RTL 파일은 `sources_1` 한 폴더에 있으며 `top_airDrawing.sv`가 최상위 모듈이다. 한 SystemVerilog 파일에는 모듈 또는 package 하나만 둔다.

## 3. `top_airDrawing`에서 실제로 일어나는 일

`top_airDrawing`은 직접 픽셀을 계산하지 않는다. 아래 모듈들을 연결해 카메라 입력, 라인 저장, 캔버스 합성, VGA 출력, UART 통신을 하나의 시스템으로 만든다.

### 3.1 `reset_controller`: 전원 투입과 클록 도메인별 리셋

Basys 3 전원이 들어오자마자 카메라와 BRAM을 사용하면 XCLK와 PCLK가 아직 안정되지 않아 주소와 RGB565 바이트 순서가 틀어질 수 있다. `reset_controller`는 이를 막기 위해 다음 순서로 리셋을 만든다.

1. 100 MHz `clk`를 10000000번 세어 약 100 ms의 power-on reset 시간을 만든다.
2. 이 시간이 끝날 때까지 `o_clock_rst`를 유지해 카메라 XCLK용 MMCM을 리셋 상태에 둔다.
3. 전원 리셋이 끝나면 100 MHz 시스템 도메인의 `o_system_rst`를 2단 동기화 파이프를 거쳐 해제한다.
4. PCLK가 들어오기 시작하면 PCLK 도메인의 `o_system_pclk_rst`도 2단 동기화 파이프를 거쳐 해제한다.
5. 외부 `rst`가 들어오면 시스템 도메인과 PCLK 도메인을 다시 리셋한다.

`rst`는 전체 FPGA 시스템 리셋이다. BTN_C는 이 경로에 연결되지 않으며 카메라 SCCB 설정만 다시 전송한다.

### 3.2 `clock_gen`: VGA tick과 카메라 XCLK 생성

`clock_gen`은 하나의 100 MHz 입력에서 서로 목적이 다른 두 신호를 만든다.

1. `o_tick_25`는 100 MHz 클록 4번마다 한 번만 1이 되는 clock enable이다.
2. VGA 카운터는 계속 100 MHz `clk`에서 동작하지만 `o_tick_25`가 1일 때만 한 픽셀씩 증가한다.
3. 따라서 VGA 픽셀 진행 속도는 25 MHz가 된다.
4. `o_xclk_24`는 MMCM으로 만든 약 22.981 MHz 카메라 기준 클록이다.
5. 출력 이름에는 과거의 `24`가 남아 있지만 실제 주파수는 24 MHz가 아니다.

정확한 XCLK 계산은 4장에서 설명한다.

### 3.3 `vga_decoder`: 640×480 VGA 스캔 좌표 생성

`vga_decoder`는 `hv_counter`와 `timing_decoder`를 묶는다.

1. `hv_counter`가 `o_tick_25`마다 수평 좌표를 0부터 799까지 증가시킨다.
2. 수평 한 줄이 끝나면 수직 좌표를 0부터 520까지 증가시킨다.
3. `timing_decoder`가 현재 좌표에서 HSYNC, VSYNC, display enable을 만든다.
4. x=0..639, y=0..479에서만 display enable이 1이 된다.
5. blanking 구간의 좌표도 `camera_line_bridge`가 다음 라인을 준비하는 시점으로 사용한다.

### 3.4 `top_ov7670`: 카메라 초기화와 RGB565 픽셀 생성

`top_ov7670` 안에는 카메라를 설정하는 경로와 픽셀을 받는 경로가 함께 있다.

#### 3.4.1 `ov7670_sccb_ctrl`

이 모듈은 OV7670 레지스터를 쓰는 초기화 상태기계다.

1. `ov7670_pkg.sv`에 저장된 71개의 레지스터 주소와 값을 앞에서부터 SCCB로 전송한다.
2. 전원 투입 때는 XCLK가 안정될 때까지 약 30 ms 기다린 뒤 COM7 software reset부터 시작한다.
3. COM7 reset 뒤에는 다시 약 30 ms 기다린다.
4. 나머지 레지스터 사이에는 약 1 ms 간격을 둔다.
5. 모든 레지스터를 전송하면 `init_done`을 1로 만든다.
6. BTN_C를 누르면 10 ms 디바운스 후 같은 71개 설정을 처음부터 다시 보낸다.
7. BTN_C 재초기화는 영상 한가운데서 COM7 reset이 걸리지 않도록 다음 VSYNC 상승 경계까지 기다린다.
8. 카메라가 고장 나 VSYNC가 들어오지 않으면 100 ms 뒤 강제로 재초기화를 시작한다.

현재 중요한 카메라 클록 레지스터는 `DBLV=0x4A`, `CLKRC=0x02`, `COM14=0x00`, `SCALING_PCLK_DIV=0xF0`이다.

#### 3.4.2 `ov7670_capture_frontend`

이 모듈은 카메라 PMOD 핀에서 들어오는 PCLK, HREF, VSYNC, D[7:0]을 PCLK 상승 경계에서 IOB 입력 레지스터에 먼저 저장한다. 긴 내부 배선을 통과하기 전에 핀 가까이에서 데이터를 받기 위한 구조다.

SCCB 설정이 끝나기 전에는 캡처를 막고, `init_done`이 들어온 뒤에도 다음 VSYNC가 올 때까지 기다렸다가 완전한 새 프레임부터 캡처를 허용한다. BTN_C 재초기화 도중의 중간 프레임이 링 버퍼에 들어가는 것을 막는다.

#### 3.4.3 `ov7670_memcontroller`

OV7670의 DVP 데이터 버스는 8비트지만 영상 형식은 RGB565 16비트다. 따라서 한 픽셀이 두 번의 PCLK에 걸쳐 들어온다.

1. HREF가 1인 첫 번째 PCLK에서 D[7:0]을 RGB565의 상위 바이트에 저장한다.
2. 두 번째 PCLK에서 D[7:0]을 하위 바이트에 저장한다.
3. 두 바이트가 모두 모였을 때만 write enable을 한 번 발생시킨다.
4. 픽셀 주소는 0부터 307199까지 증가한다.
5. VSYNC와 HREF를 이용해 프레임 시작에서 주소와 바이트 위상을 함께 0으로 맞춘다.

이 출력은 아직 전체 프레임버퍼에 저장되지 않는다. 바로 `camera_line_bridge`로 들어간다.

### 3.5 `camera_line_bridge`: 전체 프레임 대신 최근 64라인만 보관

이 모듈은 PCLK 도메인의 카메라 생산 속도와 100 MHz VGA 도메인의 소비 속도를 연결한다. 내부에는 `camera_line_ring`과 `vga_line_streamer`가 있다.

#### 3.5.1 카메라가 한 라인을 저장하는 과정

1. 카메라에서 들어온 선형 주소를 이용해 현재 x=0..639와 y=0..479를 추적한다.
2. RGB565에서 R, G, B를 각각 4비트씩 뽑아 RGB444 12비트로 줄인다.
3. 현재 라인의 640픽셀을 64개 line bank 중 비어 있는 bank 하나에 쓴다.
4. x=639까지 쓰면 그 라인이 완성된다.
5. 완성된 라인의 frame ID, 원래 y 좌표, 저장 bank 번호를 23비트 descriptor로 만든다.
6. descriptor를 `async_line_fifo`에 넣어 VGA 읽기 도메인으로 넘긴다.

픽셀은 true dual-port BRAM에 있고 descriptor는 async FIFO에 있다. 따라서 카메라는 PCLK로 쓰고 VGA는 100 MHz `clk`로 읽어도 같은 클록을 공유할 필요가 없다.

#### 3.5.2 480라인을 최대 8개 구간으로 흘리는 방식

한 카메라 프레임은 480라인이고 링 버퍼는 한 번에 64라인만 보관한다. 프레임을 메모리 용량 관점에서 보면 다음 8개 구간으로 나뉜다.

1. 구간 0: y=0..63
2. 구간 1: y=64..127
3. 구간 2: y=128..191
4. 구간 3: y=192..255
5. 구간 4: y=256..319
6. 구간 5: y=320..383
7. 구간 6: y=384..447
8. 구간 7: y=448..479

실제 RTL이 64라인을 모두 채운 뒤 한 덩어리로 보내는 것은 아니다. 한 라인이 완성되는 즉시 descriptor가 FIFO로 넘어가고 VGA가 오래된 라인을 읽은 bank를 다시 카메라가 사용한다. 따라서 8개 구간은 메모리 사용 원리를 이해하기 위한 구분이고, 실제 데이터는 라인 단위로 계속 흐르는 sliding window다.

동작을 시간 순서로 보면 다음과 같다.

1. 카메라가 프레임 앞부분을 64개 bank에 순서대로 쓴다.
2. 24라인이 모이면 VGA 읽기가 시작된다.
3. VGA가 y=0 라인을 읽는 동안 카메라는 그 뒤의 라인을 계속 쓴다.
4. VGA가 어떤 bank의 라인을 다 사용하면 FIFO pop으로 그 bank가 다시 비게 된다.
5. 카메라는 비어진 bank를 y=64 이후의 새 라인에 재사용한다.
6. 이 과정을 y=479까지 반복하므로 메모리에는 한 번도 480라인 전체가 존재하지 않는다.
7. 남은 라인이 8개 이하가 되면 `vga_line_streamer`가 아직 쓰지 않은 bank를 읽지 않도록 현재 라인을 한 슬롯 더 유지한다.

#### 3.5.3 전체 프레임버퍼와 메모리 사용량 비교

RGB565 전체 프레임 하나를 저장하면 다음 메모리가 필요하다.

- 640 × 480 × 16 bit = 4915200 bit
- 4915200 bit = 614400 byte = 600 KiB

Basys 3의 XC7A35T block RAM 전체는 1800 Kb이므로 4915.2 Kb짜리 RGB565 프레임 하나도 내부 BRAM에 들어가지 않는다.

현재 라인 링 버퍼는 다음 크기다.

- 640 × 64 × 12 bit = 491520 bit
- 491520 bit = 61440 byte = 60 KiB
- 전체 RGB565 프레임 메모리의 정확히 10%

즉 프레임 전체를 FPGA에 보관하는 대신 PC가 나중에 조립하게 만들어 카메라 영상용 BRAM을 600 KiB에서 60 KiB로 줄였다.

### 3.6 `canvas_pipeline`: 펜을 찾고 그림을 별도 캔버스에 저장

카메라 배경 위에 그린 선은 카메라 링 버퍼에 다시 쓰지 않는다. `canvas_pipeline`이 별도 320×240 캔버스를 관리한다.

1. `camera_to_canvas_sampler`가 640×480 카메라 픽셀 중 짝수 x와 짝수 y만 선택한다.
2. 결과적으로 펜 검출기는 프레임당 320×240 픽셀만 처리한다.
3. `colour_detector`가 RGB565에서 초록색이 다른 색보다 충분히 강한 픽셀을 찾는다.
4. `centroid_accum`이 검출된 픽셀의 x, y 합과 개수를 누적해 펜 중심을 계산한다.
5. `coord_filter`가 최근 5개 좌표를 이동 평균해 손떨림을 줄인다.
6. `brush_draw_engine`이 이전 좌표와 새 좌표 사이를 Bresenham 선으로 연결한다.
7. `circular_brush_renderer`가 각 선 좌표에 원형 브러시 또는 선택한 texture shape를 찍는다.
8. 결과를 `canvas_buffer`의 320×240 BRAM에 저장한다.
9. 캔버스 픽셀은 `{valid, R, G, B}` 4비트라서 색이 있는지와 1비트 RGB 색만 저장한다.
10. VGA가 읽을 때는 source x와 source y를 각각 2로 나눠 캔버스 주소를 만든다.
11. 캔버스 한 픽셀은 최종 640×480 영상의 2×2 영역에 표시된다.

캔버스 크기는 320 × 240 × 4 bit = 307200 bit = 37.5 KiB다. 카메라 64라인 링 60 KiB와 합쳐도 주요 영상 메모리는 97.5 KiB다.

texture enable과 texture shape는 UART 또는 보드 설정에서 `pen_config_controller`, `canvas_pipeline`, `brush_draw_engine`, `circular_brush_renderer`까지 연결되어 있다.

### 3.7 `vga_output_pipeline`: 카메라, 그림, 라인 헤더 합성

이 모듈은 `video_pixel_compositor`와 `vga_transport_header_encoder`를 묶는다.

일반 화면 픽셀의 우선순위는 다음과 같다.

1. 캔버스 valid가 1이면 카메라 대신 캔버스 색을 출력한다.
2. 캔버스가 없고 freeze가 1이면 Python 합성용 키컬러 `0x888`을 출력한다.
3. 캔버스가 없고 paper 모드가 1이면 흰색을 출력한다.
4. 캔버스가 없고 paper 모드가 0이면 카메라 RGB444를 출력한다.
5. display enable 밖에서는 검정색을 출력한다.

라인 헤더 위치에서는 위 결과보다 헤더의 흰색·검정색 비트가 우선한다. 이 헤더가 Python이 전체 프레임을 복구할 수 있게 만드는 핵심이다.

### 3.8 `top_uart`: 영상과 별도로 좌표와 도구 설정 전달

VGA 경로는 640×480 영상만 전달한다. 펜 좌표와 UI 버튼 상태는 UART가 담당한다.

1. FPGA에서 PC로는 카메라 프레임 경계마다 6바이트 패킷을 보낸다.
2. 패킷에는 펜 x, y, texture, eraser, size, RGB, clear, texture shape, paper, freeze 상태가 들어간다.
3. PC에서 FPGA로는 UI에서 선택한 도구 설정을 4바이트 패킷으로 보낸다.
4. baud rate는 115200이고 형식은 8N1이다.

FPGA에서 PC로 보내는 6바이트 순서는 `0xAA`, X[8:1], Y[7:0], control, shape, `0x55`다. PC에서 FPGA로 보내는 4바이트 순서는 `0xA5`, control, shape, `0x5A`다.

### 3.9 `top_button`: 물리 버튼을 한 번의 동작으로 변환

펜 모드, 펜 크기, 지우개 버튼은 누르는 동안 여러 번 튀는 기계식 bounce가 생긴다. `top_button` 안의 `button_debounce` 3개가 각 버튼을 안정화하고 버튼을 한 번 눌렀을 때 한 클록 길이의 pulse 하나만 출력한다.

BTN_C 카메라 재초기화는 `top_button`이 아니라 `ov7670_sccb_ctrl` 안의 별도 디바운스 경로를 사용한다.

### 3.10 `pen_config_controller`: 버튼 설정과 Python 설정을 한 상태로 통합

보드 버튼과 Python UI가 동시에 펜 설정을 바꿀 수 있으므로 최종 설정을 한 모듈이 소유해야 한다.

1. UART 패킷이 들어오면 Python에서 보낸 색, 크기, 지우개, texture, paper, freeze 설정으로 상태를 갱신한다.
2. 보드 버튼 pulse가 들어오면 해당 항목만 토글하거나 다음 값으로 바꾼다.
3. 최종 상태를 canvas pipeline과 UART sender에 동시에 전달한다.
4. clear는 지속 상태가 아니라 한 번만 발생하는 pulse로 전달한다.

## 4. VGA 60 Hz와 카메라 20 fps를 정한 과정

Basys 3의 기본 입력 클록은 100 MHz다. 이 클록에서 VGA용 25 MHz 진행 신호와 OV7670에 공급할 XCLK를 따로 만든다. VGA 주사율과 카메라 프레임률은 같은 값이 아니며, 아래 순서로 각각 결정했다.

### 4.1 VGA는 800×521 전체 타이밍을 25 MHz로 진행한다

화면에 보이는 영역은 640×480이지만 동기 신호와 blanking까지 포함하면 VGA 카운터의 한 프레임은 800×521이다.

1. 수평 전체는 640 active + 16 front porch + 96 sync + 48 back porch = 800 pixel이다.
2. 수직 전체는 480 active + 10 front porch + 2 sync + 29 back porch = 521 line이다.
3. 100 MHz 시스템 클록을 4분주한 25 MHz 속도로 800×521 위치를 모두 순회한다.
4. VGA 주사율은 25000000 ÷ (800 × 521) = 59.980806 Hz다.
5. 정확히 60 Hz에 필요한 픽셀 클록은 60 × 800 × 521 = 25.008 MHz다.

따라서 현재 25 MHz는 정확히 60.000 Hz는 아니지만 오차가 약 -0.032%뿐인 59.981 Hz이고, 모니터와 VGA 캡처카드에서는 사실상 60 Hz로 동작한다.

### 4.2 처음 사용한 카메라 XCLK 25 MHz를 23.9827 MHz로 다시 계산했다

초기 설계는 OV7670 XCLK에도 관례적으로 25 MHz를 넣었다. 그러나 이 프로젝트는 VGA 한 화면에 서로 다른 카메라 라인 240개를 실으므로, 완전한 카메라 프레임 하나를 VGA 화면 두 번에 걸쳐 운반한다. 카메라 목표 프레임률은 VGA 주사율의 절반인 29.990403 fps가 된다.

당시 사용한 OV7670 VGA 타이밍 기준은 가로 784, 세로 510 clock unit이다. 이에 맞춘 이론 XCLK는 다음과 같다.

1. 카메라 목표 fps = 59.980806 ÷ 2 = 29.990403 fps
2. 이론 XCLK = 59.980806 × 784 × 510
3. 이론 XCLK = 23.982725528 MHz

이 값을 만들기 위해 처음 계산한 MMCM 설정은 multiplier 34.625, input divider 5, output divider 28.875였다.

1. 실제 생성 XCLK = 100 MHz × 34.625 ÷ 5 ÷ 28.875
2. 실제 생성 XCLK = 23.982683983 MHz
3. 이론값과의 오차는 약 -1.73 ppm이다.

즉 이름만 약 24 MHz인 임의의 값이 아니라, 800×521 VGA 59.9808 Hz와 카메라 프레임 전달 비율을 기준으로 25 MHz를 23.9827 MHz로 다시 계산한 값이었다.

### 4.3 640×480 링 버퍼가 모든 라인을 안정적으로 받도록 XCLK를 22.980769 MHz로 낮췄다

23.9827 MHz XCLK에서 OV7670은 실측 약 31.30 fps로 동작했지만, 당시 64라인 링 버퍼가 한 프레임의 480라인 중 약 460라인만 안정적으로 받아 소비 속도가 부족했다. 그래서 실제로 처리 가능한 비율 460/480을 XCLK에 적용했다.

1. 보정 목표 XCLK = 23.982725528 × 460 ÷ 480
2. 보정 목표 XCLK = 22.983445298 MHz

현재 `clock_gen`은 multiplier 29.875, input divider 4, output divider 32.500을 사용한다.

1. 현재 XCLK = 100 MHz × 29.875 ÷ 4 ÷ 32.500
2. 현재 XCLK = 22.980769231 MHz
3. 보정 목표와의 차이는 약 -0.002676 MHz, 약 -116 ppm이다.

이 값이 `o_xclk_24`로 출력된다. 포트 이름의 `24`는 과거 이름이고 실제 출력은 약 22.981 MHz다.

### 4.4 XCLK는 유지하고 CLKRC로 PCLK를 낮춰 현재 20 fps를 만들었다

XCLK는 FPGA가 OV7670에 공급하는 센서 기준 클록이다. PCLK는 OV7670이 RGB565 데이터 D[7:0], HREF, VSYNC와 함께 FPGA로 돌려주는 바이트 샘플링 클록이다. RGB565 한 픽셀은 두 바이트이므로 active 영역만 계산해도 프레임당 640 × 480 × 2 = 614400번의 PCLK가 필요하다.

XCLK를 약 22.981 MHz로 정한 뒤에는 XCLK를 다시 바꾸지 않고 OV7670의 `CLKRC` 분주값으로 PCLK와 카메라 fps를 조절했다. 현재 주요 설정은 `DBLV=0x4A`, `CLKRC=0x02`, `COM14=0x00`, `SCALING_PCLK_DIV=0xF0`이다.

현재 레지스터 조합에서 사용하는 근사 계산은 다음과 같다.

1. PCLK ≈ XCLK × 2 ÷ (`CLKRC[5:0]` + 1)
2. `CLKRC=0x02`일 때 계산 PCLK ≈ 22.980769 × 2 ÷ 3
3. 계산 PCLK ≈ 15.320513 MHz
4. 오실로스코프로 측정한 실제 PCLK는 약 15.15 MHz다.
5. 이 상태에서 실제 카메라 프레임률은 약 20 fps다.

blanking을 포함한 현재 센서 타이밍은 실측상 한 프레임에 약 757500 PCLK가 필요하다.

1. 프레임당 PCLK ≈ 15.15 MHz ÷ 20 fps = 757500
2. 예상 카메라 fps ≈ PCLK ÷ 757500
3. PCLK 15.15 MHz이면 약 20.0 fps다.
4. PCLK 18 MHz이면 약 23.8 fps다.
5. PCLK 20 MHz이면 약 26.4 fps다.
6. PCLK 22.98 MHz이면 약 30.3 fps다.

실제 시험에서는 약 18 MHz 설정도 밝은 장면에서 보라색 결점이 다시 나타났고, 약 20 MHz 이상에서는 결점뿐 아니라 BTN_C 재초기화 결과도 불안정해졌다. PCLK 파형 하나가 정상으로 보여도 D[7:0] 여덟 선과 HREF, VSYNC가 같은 PCLK 경계에서 setup·hold 시간을 모두 만족한다는 뜻은 아니다. 그래서 현재 안정 기준은 XCLK 22.980769 MHz를 유지하면서 `CLKRC=0x02`로 PCLK를 실측 약 15.15 MHz까지 낮춘 약 20 fps 설정이다.

XDC의 `cam_pclk` period는 43.515 ns, 약 22.98 MHz로 남겨 두었다. 현재 실측 PCLK 15.15 MHz보다 빠른 조건으로 입력 타이밍을 분석하므로 제약은 보수적이다.

## 5. 64라인 영상이 Python에서 640×480 프레임이 되는 과정

이 부분이 전체 프레임버퍼를 없앨 수 있었던 핵심이다.

### 5.1 FPGA가 한 카메라 라인을 VGA 두 행으로 내보내는 이유

VGA 출력은 약 59.98 fields/s이고 카메라 한 프레임에는 480라인이 있다. 설계는 카메라 한 라인을 VGA의 연속된 두 행 동안 유지한다.

1. 첫 번째 행에는 카메라 또는 캔버스 픽셀을 출력한다.
2. 두 번째 행에도 같은 소스 라인을 출력한다.
3. 두 번째 행의 오른쪽 끝 x=619..639에는 영상 대신 21픽셀 헤더를 출력한다.
4. VGA 캡처 프레임 하나에는 240개의 서로 다른 카메라 라인이 들어간다.
5. 따라서 완전한 480라인 프레임 하나는 최소 두 번의 VGA 캡처에 걸쳐 PC로 전달된다.

VGA 경로의 이론적 완전 프레임 운반 상한은 다음과 같다.

- 59.9808 fields/s × 240 source lines/field = 약 14395 source lines/s
- 14395 ÷ 480 = 약 29.99 complete frames/s

현재 카메라 약 20 fps는 이 전송 상한보다 낮다.

### 5.2 21픽셀 헤더에 들어가는 정보

`vga_transport_header_encoder`는 오른쪽 끝 21픽셀을 흰색 1, 검정색 0으로 사용한다.

1. bit 0..2: 고정 시작 패턴 101
2. bit 3: line valid
3. bit 4..7: frame ID 하위 4비트
4. bit 8..16: 원래 카메라 source y 9비트
5. bit 17..20: frame ID와 source y로 계산한 4비트 checksum

이 헤더가 있으므로 VGA 캡처카드가 프레임 경계를 다시 잡거나 일부 라인이 늦게 도착해도 Python은 화면 위치가 아니라 헤더의 source y를 기준으로 원래 줄을 찾을 수 있다.

### 5.3 Python의 재조립 순서

`air_draw_ui.py`의 `decode_transport_lines`와 `TransportFrameAssembler`가 다음 작업을 한다.

1. DirectShow로 캡처카드를 640×480, 60 fps, MJPG로 연다.
2. 캡처카드가 한 줄 위나 아래로 재동기화될 수 있으므로 짝수 행과 홀수 행의 헤더를 모두 검사한다.
3. 시작 패턴과 checksum이 더 많이 맞는 행 parity를 선택한다.
4. 각 유효 행에서 frame ID, source y, 640픽셀 payload를 꺼낸다.
5. frame ID별로 640×480 NumPy 배열과 480개의 received flag를 만든다.
6. source y가 137이면 payload를 배열의 137번째 행에 넣는 방식으로 원래 위치에 저장한다.
7. 링 버퍼의 8개 구간에서 흘러온 y=0..479 라인이 모두 모이면 received 480개가 전부 1이 된다.
8. 이때만 완성된 프레임을 UI 스레드에 공개한다.
9. 중간 조립 중인 프레임이나 라인이 빠진 프레임은 화면에 표시하지 않는다.
10. 헤더가 덮어쓴 오른쪽 끝과 캡처 경계는 표시 전에 잘라내고 다시 640×480 크기로 보정한다.

정리하면 FPGA의 64라인 BRAM은 현재 흘러가는 작은 창만 저장하고, 600 KiB짜리 완성 프레임을 보관하는 역할은 PC의 NumPy 배열이 담당한다. 이것이 전체 프레임버퍼를 제거하면서도 Python에서 완전한 640×480 영상을 얻는 원리다.

### 5.4 CAPTURE와 SAVE

`CAPTURE`는 전체 카메라 프레임버퍼가 없는 현재 구조에서도 정지 화면 위에 계속 그릴 수 있도록 Python과 RTL이 함께 동작한다.

1. UI가 UART shape 바이트 bit4로 freeze를 요청한다.
2. FPGA는 캔버스 픽셀과 21픽셀 전송 헤더를 그대로 출력하고, 나머지 카메라 픽셀만 RGB444 `0x888`로 치환한다.
3. FPGA가 UART TX shape bit4로 freeze 상태를 에코한다.
4. Python은 freeze 직전의 마지막 라이브 프레임을 배경으로 보관한다.
5. 이후 수신 프레임에서 `0x888` 영역은 고정 배경을 사용하고, 키컬러가 아닌 캔버스 획은 새 영상에서 가져온다.
6. `CAPTURE`를 다시 누르면 키컬러 합성을 끝내고 라이브 영상으로 복귀한다.

`SAVE`는 현재 표시 중인 영상과 FPGA 캔버스 결과를 `python_ui/captures/airdraw_날짜_시간.png`로 저장한다. 툴바와 PC 마커 아이콘, 저장 완료 토스트는 파일에 포함하지 않는다.

freeze 이전에 그린 획은 고정 배경에 포함되므로 freeze 중 CLEAR나 지우개로 지워도 고정 화면에서는 사라지지 않는다. freeze 이후 새로 그린 획은 현재 FPGA 캔버스에서 합성된다.

캡처 속도를 분리해서 확인하려면 `python_ui`에서 다음 명령을 실행한다.

```powershell
.\.venv\Scripts\python.exe .\capture_probe.py --seconds 5
```

출력의 `capture`는 OpenCV가 받은 UVC 프레임 속도, `unique_transport`는 헤더 조합이 달라진 VGA 전송 화면 속도, `complete`는 source y 0..479가 모두 모인 카메라 완성 프레임 속도다.
