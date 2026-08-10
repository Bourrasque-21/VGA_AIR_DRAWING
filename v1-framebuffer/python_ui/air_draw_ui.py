"""
Air Draw Monitor UI (양방향)
- 캡처카드 영상 + UART TX 수신 상태 표시 (FPGA -> PC)
- 툴바 클릭으로 펜 설정 전송 (PC -> FPGA, uart_packet_decoder)

TX 패킷 (FPGA->PC, 6B): [0xAA, X[8:1], Y[7:0], control, texture_shape, 0x55]
RX 패킷 (PC->FPGA, 4B): [0xA5, control, shape, 0x5A]
  control: bit7 tex / bit6 eraser / bit5 size / bit4 R / bit3 G / bit2 B / bit1 clear / bit0 rsv
  shape:   bit2:0 texture_shape / bit3 paper(도화지 모드)
TX shape 바이트도 bit3에 paper 에코 포함.
"""
import math
import threading
import time

import cv2
import numpy as np

# ─────────────── 설정 ───────────────
CAM_INDEX    = 0
CROP_LEFT    = 12      # 왼쪽 노이즈(보라색) 컬럼 폭(px) - 밝아서 자동감지로 안 잡히므로 고정 크롭
SCALE        = 4       # 영상 확대 배율
CALIB_FRAMES = 30      # 검은 테두리 자동 감지에 사용할 프레임 수
BLACK_THR    = 30      # 이 밝기 이하 행/열은 VGA 블랭킹(검정)으로 판정
MARKER_TAU   = 0.06    # 마커 스무딩 시정수(초) - 작을수록 즉각 반응, 클수록 부드러움
COM_PORT     = "COM14" # Basys3 USB-UART 포트. None이면 자동 탐색
BAUD_RATE    = 115200
DEBUG_UART   = True    # 콘솔에 수신 패킷 상태 출력

WINDOW_NAME = "Air Draw Monitor"

# ─────────────── 공유 상태 ───────────────
state = {
    "x": 0, "y": 0,
    "r": False, "g": False, "b": False,
    "eraser": False, "size": False,
    "texture": False, "shape": 0, "paper": False,
    "freeze": False,   # 캡처 모드: FPGA가 배경 프레임버퍼 쓰기를 멈춘 상태
    "clear_ts": 0.0,
    "uart_ok": False,
    "pkt_ts": 0.0,     # 마지막 패킷 수신 시각
}
lock = threading.Lock()

ser_handle = None          # uart_reader가 열어주는 시리얼 핸들 (전송용 공유)
ser_lock = threading.Lock()

TOOL_PEN, TOOL_SPRAY, TOOL_DIAG, TOOL_ERASER = "pen", "spray", "diag", "eraser"


def current_tool(s):
    if s["eraser"]:
        return TOOL_ERASER
    if s["texture"]:
        return TOOL_SPRAY if s["shape"] <= 2 else TOOL_DIAG
    return TOOL_PEN


# ─────────────── PC -> FPGA 패킷 전송 ───────────────
def send_packet(tex, eraser, size, r, g, b, shape, paper=0, freeze=0, clear=False):
    global ser_handle
    if ser_handle is None:
        print("[UART] 전송 불가 - 포트가 열려있지 않음")
        return
    ctrl = ((tex << 7) | (eraser << 6) | (size << 5) |
            (r << 4) | (g << 3) | (b << 2) | ((1 if clear else 0) << 1))
    shape_byte = ((1 if freeze else 0) << 4) | ((1 if paper else 0) << 3) | (shape & 0x07)
    pkt = bytes([0xA5, ctrl & 0xFF, shape_byte, 0x5A])
    try:
        with ser_lock:
            ser_handle.write(pkt)
        if DEBUG_UART:
            print(f"[UART] 송신 ctrl=0b{ctrl:08b} shape={shape} clear={clear}")
    except Exception as e:
        print(f"[UART] 송신 실패: {e}")


def send_from_state(s, **override):
    """현재 표시 상태를 기반으로 일부 필드만 바꿔서 전송"""
    fields = {
        "tex": int(s["texture"]), "eraser": int(s["eraser"]), "size": int(s["size"]),
        "r": int(s["r"]), "g": int(s["g"]), "b": int(s["b"]),
        "shape": s["shape"], "paper": int(s["paper"]),
        "freeze": int(s["freeze"]), "clear": False,
    }
    fields.update(override)
    send_packet(fields["tex"], fields["eraser"], fields["size"],
                fields["r"], fields["g"], fields["b"], fields["shape"],
                paper=fields["paper"], freeze=fields["freeze"], clear=fields["clear"])


# ─────────────── 클릭 처리 ───────────────
hitboxes = []  # (x1, y1, x2, y2, handler) - draw_ui가 매 프레임 갱신


def on_mouse(event, mx, my, flags, param):
    if event != cv2.EVENT_LBUTTONDOWN:
        return
    for x1, y1, x2, y2, handler in hitboxes:
        if x1 <= mx <= x2 and y1 <= my <= y2:
            with lock:
                s = dict(state)
            handler(s)
            return


def click_tool(tool):
    def handler(s):
        if tool == TOOL_PEN:
            send_from_state(s, tex=0, eraser=0)
        elif tool == TOOL_ERASER:
            send_from_state(s, eraser=1)
        elif tool == TOOL_SPRAY:
            shape = s["shape"] if s["shape"] <= 2 else 1
            send_from_state(s, tex=1, eraser=0, shape=shape)
        elif tool == TOOL_DIAG:
            shape = s["shape"] if s["shape"] >= 3 else 3
            send_from_state(s, tex=1, eraser=0, shape=shape)
    return handler


def click_variant(index):
    """index 0=얇게, 1=굵게. 도구별 인코딩(size/shape)을 동시에 맞춰 전송한다."""
    def handler(s):
        tool = current_tool(s)
        if tool == TOOL_SPRAY:
            send_from_state(s, size=index, shape=0 if index == 0 else 2)
        elif tool == TOOL_DIAG:
            send_from_state(s, size=index, shape=3 + index)
        else:  # PEN / ERASER
            send_from_state(s, size=index)
    return handler


def click_color(r, g, b):
    def handler(s):
        send_from_state(s, r=r, g=g, b=b)
    return handler


def click_clear(s):
    send_from_state(s, clear=True)


def click_paper(s):
    send_from_state(s, paper=0 if s["paper"] else 1)


def click_capture(s):
    """캡처 토글: FPGA가 배경 프레임버퍼 쓰기를 멈춰 화면이 고정되고,
    그 위에 계속 그릴 수 있다. 다시 누르면 라이브 영상으로 복귀."""
    send_from_state(s, freeze=0 if s["freeze"] else 1)


save_request = False   # SAVE 클릭 시 True, 메인 루프가 저장 후 False로


def click_save(s):
    global save_request
    save_request = True


# ─────────────── UART 수신 스레드 ───────────────
def uart_reader():
    global ser_handle
    try:
        import serial
        from serial.tools import list_ports
    except ImportError:
        print("[UART] pyserial 미설치 - 'pip install pyserial' 후 재실행하면 상태 연동됩니다")
        return

    while True:
        port = COM_PORT
        if port is None:
            ports = list(list_ports.comports())
            if DEBUG_UART and ports:
                print("[UART] 발견된 포트:", ", ".join(f"{p.device}({p.description})" for p in ports))
            port = ports[0].device if ports else None
        if port is None:
            time.sleep(2)
            continue

        try:
            ser = serial.Serial(port, BAUD_RATE, timeout=0.2)
            print(f"[UART] {port} 연결됨")
            ser_handle = ser
            with lock:
                state["uart_ok"] = True
            buf = bytearray()
            while True:
                buf += ser.read(64)
                while len(buf) >= 6:
                    if buf[0] != 0xAA or buf[5] != 0x55:
                        buf.pop(0)
                        continue
                    pkt = bytes(buf[:6])
                    del buf[:6]
                    ctrl = pkt[3]
                    with lock:
                        state["x"]       = pkt[1] << 1
                        state["y"]       = pkt[2]
                        state["texture"] = bool(ctrl & 0x80)
                        state["eraser"]  = bool(ctrl & 0x40)
                        state["size"]    = bool(ctrl & 0x20)
                        state["r"]       = bool(ctrl & 0x10)
                        state["g"]       = bool(ctrl & 0x08)
                        state["b"]       = bool(ctrl & 0x04)
                        state["shape"]   = pkt[4] & 0x07
                        state["paper"]   = bool(pkt[4] & 0x08)
                        state["freeze"]  = bool(pkt[4] & 0x10)
                        state["pkt_ts"]  = time.time()
                        if ctrl & 0x02:
                            state["clear_ts"] = time.time()
                    if DEBUG_UART and ctrl != getattr(uart_reader, "_last_ctrl", None):
                        uart_reader._last_ctrl = ctrl
                        print(f"[UART] 수신 ctrl=0b{ctrl:08b} shape={pkt[4]} "
                              f"(tex={ctrl >> 7 & 1} eraser={ctrl >> 6 & 1} size={ctrl >> 5 & 1} "
                              f"r={ctrl >> 4 & 1} g={ctrl >> 3 & 1} b={ctrl >> 2 & 1})")
        except Exception as e:
            ser_handle = None
            with lock:
                state["uart_ok"] = False
            print(f"[UART] 연결 끊김/실패 ({e}) - 2초 후 재시도")
            time.sleep(2)


# ─────────────── 그리기 헬퍼 ───────────────
INK       = (68, 60, 52)      # 아이콘 잉크색 (BGR)
BAR_BG    = (249, 247, 245)   # 툴바 배경
HEAD_BG   = (94, 74, 58)      # 상단 헤더 (네이비 톤)
SEL_FILL  = (255, 235, 214)   # 선택 하이라이트 (연블루)
SEL_EDGE  = (235, 152, 61)    # 선택 테두리 (블루)
MUTED     = (170, 165, 160)


def rounded_rect(img, x1, y1, x2, y2, color, r=10):
    cv2.rectangle(img, (x1 + r, y1), (x2 - r, y2), color, -1, cv2.LINE_AA)
    cv2.rectangle(img, (x1, y1 + r), (x2, y2 - r), color, -1, cv2.LINE_AA)
    for cx, cy in ((x1 + r, y1 + r), (x2 - r, y1 + r), (x1 + r, y2 - r), (x2 - r, y2 - r)):
        cv2.circle(img, (cx, cy), r, color, -1, cv2.LINE_AA)


def rounded_rect_outline(img, x1, y1, x2, y2, color, r=10, t=2):
    cv2.ellipse(img, (x1 + r, y1 + r), (r, r), 180, 0, 90, color, t, cv2.LINE_AA)
    cv2.ellipse(img, (x2 - r, y1 + r), (r, r), 270, 0, 90, color, t, cv2.LINE_AA)
    cv2.ellipse(img, (x1 + r, y2 - r), (r, r), 90, 0, 90, color, t, cv2.LINE_AA)
    cv2.ellipse(img, (x2 - r, y2 - r), (r, r), 0, 0, 90, color, t, cv2.LINE_AA)
    cv2.line(img, (x1 + r, y1), (x2 - r, y1), color, t, cv2.LINE_AA)
    cv2.line(img, (x1 + r, y2), (x2 - r, y2), color, t, cv2.LINE_AA)
    cv2.line(img, (x1, y1 + r), (x1, y2 - r), color, t, cv2.LINE_AA)
    cv2.line(img, (x2, y1 + r), (x2, y2 - r), color, t, cv2.LINE_AA)


def draw_icon_pen(img, cx, cy, color):
    cv2.line(img, (cx - 8, cy + 10), (cx + 11, cy - 9), color, 5, cv2.LINE_AA)
    tip = np.array([[cx - 14, cy + 16], [cx - 5, cy + 13], [cx - 11, cy + 7]], np.int32)
    cv2.fillPoly(img, [tip], color, cv2.LINE_AA)


def draw_icon_spray(img, cx, cy, color):
    dots = [(-9, -8, 1), (-2, -12, 1), (6, -9, 1), (-12, 0, 1), (11, -2, 1),
            (-7, 6, 2), (0, -4, 2), (7, 5, 2), (-1, 11, 1), (5, 12, 1),
            (-13, 11, 1), (12, 10, 1), (1, 3, 2)]
    for dx, dy, r in dots:
        cv2.circle(img, (cx + dx, cy + dy), r, color, -1, cv2.LINE_AA)


def draw_icon_diag(img, cx, cy, color):
    # 45도 기운 길쭉한 직사각형 외곽선 (캘리그라피 닙) - PEN과 구분되게 속을 비움
    pts = np.array([[cx + 5, cy - 13], [cx + 13, cy - 5],
                    [cx - 5, cy + 13], [cx - 13, cy + 5]], np.int32)
    cv2.fillPoly(img, [pts], (255, 255, 255), cv2.LINE_AA)
    cv2.polylines(img, [pts], True, color, 2, cv2.LINE_AA)


def draw_icon_eraser(img, cx, cy, color):
    pts = np.array([[cx - 12, cy + 4], [cx - 2, cy - 10],
                    [cx + 12, cy - 1], [cx + 2, cy + 13]], np.int32)
    cv2.fillPoly(img, [pts], (160, 150, 235), cv2.LINE_AA)   # 분홍 지우개 몸통
    cv2.polylines(img, [pts], True, color, 1, cv2.LINE_AA)
    cv2.line(img, (cx - 14, cy + 16), (cx + 14, cy + 16), color, 2, cv2.LINE_AA)


ICON_DRAWERS = {
    TOOL_PEN: draw_icon_pen,
    TOOL_SPRAY: draw_icon_spray,
    TOOL_DIAG: draw_icon_diag,
    TOOL_ERASER: draw_icon_eraser,
}
TOOL_ORDER  = [TOOL_PEN, TOOL_SPRAY, TOOL_DIAG, TOOL_ERASER]
TOOL_LABELS = {TOOL_PEN: "PEN", TOOL_SPRAY: "SPRAY", TOOL_DIAG: "CALIG", TOOL_ERASER: "ERASER"}


def active_thickness(s, tool):
    """현재 도구의 활성 굵기 인덱스 (0=얇게, 1=굵게)"""
    if tool == TOOL_SPRAY:
        return 0 if s["shape"] == 0 else 1
    if tool == TOOL_DIAG:
        return 0 if s["shape"] <= 3 else 1
    return 1 if s["size"] else 0


# 8색 팔레트: (R, G, B) 비트 조합 -> 표시용 BGR
PALETTE = [
    (0, 0, 0, (40, 40, 40)),       # 검정
    (1, 0, 0, (60, 60, 230)),      # 빨강
    (0, 1, 0, (80, 190, 80)),      # 초록
    (0, 0, 1, (230, 120, 60)),     # 파랑
    (1, 1, 0, (60, 210, 240)),     # 노랑
    (1, 0, 1, (200, 80, 230)),     # 마젠타
    (0, 1, 1, (220, 210, 70)),     # 시안
    (1, 1, 1, (250, 250, 250)),    # 흰색
]


last_save_ts = 0.0   # 마지막 이미지 저장 시각 (SAVE 버튼 강조 표시용)


def draw_ui(width, s):
    global hitboxes
    boxes = []
    HEAD_H, BAR_H = 42, 96
    ui = np.full((HEAD_H + BAR_H, width, 3), 255, np.uint8)

    # 헤더
    ui[:HEAD_H] = HEAD_BG
    cv2.putText(ui, "Air Draw", (16, 28), cv2.FONT_HERSHEY_DUPLEX, 0.75,
                (255, 255, 255), 1, cv2.LINE_AA)
    # 초록=패킷 수신 중 / 주황=포트만 열림(데이터 없음) / 빨강=포트 안 열림
    if s["uart_ok"] and time.time() - s["pkt_ts"] < 1.0:
        dot_color, uart_label = (90, 200, 90), "UART"
    elif s["uart_ok"]:
        dot_color, uart_label = (60, 160, 240), "NO DATA"
    else:
        dot_color, uart_label = (80, 80, 230), "UART"
    cv2.circle(ui, (width - 118, HEAD_H // 2), 6, dot_color, -1, cv2.LINE_AA)
    cv2.putText(ui, uart_label, (width - 104, HEAD_H // 2 + 5), cv2.FONT_HERSHEY_SIMPLEX,
                0.5, (230, 230, 230), 1, cv2.LINE_AA)
    # 펜 좌표 (UART 표시등 왼쪽)
    coord = f"X {s['x']:>3}  Y {s['y']:>3}"
    cv2.putText(ui, coord, (width - 268, HEAD_H // 2 + 5), cv2.FONT_HERSHEY_SIMPLEX,
                0.48, (215, 215, 215), 1, cv2.LINE_AA)

    # 툴바 배경
    ui[HEAD_H:] = BAR_BG
    cv2.line(ui, (0, HEAD_H + BAR_H - 1), (width, HEAD_H + BAR_H - 1), (225, 222, 218), 1)

    tool = current_tool(s)
    top = HEAD_H

    # ── 도구 아이콘 4개 ──
    slot_w, x0 = 74, 14
    for i, t in enumerate(TOOL_ORDER):
        cx = x0 + i * slot_w + slot_w // 2
        cy = top + 38
        if t == tool:
            rounded_rect(ui, cx - 28, top + 8, cx + 28, top + 62, SEL_FILL, 12)
            rounded_rect_outline(ui, cx - 28, top + 8, cx + 28, top + 62, SEL_EDGE, 12, 2)
        ICON_DRAWERS[t](ui, cx, cy, INK)
        label_color = SEL_EDGE if t == tool else MUTED
        tw = cv2.getTextSize(TOOL_LABELS[t], cv2.FONT_HERSHEY_SIMPLEX, 0.36, 1)[0][0]
        cv2.putText(ui, TOOL_LABELS[t], (cx - tw // 2, top + 80),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.36, label_color, 1, cv2.LINE_AA)
        boxes.append((cx - 28, top + 8, cx + 28, top + 62, click_tool(t)))

    div_x = x0 + 4 * slot_w + 8
    cv2.line(ui, (div_x, top + 14), (div_x, top + 82), (222, 219, 215), 1)

    # ── 굵기 선택 (얇은 선 / 굵은 선 아이콘, 모든 도구 공통 2단계) ──
    active = active_thickness(s, tool)
    vx = div_x + 18
    for i, line_th in enumerate((2, 6)):
        pw = 52
        y1, y2 = top + 26, top + 54
        if i == active:
            rounded_rect(ui, vx, y1, vx + pw, y2, SEL_FILL, 13)
            rounded_rect_outline(ui, vx, y1, vx + pw, y2, SEL_EDGE, 13, 2)
            lc = SEL_EDGE
        else:
            rounded_rect_outline(ui, vx, y1, vx + pw, y2, (215, 212, 208), 13, 1)
            lc = INK
        ly = (y1 + y2) // 2
        cv2.line(ui, (vx + 12, ly), (vx + pw - 12, ly), lc, line_th, cv2.LINE_AA)
        boxes.append((vx, y1, vx + pw, y2, click_variant(i)))
        vx += pw + 8
    cv2.putText(ui, "SIZE", (div_x + 18, top + 74), cv2.FONT_HERSHEY_SIMPLEX,
                0.34, MUTED, 1, cv2.LINE_AA)

    div2_x = vx + 10
    cv2.line(ui, (div2_x, top + 14), (div2_x, top + 82), (222, 219, 215), 1)

    # ── 색상 팔레트 (8색 중 선택) ──
    cur_bits = (int(s["r"]), int(s["g"]), int(s["b"]))
    sx = div2_x + 24
    cy = top + 38
    for r, g, b, col in PALETTE:
        selected = (r, g, b) == cur_bits and tool != TOOL_ERASER
        cv2.circle(ui, (sx, cy), 11, col, -1, cv2.LINE_AA)
        cv2.circle(ui, (sx, cy), 11, (205, 202, 198), 1, cv2.LINE_AA)  # 흰색 구분용 외곽
        if selected:
            cv2.circle(ui, (sx, cy), 15, SEL_EDGE, 2, cv2.LINE_AA)
        boxes.append((sx - 15, cy - 15, sx + 15, cy + 15, click_color(r, g, b)))
        sx += 33
    px = sx - 10
    cv2.putText(ui, "COLOR", (div2_x + 14, top + 74), cv2.FONT_HERSHEY_SIMPLEX,
                0.34, MUTED, 1, cv2.LINE_AA)

    # ── CLEAR 버튼 ──
    cbx1, cby1, cbx2, cby2 = px + 34, top + 24, px + 116, top + 54
    if time.time() - s["clear_ts"] < 0.8:
        rounded_rect(ui, cbx1, cby1, cbx2, cby2, (210, 210, 250), 13)
        rounded_rect_outline(ui, cbx1, cby1, cbx2, cby2, (60, 60, 230), 13, 2)
        tc = (60, 60, 230)
    else:
        rounded_rect_outline(ui, cbx1, cby1, cbx2, cby2, (150, 145, 200), 13, 1)
        tc = (120, 115, 170)
    tw = cv2.getTextSize("CLEAR", cv2.FONT_HERSHEY_SIMPLEX, 0.44, 1)[0][0]
    cv2.putText(ui, "CLEAR", (cbx1 + (cbx2 - cbx1 - tw) // 2, cby2 - 10),
                cv2.FONT_HERSHEY_SIMPLEX, 0.44, tc, 1, cv2.LINE_AA)
    boxes.append((cbx1, cby1, cbx2, cby2, click_clear))

    # ── PAPER(도화지) 토글 ──
    pbx1, pby1, pbx2, pby2 = cbx2 + 12, top + 24, cbx2 + 94, top + 54
    if s["paper"]:
        rounded_rect(ui, pbx1, pby1, pbx2, pby2, SEL_FILL, 13)
        rounded_rect_outline(ui, pbx1, pby1, pbx2, pby2, SEL_EDGE, 13, 2)
        tc = SEL_EDGE
    else:
        rounded_rect_outline(ui, pbx1, pby1, pbx2, pby2, (215, 212, 208), 13, 1)
        tc = MUTED
    tw = cv2.getTextSize("PAPER", cv2.FONT_HERSHEY_SIMPLEX, 0.44, 1)[0][0]
    cv2.putText(ui, "PAPER", (pbx1 + (pbx2 - pbx1 - tw) // 2, pby2 - 10),
                cv2.FONT_HERSHEY_SIMPLEX, 0.44, tc, 1, cv2.LINE_AA)
    boxes.append((pbx1, pby1, pbx2, pby2, click_paper))

    # ── CAPTURE(화면 고정) 토글 ──
    fbx1, fby1, fbx2, fby2 = pbx2 + 12, top + 24, pbx2 + 106, top + 54
    if s["freeze"]:
        rounded_rect(ui, fbx1, fby1, fbx2, fby2, SEL_FILL, 13)
        rounded_rect_outline(ui, fbx1, fby1, fbx2, fby2, SEL_EDGE, 13, 2)
        tc = SEL_EDGE
    else:
        rounded_rect_outline(ui, fbx1, fby1, fbx2, fby2, (215, 212, 208), 13, 1)
        tc = MUTED
    tw = cv2.getTextSize("CAPTURE", cv2.FONT_HERSHEY_SIMPLEX, 0.44, 1)[0][0]
    cv2.putText(ui, "CAPTURE", (fbx1 + (fbx2 - fbx1 - tw) // 2, fby2 - 10),
                cv2.FONT_HERSHEY_SIMPLEX, 0.44, tc, 1, cv2.LINE_AA)
    boxes.append((fbx1, fby1, fbx2, fby2, click_capture))

    # ── SAVE(이미지 저장) 버튼 ──
    sbx1, sby1, sbx2, sby2 = fbx2 + 12, top + 24, fbx2 + 90, top + 54
    if time.time() - last_save_ts < 0.8:   # 저장 직후 잠깐 강조
        rounded_rect(ui, sbx1, sby1, sbx2, sby2, (214, 245, 214), 13)
        rounded_rect_outline(ui, sbx1, sby1, sbx2, sby2, (70, 170, 70), 13, 2)
        tc = (70, 170, 70)
    else:
        rounded_rect_outline(ui, sbx1, sby1, sbx2, sby2, (215, 212, 208), 13, 1)
        tc = MUTED
    tw = cv2.getTextSize("SAVE", cv2.FONT_HERSHEY_SIMPLEX, 0.44, 1)[0][0]
    cv2.putText(ui, "SAVE", (sbx1 + (sbx2 - sbx1 - tw) // 2, sby2 - 10),
                cv2.FONT_HERSHEY_SIMPLEX, 0.44, tc, 1, cv2.LINE_AA)
    boxes.append((sbx1, sby1, sbx2, sby2, click_save))

    hitboxes = boxes
    return ui


# ─────────────── 펜 위치 마커 (assets/marker_*.png 아이콘 오버레이) ───────────────
import os

ASSET_DIR     = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
MARKER_ICON_H = 84   # 화면에 표시할 아이콘 높이(px)
_marker_icons = {}   # tool -> (RGBA 이미지, (hotspot_x, hotspot_y))


def _load_marker_icons():
    for tool, fname in ((TOOL_PEN, "marker_pen.png"), (TOOL_ERASER, "marker_eraser.png"),
                        (TOOL_DIAG, "marker_diag.png"), (TOOL_SPRAY, "marker_spray.png")):
        path = os.path.join(ASSET_DIR, fname)
        img = cv2.imread(path, cv2.IMREAD_UNCHANGED)
        if img is None or img.shape[2] != 4:
            print(f"[MARKER] 아이콘 로드 실패: {path}")
            continue
        scale = MARKER_ICON_H / img.shape[0]
        img = cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
        # 핫스팟(촉 끝): 지우개는 최하단 중앙, 나머지는 좌하단 끝점
        a = img[:, :, 3]
        ys, xs = np.where(a > 100)
        if tool == TOOL_ERASER:
            yb = ys.max()
            hot = (int(xs[ys > yb - 3].mean()), int(yb))
        else:
            i = int((ys.astype(int) - xs.astype(int)).argmax())
            hot = (int(xs[i]), int(ys[i]))
        _marker_icons[tool] = (img, hot)


def _overlay_rgba(frame, icon, x, y, hot):
    """icon의 hotspot이 (x, y)에 오도록 알파 블렌딩으로 합성."""
    fh, fw = frame.shape[:2]
    ih, iw = icon.shape[:2]
    x0, y0 = x - hot[0], y - hot[1]
    fx0, fy0 = max(x0, 0), max(y0, 0)
    fx1, fy1 = min(x0 + iw, fw), min(y0 + ih, fh)
    if fx1 <= fx0 or fy1 <= fy0:
        return
    roi = frame[fy0:fy1, fx0:fx1]
    ico = icon[fy0 - y0:fy1 - y0, fx0 - x0:fx1 - x0]
    a = ico[:, :, 3:4].astype(np.float32) / 255.0
    roi[:] = (ico[:, :, :3].astype(np.float32) * a +
              roi.astype(np.float32) * (1.0 - a)).astype(np.uint8)


def draw_pen_marker(frame, s, pos=None):
    """찍히는 좌표에 도구 아이콘 커서를 표시. 촉 끝이 정확히 그 좌표에 닿는다.
    pos에 스무딩된 (x, y) 캔버스 좌표를 주면 그 위치를 사용."""
    if time.time() - s["pkt_ts"] > 1.0:   # 패킷이 안 들어오면 위치를 모름
        return
    if not _marker_icons:
        return
    px = s["x"] if pos is None else pos[0]
    py = s["y"] if pos is None else pos[1]
    h, w = frame.shape[:2]
    # 캔버스(320x240) -> 표시 좌표. 영상이 좌우반전이므로 x도 반전.
    mx = int((1.0 - px / 320.0) * w)
    my = int(py / 240.0 * h)
    mx = max(0, min(w - 1, mx))
    my = max(0, min(h - 1, my))

    tool = current_tool(s)
    if tool not in _marker_icons:
        return
    icon, hot = _marker_icons[tool]
    _overlay_rgba(frame, icon, mx, my, hot)


_load_marker_icons()


# ─────────────── 콘텐츠 영역 자동 감지 ───────────────
def detect_content_box(frame):
    """VGA 블랭킹(검정) 테두리를 제외한 실제 영상 영역을 찾는다.
    노이즈 픽셀 몇 개에 속지 않도록, 행/열에 밝은 픽셀이 '충분히 많은' 곳만 콘텐츠로 본다."""
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    bright = gray > BLACK_THR
    cols = np.where(bright.sum(axis=0) > 16)[0]   # 세로로 16px 이상 밝아야 콘텐츠 열
    rows = np.where(bright.sum(axis=1) > 16)[0]
    if len(cols) < 32 or len(rows) < 32:   # 카메라 미시작 등 화면 전체가 어두우면 보류
        return None
    return rows[0], rows[-1] + 1, cols[0], cols[-1] + 1


# ─────────────── 이미지 저장 ───────────────
SAVE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "captures")


def save_image(frame):
    """현재 영상 프레임(그림 포함, 마커/툴바 제외)을 PNG로 저장."""
    global last_save_ts
    os.makedirs(SAVE_DIR, exist_ok=True)
    path = os.path.join(SAVE_DIR, time.strftime("airdraw_%Y%m%d_%H%M%S.png"))
    cv2.imwrite(path, frame)
    last_save_ts = time.time()
    print(f"[SAVE] 저장됨: {path}")


TOAST_SEC = 1.5   # 저장 완료 알림 표시 시간(초)


def draw_save_toast(frame):
    """저장 직후 TOAST_SEC 동안 화면 상단 중앙에 완료 알림을 띄운다."""
    msg = "Download complete!"
    font, fs, th = cv2.FONT_HERSHEY_SIMPLEX, 0.85, 2
    (tw, tht), _ = cv2.getTextSize(msg, font, fs, th)
    w = frame.shape[1]
    pad, ch_r = 24, 14                      # 좌우 여백, 체크 아이콘 반지름
    x1 = (w - tw) // 2 - pad - ch_r * 2 - 12
    x2 = (w + tw) // 2 + pad
    y1, y2 = 24, 24 + tht + 30
    cy = (y1 + y2) // 2
    rounded_rect(frame, x1, y1, x2, y2, (60, 50, 45), 16)
    # 초록 체크 아이콘
    cx = x1 + pad + ch_r
    cv2.circle(frame, (cx, cy), ch_r, (90, 200, 90), -1, cv2.LINE_AA)
    cv2.polylines(frame, [np.array([[cx - 6, cy], [cx - 2, cy + 5], [cx + 6, cy - 5]])],
                  False, (255, 255, 255), 2, cv2.LINE_AA)
    cv2.putText(frame, msg, (cx + ch_r + 12, cy + tht // 2), font, fs,
                (255, 255, 255), th, cv2.LINE_AA)


# ─────────────── 메인 ───────────────
def main():
    global save_request
    threading.Thread(target=uart_reader, daemon=True).start()

    cap = cv2.VideoCapture(CAM_INDEX, cv2.CAP_MSMF)
    if not cap.isOpened():
        cap = cv2.VideoCapture(CAM_INDEX)
    if not cap.isOpened():
        raise RuntimeError("캡처카드를 열 수 없습니다. CAM_INDEX를 0/1/2로 바꿔보세요.")

    cv2.namedWindow(WINDOW_NAME)
    cv2.setMouseCallback(WINDOW_NAME, on_mouse)

    content_box = None   # (y1, y2, x1, x2) - 확정된 크롭 영역
    calib_boxes = []     # 캘리브레이션 중 수집한 프레임별 박스
    marker_pos = None    # 스무딩된 마커 위치 (캔버스 좌표, float)
    last_ts = time.time()

    while True:
        ok, frame = cap.read()
        if not ok:
            continue

        frame = frame[:, CROP_LEFT:]

        # 시작 후 CALIB_FRAMES 동안 검은 테두리를 감지해 크롭 영역 확정.
        # 노이즈에 오염된 한두 프레임에 휘둘리지 않게 좌표별 중앙값 사용.
        # 'c' 키로 언제든 재캘리브레이션 가능.
        if content_box is None:
            box = detect_content_box(frame)
            if box is not None:
                calib_boxes.append(box)
                if len(calib_boxes) >= CALIB_FRAMES:
                    arr = np.array(calib_boxes)
                    content_box = tuple(int(v) for v in np.median(arr, axis=0))
                    print(f"[VIDEO] 콘텐츠 영역 확정: y={content_box[0]}..{content_box[1]}, "
                          f"x={content_box[2]}..{content_box[3]}")

        if content_box is not None:
            y1, y2, x1, x2 = content_box
            frame = frame[y1:y2, x1:x2]

        frame = cv2.flip(frame, 1)
        frame = cv2.resize(frame, None, fx=SCALE, fy=SCALE, interpolation=cv2.INTER_CUBIC)

        with lock:
            s = dict(state)

        # 마커 시간 보간: 좌표는 카메라 프레임(~30fps)마다만 오므로,
        # 화면 프레임마다 목표점을 지수적으로 따라가 띄엄띄엄 점프를 없앤다.
        now = time.time()
        dt = min(now - last_ts, 0.1)
        last_ts = now
        k = 1.0 - math.exp(-dt / MARKER_TAU)
        if marker_pos is None:
            marker_pos = [float(s["x"]), float(s["y"])]
        marker_pos[0] += (s["x"] - marker_pos[0]) * k
        marker_pos[1] += (s["y"] - marker_pos[1]) * k

        # SAVE 버튼: 마커 아이콘이 얹히기 전의 그림만 저장
        if save_request:
            save_request = False
            save_image(frame)

        draw_pen_marker(frame, s, marker_pos)
        if time.time() - last_save_ts < TOAST_SEC:
            draw_save_toast(frame)
        ui = draw_ui(frame.shape[1], s)
        canvas = np.vstack([ui, frame])

        cv2.imshow(WINDOW_NAME, canvas)
        key = cv2.waitKey(1) & 0xFF
        if key == ord('q'):
            break
        if key == ord('c'):   # 크롭 재캘리브레이션
            content_box = None
            calib_boxes = []
            print("[VIDEO] 크롭 재캘리브레이션 시작")

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
