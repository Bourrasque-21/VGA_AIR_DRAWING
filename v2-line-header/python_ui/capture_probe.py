"""Measure the local 640x480 VGA transport and reconstruction rates."""

import argparse
import time

import cv2

from air_draw_ui import TransportFrameAssembler, decode_transport_lines


def fourcc_text(value):
    code = int(value)
    return "".join(chr((code >> (8 * index)) & 0xFF) for index in range(4))


def open_capture(index, backend_name):
    backends = {
        "dshow": getattr(cv2, "CAP_DSHOW", cv2.CAP_ANY),
        "msmf": getattr(cv2, "CAP_MSMF", cv2.CAP_ANY),
        "any": cv2.CAP_ANY,
    }
    capture = cv2.VideoCapture(index, backends[backend_name])
    capture.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    capture.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    capture.set(cv2.CAP_PROP_FPS, 60)
    capture.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
    capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    return capture


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--backend", choices=("dshow", "msmf", "any"),
                        default="dshow")
    parser.add_argument("--seconds", type=float, default=5.0)
    args = parser.parse_args()

    capture = open_capture(args.camera, args.backend)
    if not capture.isOpened():
        raise SystemExit(f"camera {args.camera} could not be opened")

    assembler = TransportFrameAssembler()
    try:
        for _ in range(10):
            if not capture.read()[0]:
                raise SystemExit("capture read failed during warm-up")

        started = time.perf_counter()
        received = unique_transport = marker_errors = valid_lines = completed = 0
        last_signature = None
        shape = None

        while time.perf_counter() - started < args.seconds:
            ok, frame = capture.read()
            if not ok or frame is None:
                continue

            received += 1
            shape = frame.shape
            lines = decode_transport_lines(frame)
            valid_lines += len(lines)
            if not lines:
                marker_errors += 1
                continue

            signature = tuple((frame_id, line_y) for frame_id, line_y, _ in lines)
            if signature != last_signature:
                unique_transport += 1
            last_signature = signature

            if assembler.push(lines) is not None:
                completed += 1

        elapsed = time.perf_counter() - started
        if shape is None:
            raise SystemExit("no frames received")

        print(
            f"backend={args.backend} actual={shape[1]}x{shape[0]} "
            f"reported_fps={capture.get(cv2.CAP_PROP_FPS):.3f} "
            f"fourcc={fourcc_text(capture.get(cv2.CAP_PROP_FOURCC))!r}"
        )
        print(f"capture={received / elapsed:.2f}fps frames={received} elapsed={elapsed:.2f}s")
        print(
            f"unique_transport={unique_transport / elapsed:.2f}fps "
            f"valid_lines={valid_lines / elapsed:.0f}/s "
            f"complete={completed / elapsed:.2f}fps marker_errors={marker_errors}"
        )
    finally:
        capture.release()


if __name__ == "__main__":
    main()
