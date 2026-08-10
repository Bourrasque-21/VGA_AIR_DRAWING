# VGA Draw Project Sources

## 📂 폴더 구조 (Directory Structure)

```text
AGV_PRJ/
├── src/
│   ├── rtl/               # 직접 작성한 RTL 설계 소스코드 (.sv)
│   ├── constraints/       # FPGA 핀 맵 및 물리적 제약사항 (.xdc)
│   └── ip/                # Vivado IP 설정 (.xci)
│       └── clk_wiz_0/
└── README.md              # 프로젝트 구성 설명서 (이 파일)
```

---

## 📄 파일 리스트 (File Details)

### 1. Design RTL (`src/rtl/`)
* `top_VGA.sv`: 최상위 탑 모듈
* `brush_draw_engine.sv`: 스트로크, 선 보간, 브러시 렌더러를 연결하는 상위 모듈
* `brush_stroke_controller.sv`: 프레임 이벤트, Pen Up 및 스트로크 연속성 관리
* `bresenham_interpolator.sv`: Bresenham 선 중심 좌표 생성
* `circular_brush_renderer.sv`: 원형 펜/지우개 마스크 및 Canvas 쓰기 주소 생성
* `canvas_buffer.sv`: 화면 픽셀 데이터를 저장하는 캔버스 버퍼
* `colour_detector.sv`: 특정 펜 색상을 디텍팅하는 모듈
* `framebuffer.sv` / `framebuffer_reader.sv`: 카메라 영상 프레임 버퍼 및 읽기 모듈
* `i2c_master.sv`: 카메라 및 센서 설정을 위한 I2C 제어기
* `ov7670_memcontroller.sv`: OV7670 카메라 메모리 제어기
* `ov7670_pkg.sv`: OV7670 관련 상수 정의 패키지 파일
* `ov7670_sccb_ctrl.sv`: SCCB 통신 제어 모듈
* `pen_filter.sv`: 현재 사용 중인 BBox 중심 검출 및 좌표 평활화 필터
* `pen_pos_tracker.sv`: 비활성 레거시 위치 추적기(파일 전체 주석 처리, 합성 경로 미사용)
* `upscaleimage.sv`: 이미지 업스케일링 모듈
* `VGA_Decoder.sv`: VGA 신호 생성 모듈

### 그리기 엔진 구조

카메라에서 검출한 마커 좌표는 다음 순서로 Canvas 픽셀로 변환됩니다.

```text
colour_detector
    ↓ 녹색 픽셀 검출
bbox_center_accum + coord_filter
    ↓ 프레임별 펜 좌표와 Pen Down/Up
brush_stroke_controller
    ↓ 이번 선의 시작점과 끝점
bresenham_interpolator
    ↓ 시작점과 끝점 사이의 연속된 중심 좌표
circular_brush_renderer
    ↓ 각 중심 좌표 주변의 원형 픽셀과 RAM 쓰기 주소
canvas_buffer
```

#### `brush_stroke_controller`의 역할

`brush_stroke_controller`는 픽셀을 직접 그리는 모듈이 아니라, 카메라의 프레임별 좌표를 하나의 연속된 선 작업으로 변환하는 제어 모듈입니다.

주요 입력:

* `frame_done`: 새로운 프레임의 좌표와 펜 상태가 준비됐음을 알리는 1클럭 신호
* `pen_present`: 현재 프레임에서 마커가 검출됐는지 나타내는 Pen Down/Up 상태
* `X_center`, `Y_center`: 현재 프레임의 필터링된 마커 중심 좌표
* `sw_pen_color`, `sw_eraser`, `sw_size`: 해당 프레임에 적용할 도구 설정

주요 처리:

1. `frame_done`마다 현재 좌표, Pen 상태, 색상과 크기를 `pending_*` 레지스터에 저장합니다.
2. 이전에 완료한 좌표가 유효하면 `이전 좌표 → 현재 좌표`를 선의 시작점과 끝점으로 만듭니다.
3. 처음 검출된 좌표이거나 Pen Up 이후의 좌표라면 시작점과 끝점을 모두 현재 좌표로 설정해 새로운 스트로크를 시작합니다.
4. 렌더러가 바쁜 동안 새 프레임이 들어오면 1단 pending 버퍼에 가장 최신 좌표를 보관합니다.
5. 처리 중 Pen Up이 한 번이라도 들어오면 `break_pending`을 유지해, 이후 LED가 다시 켜졌을 때 이전 위치와 연결되지 않게 합니다.
6. `bresenham_interpolator`가 준비되면 `line_start`와 함께 `line_x0/y0`, `line_x1/y1`을 전달하고, `line_done`이 들어올 때까지 현재 선을 active 상태로 유지합니다.

좌표 처리 예시:

```text
프레임 1: Pen Down, (50, 50)  → (50, 50)에서 새 스트로크 시작
프레임 2: Pen Down, (60, 55)  → (50, 50)에서 (60, 55)까지 선 생성
프레임 3: Pen Up              → 이전 좌표 무효화
프레임 4: Pen Down, (200, 100) → (200, 100)에서 새 스트로크 시작
```

역할 구분:

| 모듈 | 담당하는 작업 | 담당하지 않는 작업 |
| :--- | :--- | :--- |
| `brush_stroke_controller` | Pen Up/Down, 이전·최신 좌표, 선 시작점·끝점, 도구 설정 관리 | 선 내부 좌표 계산, 픽셀 쓰기 |
| `bresenham_interpolator` | 두 좌표 사이의 중심점 보간 | 브러시 모양, 색상, RAM 주소 계산 |
| `circular_brush_renderer` | 원형 마스크, 화면 경계 검사, RAM 주소와 데이터 생성 | 스트로크 연결 여부와 선 보간 |
| `canvas_buffer` | 최종 그리기 픽셀 저장 | 좌표 추적과 브러시 모양 계산 |

### 비활성 레거시 RTL

* `src/rtl/pen_pos_tracker.sv`
  * 현재 `top_VGA` 및 `canvas_buffer_top`에서 인스턴스되지 않습니다.
  * 검출된 녹색 픽셀 중 마지막 좌표를 대표 위치로 저장하던 이전 구현입니다.
  * 현재 설계는 `pen_filter.sv`의 `bbox_center_accum`과 `coord_filter`를 사용합니다.
  * 비교 및 참고를 위해 파일은 유지하되 합성되지 않도록 전체를 주석 처리했습니다.

### 2. Constraints (`src/constraints/`)
* `Basys-3-Master.xdc`: Basys3 보드 핀 레이아웃 제약조건 파일

  #### 🎛️ 물리적 핀 맵 정보 (Switches & Buttons)

  ##### 스위치 (Switches)
  | 포트 이름 (Port Name) | 패키지 핀 (Pin) | 기능 설명 |
  | :--- | :--- | :--- |
  | `sw_paint_blue` | V17 | 그리기 파란색 브러쉬 활성화 |
  | `sw_paint_green` | V16 | 그리기 초록색 브러쉬 활성화 |
  | `sw_paint_red` | W16 | 그리기 빨간색 브러쉬 활성화 |
  | `sw_eraser` | W17 | 지우개 모드 활성화 |
  | `sw_size` | W15 | 브러쉬 크기 변경 스위치 |
  | `sw_blue` | R3 | 필터 파란색 채널 활성화 |
  | `sw_green` | W2 | 필터 초록색 채널 활성화 |
  | `sw_red` | U1 | 필터 빨간색 채널 활성화 |
  | `sw_gray` | T1 | 그레이스케일 모드 활성화 |
  | `sw_upscale` | R2 | 이미지 업스케일링 모드 활성화 |

  ##### 버튼 (Buttons)
  | 포트 이름 (Port Name) | 패키지 핀 (Pin) | 물리 위치 (Basys3) | 기능 설명 |
  | :--- | :--- | :--- | :--- |
  | `reset` | U18 | Center | 시스템 리셋 |
  | `start_btn` | T18 | Up | 카메라 수신 및 그리기 시작 |
  | `clear_btn` | T17 | Right | 화면 캔버스 클리어(초기화) |

### 3. IP Catalog Configuration (`src/ip/`)
* `clk_wiz_0/clk_wiz_0.xci`: 시스템 클럭 생성을 위한 Clocking Wizard IP 설정 정보

---
