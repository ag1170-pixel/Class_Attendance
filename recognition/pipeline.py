"""The attendance recognition pipeline: recognise once, then track.

Input:  a capture source (webcam now, classroom camera later) + a Roster.
Output: a present/absent list bound to enrolled students, with confidence.

Flow (docs/02_ALGORITHM.md):
  frames -> detect faces -> track (stable id) -> on a GOOD frame, embed + match
  to bind track->student -> aggregate over time -> present/absent.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional

import numpy as np

from . import config
from .capture import CaptureSource
from .faces import FaceEngine
from .roster import Roster
from .tracker import IoUTracker, Track


@dataclass
class AttendanceResult:
    student_id: str
    name: str
    status: str                 # "present" | "absent"
    confidence: float           # best cosine similarity seen
    frames_seen: int
    best_inter_eye_px: float


@dataclass
class RunStats:
    frames_processed: int = 0
    faces_detected: int = 0
    faces_recognizable: int = 0     # cleared the inter-eye pixel gate
    median_inter_eye_px: float = 0.0


class RecognitionPipeline:
    def __init__(self, engine: FaceEngine, roster: Roster):
        self.engine = engine
        self.roster = roster

    def run(
        self,
        source: CaptureSource,
        seconds: float = config.ATTENDANCE_SECONDS,
    ) -> tuple[List[AttendanceResult], RunStats]:
        tracker = IoUTracker()
        stats = RunStats()
        inter_eye_samples: List[float] = []

        for frame in source.frames(max_seconds=seconds):
            stats.frames_processed += 1
            faces = self.engine.detect(frame)
            stats.faces_detected += len(faces)

            pairs = tracker.update(faces)
            for track, face in pairs:
                ied = face.inter_eye_px
                inter_eye_samples.append(ied)

                # QUALITY GATE: only bind identity from a good-enough frame.
                if ied < config.MIN_INTEREYE_PX:
                    continue
                stats.faces_recognizable += 1

                emb = self.engine.embed(frame, face)
                sid, _name, sim = self.roster.match(emb)
                if sid is not None:
                    # Bind / reinforce identity on this track (name resolved from
                    # the roster at aggregation time, so we only store the id).
                    if track.student_id is None or sim > track.best_similarity:
                        track.student_id = sid
                    track.best_similarity = max(track.best_similarity, sim)
                    track.best_inter_eye = max(track.best_inter_eye, ied)
                    track.identity_frames += 1

        if inter_eye_samples:
            stats.median_inter_eye_px = float(np.median(inter_eye_samples))

        return self._aggregate(tracker.tracks), stats

    def _aggregate(self, tracks: List[Track]) -> List[AttendanceResult]:
        # Best evidence per student across all tracks bound to them.
        best: Dict[str, Track] = {}
        for t in tracks:
            if t.student_id is None:
                continue
            if t.identity_frames < config.MIN_FRAMES_PRESENT:
                continue
            cur = best.get(t.student_id)
            if cur is None or t.best_similarity > cur.best_similarity:
                best[t.student_id] = t

        results: List[AttendanceResult] = []
        for s in self.roster.students:
            t = best.get(s.student_id)
            if t is not None:
                results.append(
                    AttendanceResult(
                        student_id=s.student_id,
                        name=s.name,
                        status="present",
                        confidence=round(t.best_similarity, 3),
                        frames_seen=t.identity_frames,
                        best_inter_eye_px=round(t.best_inter_eye, 1),
                    )
                )
            else:
                results.append(
                    AttendanceResult(
                        student_id=s.student_id,
                        name=s.name,
                        status="absent",
                        confidence=0.0,
                        frames_seen=0,
                        best_inter_eye_px=0.0,
                    )
                )
        return results
