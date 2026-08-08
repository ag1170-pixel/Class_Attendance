"""Download the YuNet + SFace ONNX models from the OpenCV Zoo.

Small (~a few MB total). Run once:  python -m recognition.download_models
"""
from __future__ import annotations

import sys
import urllib.request

from . import config

MODELS = {
    config.FACE_DETECT_MODEL: (
        "https://github.com/opencv/opencv_zoo/raw/main/models/"
        "face_detection_yunet/face_detection_yunet_2023mar.onnx"
    ),
    config.FACE_RECOG_MODEL: (
        "https://github.com/opencv/opencv_zoo/raw/main/models/"
        "face_recognition_sface/face_recognition_sface_2021dec.onnx"
    ),
}


def _download(url: str, dest) -> None:
    print(f"↓ {dest.name}  <-  {url}")
    with urllib.request.urlopen(url) as r, open(dest, "wb") as f:
        f.write(r.read())
    print(f"  saved {dest.stat().st_size/1024:.0f} KB")


def main() -> int:
    for dest, url in MODELS.items():
        if dest.exists() and dest.stat().st_size > 0:
            print(f"✓ {dest.name} already present")
            continue
        try:
            _download(url, dest)
        except Exception as e:  # noqa: BLE001
            print(f"ERROR downloading {dest.name}: {e}", file=sys.stderr)
            return 1
    print("All models ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
