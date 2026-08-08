"""Pluggable capture source.

The pipeline never cares WHERE frames come from. `cv2.VideoCapture` already
accepts a webcam index, a file path, or an `rtsp://` URL natively, so one class
covers all three — swapping the demo webcam for the real classroom camera is a
one-line change of the source spec and touches no pipeline code.
"""
from __future__ import annotations

import time
from typing import Iterator, Optional, Union

import cv2

from . import config


class CaptureSource:
    """Yield frames (BGR arrays) from any cv2-openable target."""

    def __init__(self, target: Union[int, str], sample_fps: int = config.SAMPLE_FPS):
        self._cap = cv2.VideoCapture(target)
        if not self._cap.isOpened():
            hint = ""
            if isinstance(target, int):
                hint = ("\nOn macOS the webcam needs camera permission for your terminal: "
                        "System Settings → Privacy & Security → Camera → enable Terminal/iTerm, "
                        "then restart the terminal. Also close any app already using the camera.")
            raise RuntimeError(f"Could not open capture source: {target!r}{hint}")
        self._sample_fps = sample_fps

    def frames(self, max_seconds: Optional[float] = None) -> Iterator["cv2.Mat"]:
        src_fps = self._cap.get(cv2.CAP_PROP_FPS) or 30.0
        stride = max(1, int(round(src_fps / self._sample_fps)))  # process ~sample_fps/s
        start, idx = time.time(), 0
        while True:
            ok, frame = self._cap.read()
            if not ok:
                break
            if idx % stride == 0:
                yield frame
            idx += 1
            if max_seconds is not None and (time.time() - start) >= max_seconds:
                break

    def release(self) -> None:
        self._cap.release()


def open_source(spec: str, sample_fps: int = config.SAMPLE_FPS) -> CaptureSource:
    """'webcam[:N]' -> camera index N (default 0); anything else (path or
    rtsp://...) is passed straight to cv2.VideoCapture."""
    if spec.startswith("webcam"):
        _, _, idx = spec.partition(":")
        return CaptureSource(int(idx) if idx else 0, sample_fps)
    return CaptureSource(spec, sample_fps)
