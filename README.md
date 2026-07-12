# AVG VGA Draw Project Sources
---

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
* `brush_draw_engine.sv`: 브러쉬 그리기 로직 제어 모듈
* `canvas_buffer.sv`: 화면 픽셀 데이터를 저장하는 캔버스 버퍼
* `colour_detector.sv`: 특정 펜 색상을 디텍팅하는 모듈
* `framebuffer.sv` / `framebuffer_reader.sv`: 카메라 영상 프레임 버퍼 및 읽기 모듈
* `i2c_master.sv`: 카메라 및 센서 설정을 위한 I2C 제어기
* `ov7670_memcontroller.sv`: OV7670 카메라 메모리 제어기
* `ov7670_pkg.sv`: OV7670 관련 상수 정의 패키지 파일
* `ov7670_sccb_ctrl.sv`: SCCB 통신 제어 모듈
* `pen_filter.sv` / `pen_pos_tracker.sv`: 펜 감지 필터 및 위치 추적기
* `upscaleimage.sv`: 이미지 업스케일링 모듈
* `VGA_Decoder.sv`: VGA 신호 생성 모듈

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
  | `sw_blue` | R3 | 펜 필터 파란색 채널 활성화 |
  | `sw_green` | W2 | 펜 필터 초록색 채널 활성화 |
  | `sw_red` | U1 | 펜 필터 빨간색 채널 활성화 |
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
