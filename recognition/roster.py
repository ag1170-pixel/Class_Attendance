"""Enrolled-student templates (the prototype's stand-in for the DB face_template
table). Each student has one or more L2-normalized embeddings stored on disk.

In production these live in Postgres/pgvector, encrypted, consent-gated
(docs/03_ARCHITECTURE.md §3-4). The in-memory/matching logic is identical.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

import numpy as np

from . import config
from .faces import FaceEngine


@dataclass
class Student:
    student_id: str
    name: str
    embeddings: List[np.ndarray] = field(default_factory=list)


class Roster:
    """Holds the enrolled students for ONE class section and matches against them."""

    def __init__(self):
        self._students: Dict[str, Student] = {}

    # ── persistence ──────────────────────────────────────────────────────────
    def add(self, student_id: str, name: str, embedding: np.ndarray) -> None:
        s = self._students.get(student_id)
        if s is None:
            s = Student(student_id=student_id, name=name)
            self._students[student_id] = s
        s.embeddings.append(embedding.astype(np.float32))

    def save(self, path=None) -> None:
        path = path or (config.TEMPLATES_DIR / "roster.json")
        payload = {
            sid: {
                "name": s.name,
                "embeddings": [e.tolist() for e in s.embeddings],
            }
            for sid, s in self._students.items()
        }
        with open(path, "w") as f:
            json.dump(payload, f)

    @classmethod
    def load(cls, path=None) -> "Roster":
        path = path or (config.TEMPLATES_DIR / "roster.json")
        r = cls()
        if not path.exists():
            return r
        with open(path) as f:
            payload = json.load(f)
        for sid, rec in payload.items():
            for emb in rec["embeddings"]:
                r.add(sid, rec["name"], np.array(emb, dtype=np.float32))
        return r

    # ── matching ─────────────────────────────────────────────────────────────
    @property
    def students(self) -> List[Student]:
        return list(self._students.values())

    def __len__(self) -> int:
        return len(self._students)

    def match(self, embedding: np.ndarray) -> Tuple[Optional[str], Optional[str], float]:
        """Closest enrolled student above the auto-present threshold, else
        (None, None, best). Kept for simple callers; the pipeline uses
        match_detailed() for the dual-threshold + margin rule."""
        sid, name, s1, _s2 = self.match_detailed(embedding)
        if s1 >= config.COSINE_MATCH_HIGH:
            return sid, name, s1
        return None, None, s1

    def match_detailed(self, embedding: np.ndarray):
        """Return (best_sid, best_name, s1, s2): the best-matching student's
        score s1 and the runner-up student's score s2 (for the margin test).
        Matching is scoped to THIS roster only (30-60 faces) -> fast + precise.
        """
        # Best cosine per student (across their templates).
        per_student = [
            (s.student_id, s.name,
             max((FaceEngine.cosine(embedding, e) for e in s.embeddings), default=-1.0))
            for s in self._students.values()
        ]
        if not per_student:
            return None, None, -1.0, -1.0
        per_student.sort(key=lambda t: t[2], reverse=True)
        sid, name, s1 = per_student[0]
        s2 = per_student[1][2] if len(per_student) > 1 else -1.0
        return sid, name, s1, s2
