"""Enrol a student's face (the one-time scan the concept calls for).

Usage:
  # from the Mac webcam (grabs the best frames over a few seconds)
  python -m recognition.enroll --id S001 --name "Aarav Sharma" --source webcam

  # from an image file (or several)
  python -m recognition.enroll --id S001 --name "Aarav Sharma" --image face.jpg

The best-quality face (largest inter-eye distance) is embedded and stored to the
roster. In production this runs on-device (iOS Vision quality gate) and is
consent-gated before any template is written.
"""
from __future__ import annotations

import argparse
import sys
from typing import List, Optional, Tuple

import numpy as np

import cv2

from . import config
from .capture import open_source
from .faces import Face, FaceEngine
from .roster import Roster


def _best_face(engine: FaceEngine, frame) -> Optional[Face]:
    faces = engine.detect(frame)
    if not faces:
        return None
    # Pick the most recognisable face: largest inter-eye distance.
    return max(faces, key=lambda f: f.inter_eye_px)


def enroll_from_source(engine: FaceEngine, spec: str, seconds: float) -> List[Tuple[np.ndarray, float]]:
    src = open_source(spec)
    captured: List[Tuple[np.ndarray, float]] = []
    try:
        for frame in src.frames(max_seconds=seconds):
            face = _best_face(engine, frame)
            if face is None or face.inter_eye_px < config.MIN_INTEREYE_PX:
                continue
            emb = engine.embed(frame, face)
            captured.append((emb, face.inter_eye_px))
    finally:
        src.release()
    return captured


def enroll_from_images(engine: FaceEngine, paths: List[str]) -> List[Tuple[np.ndarray, float]]:
    out: List[Tuple[np.ndarray, float]] = []
    for p in paths:
        frame = cv2.imread(p)
        if frame is None:
            print(f"  ! could not read image: {p}", file=sys.stderr)
            continue
        face = _best_face(engine, frame)
        if face is None:
            print(f"  ! no face found in: {p}", file=sys.stderr)
            continue
        out.append((engine.embed(frame, face), face.inter_eye_px))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Enrol a student's face.")
    ap.add_argument("--id", required=True, help="student id, e.g. S001")
    ap.add_argument("--name", required=True, help="student full name")
    ap.add_argument("--source", help="webcam[:N] | path/to/video | rtsp://...")
    ap.add_argument("--image", nargs="+", help="one or more face image files")
    ap.add_argument("--seconds", type=float, default=4.0)
    ap.add_argument("--keep", type=int, default=3, help="how many best embeddings to store")
    args = ap.parse_args()

    engine = FaceEngine()
    roster = Roster.load()

    if args.image:
        captured = enroll_from_images(engine, args.image)
    elif args.source:
        captured = enroll_from_source(engine, args.source, args.seconds)
    else:
        print("Provide --image or --source", file=sys.stderr)
        return 2

    if not captured:
        print("No usable face captured. Try better lighting / closer to camera.",
              file=sys.stderr)
        return 1

    # Keep the N highest-quality embeddings.
    captured.sort(key=lambda t: t[1], reverse=True)
    for emb, ied in captured[: args.keep]:
        roster.add(args.id, args.name, emb)
    roster.save()

    best_ied = captured[0][1]
    print(f"✓ Enrolled {args.name} ({args.id}) with "
          f"{min(args.keep, len(captured))} template(s). "
          f"Best inter-eye distance: {best_ied:.0f}px "
          f"({'reliable' if best_ied >= config.RELIABLE_INTEREYE_PX else 'usable'}).")
    print(f"  Roster now has {len(roster)} student(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
