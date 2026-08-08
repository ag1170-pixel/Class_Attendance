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
        """Return (student_id, name, best_similarity) for the closest enrolled
        student, or (None, None, best) if nothing clears the threshold.

        Matching is scoped to THIS roster only (30-60 faces) -> fast + precise.
        """
        best_sid, best_name, best_sim = None, None, -1.0
        for s in self._students.values():
            for emb in s.embeddings:
                sim = FaceEngine.cosine(embedding, emb)
                if sim > best_sim:
                    best_sid, best_name, best_sim = s.student_id, s.name, sim
        if best_sim >= config.COSINE_MATCH_THRESHOLD:
            return best_sid, best_name, best_sim
        return None, None, best_sim
