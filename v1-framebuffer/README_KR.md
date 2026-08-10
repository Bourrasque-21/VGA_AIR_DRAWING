## 동작 방식

**CAPTURE (화면 고정 후 그 위에 그리기)** — FPGA 쪽 구현이 필수였습니다. 그림은 FPGA 안에서 영상과 합성돼 오기 때문에 파이썬에서 화면을 얼리면 새로 그리는 선도 같이 멈추거든요. 그래서 UART RX 패킷의 예약 비트(shape 바이트 bit4)로 FPGA에 freeze 명령을 보내고, FPGA는 **배경 프레임버퍼 쓰기만 정지**합니다. 마커 검출과 캔버스 그리기 경로는 그대로 살아 있어서, 고정된 화면 위에 계속 그려집니다. 다시 누르면 라이브로 복귀. TX 패킷 bit4로 에코되므로 UI 버튼 상태도 실제 FPGA 상태와 항상 일치합니다.

**SAVE** — 순수 파이썬. 클릭하면 현재 영상 프레임(그림 포함, 마커 아이콘·툴바 제외)을 `python_ui\captures\airdraw_날짜_시각.png`로 저장하고 버튼이 초록색으로 잠깐 깜빡입니다.

## 수정 파일

| 파일 | 내용 |
| --- | --- |
| uart_packet_decoder.sv | RX shape 바이트 bit4 → `o_freeze` |
| pen_config_controller.sv | freeze 상태 레지스터 (GUI 전용, 버튼 없음) |
| top_buffer.sv | freeze를 pclk로 2FF 동기화 후 프레임버퍼 write enable 게이팅 |
| uart_packet_sender.sv | TX byte4 bit4에 freeze 에코 |
| top_airDrawing.sv | 배선 |
| air_draw_ui.py | CAPTURE 토글·SAVE 버튼 (PAPER 오른쪽), freeze 파싱/전송, PNG 저장 |
