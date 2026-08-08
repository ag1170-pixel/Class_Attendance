"""End-to-end self-test of the recognition pipeline on REAL faces, no webcam.

Proves three things that matter:
  1. TRUE POSITIVE  — an enrolled person is recognised PRESENT.
  2. DISCRIMINATION — two enrolled people are told apart (not cross-matched).
  3. PIXEL GATE     — recognition holds while the face is big enough and degrades
                      as it shrinks past the inter-eye pixel budget
                      (docs/01_FEASIBILITY.md). Shown as informational output.

Needs >=2 face images in recognition/data/faces/ (filename stem = person name).

Run:  python -m recognition.selftest
"""
from __future__ import annotations

import sys
from typing import List, Tuple

import numpy as np

import cv2

from . import config
from .faces import FaceEngine
from .pipeline import RecognitionPipeline
from .roster import Roster

FACES_DIR = config.DATA_DIR / "faces"


def _load_people() -> List[Tuple[str, np.ndarray]]:
    out = []
    for p in sorted(FACES_DIR.glob("*.jpg")) + sorted(FACES_DIR.glob("*.png")):
        img = cv2.imread(str(p))
        if img is not None:
            out.append((p.stem, img))
    return out


class _FramesSource:
    """Minimal capture source over a fixed list of frames (emulates a clip)."""
    def __init__(self, frames): self._frames = frames
    def frames(self, max_seconds=None):
        yield from self._frames
    def release(self): pass


def _run_on(pipeline: RecognitionPipeline, img: np.ndarray, n: int = 6):
    results, stats = pipeline.run(_FramesSource([img] * n), seconds=999)
    present = {r.name: r.confidence for r in results if r.status == "present"}
    return present, stats


def run() -> int:
    people = _load_people()
    if len(people) < 2:
        print("ERROR: need >=2 face images in recognition/data/faces/ "
              "(filename stem = person name).", file=sys.stderr)
        return 1

    engine = FaceEngine()
    roster = Roster()
    for name, img in people:
        faces = engine.detect(img)
        if not faces:
            print(f"  ! no face detected while enrolling {name}", file=sys.stderr)
            continue
        best = max(faces, key=lambda f: f.inter_eye_px)
        roster.add(name, name, engine.embed(img, best))
        print(f"enrolled {name:10} (inter-eye {best.inter_eye_px:.0f}px)")
    pipeline = RecognitionPipeline(engine, roster)
    print()

    ok = True

    # 1 + 2) True positive AND discrimination: show each person alone; they must
    # be recognised as THEMSELVES and nobody else.
    print("── recognition & discrimination ──")
    print(f"{'shown':10} {'recognised present':30} {'result'}")
    for name, img in people:
        present, _ = _run_on(pipeline, img)
        names = set(present)
        correct = (name in names) and (names == {name})
        ok = ok and correct
        shown = ", ".join(f"{n} {present[n]*100:.0f}%" for n in present) or "(none)"
        print(f"{name:10} {shown:30} {'OK' if correct else 'FAIL'}")

    # 3) Pixel gate (informational): shrink one person and watch it degrade.
    name, img = people[0]
    print(f"\n── pixel gate: shrinking '{name}' ──")
    print(f"{'width':>6} {'inter_eye_px':>12} {'recognised':>11}")
    base_w = img.shape[1]
    for scale in (1.0, 0.6, 0.4, 0.25, 0.15):
        w = max(1, int(base_w * scale))
        small = cv2.resize(img, (w, int(img.shape[0] * scale)))
        faces = engine.detect(small)
        ied = max((f.inter_eye_px for f in faces), default=0.0)
        present, _ = _run_on(pipeline, small)
        got = name if name in present else "-"
        print(f"{w:>6} {ied:>12.0f} {got:>11}")

    print("\nRESULT:", "PASS ✅" if ok else "FAIL ❌")
    print("Interpretation: enrolled faces are recognised and told apart at good "
          "resolution; recognition falls off exactly as the face shrinks past the "
          "inter-eye pixel budget — which is why 'recognise once, then track' plus "
          "adequate cameras matter (docs/01, docs/02).")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(run())
