"""A lightweight IoU tracker — the prototype stand-in for ByteTrack/BoT-SORT.

Its only job is to keep a stable `track_id` on each person across sampled
frames, so an identity recognised in ONE good frame carries through frames where
the face is small, turned, or briefly hidden. That is the whole point of
"recognise once, then track" (docs/02_ALGORITHM.md).
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import List, Optional

import numpy as np

from . import config
from .faces import Face


def _iou(a: np.ndarray, b: np.ndarray) -> float:
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    ax2, ay2, bx2, by2 = ax + aw, ay + ah, bx + bw, by + bh
    ix1, iy1 = max(ax, bx), max(ay, by)
    ix2, iy2 = min(ax2, bx2), min(ay2, by2)
    iw, ih = max(0.0, ix2 - ix1), max(0.0, iy2 - iy1)
    inter = iw * ih
    union = aw * ah + bw * bh - inter + 1e-8
    return inter / union


@dataclass
class Track:
    track_id: int
    bbox: np.ndarray
    age: int = 0                       # frames since last seen
    # identity binding, filled once a good-quality face is recognised
    student_id: Optional[str] = None
    best_similarity: float = 0.0
    best_inter_eye: float = 0.0
    identity_frames: int = 0           # frames the identity was confirmed


class IoUTracker:
    def __init__(self):
        self._tracks: List[Track] = []
        self._next_id = 1

    @property
    def tracks(self) -> List[Track]:
        return self._tracks

    def update(self, faces: List[Face]) -> List[tuple]:
        """Associate detections to tracks. Returns [(track, face), ...]."""
        for t in self._tracks:
            t.age += 1

        pairs: List[tuple] = []
        used = set()
        # Greedy IoU association (good enough for seated, low-motion scenes).
        for face in faces:
            best_t, best_iou = None, config.IOU_MATCH_THRESHOLD
            for t in self._tracks:
                if t.track_id in used:
                    continue
                score = _iou(t.bbox, face.bbox)
                if score >= best_iou:
                    best_t, best_iou = t, score
            if best_t is None:
                best_t = Track(track_id=self._next_id, bbox=face.bbox)
                self._next_id += 1
                self._tracks.append(best_t)
            best_t.bbox = face.bbox
            best_t.age = 0
            used.add(best_t.track_id)
            pairs.append((best_t, face))

        # Retire stale tracks.
        self._tracks = [t for t in self._tracks if t.age <= config.MAX_TRACK_AGE]
        return pairs
