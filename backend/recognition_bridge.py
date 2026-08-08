"""Bridge: DB roster  ->  recognition pipeline  ->  DB attendance records.

This is the seam where the two halves meet (docs/03_ARCHITECTURE.md §2, steps
5-8). Given a section and a capture source, it:
  1. loads that section's enrolled embeddings from the DB,
  2. runs the recognise-once-then-track pipeline over the clip,
  3. writes the auto results back and moves the session to 'review'.

Importing `recognition` requires OpenCV; the backend workflow itself does not,
so this module is the only place the two dependency sets meet.
"""
from __future__ import annotations

from typing import List, Tuple

from .db import Database
from .services import AttendanceService


def build_roster_from_db(svc: AttendanceService, section_id: str):
    """Turn DB embeddings into a recognition.Roster (in-memory match structure)."""
    from recognition.roster import Roster  # local import: needs OpenCV stack
    import numpy as np

    roster = Roster()
    for student_id, name, emb in svc.roster_embeddings(section_id):
        roster.add(student_id, name, np.array(emb, dtype=np.float32))
    return roster


def run_session(db: Database, session_id: str, source_spec: str,
                seconds: float = 5.0) -> List[Tuple[str, float]]:
    """Run recognition for an existing session and record the results.

    Returns the list of (student_id, confidence) marked present.
    """
    from recognition.capture import open_source
    from recognition.faces import FaceEngine
    from recognition.pipeline import RecognitionPipeline

    svc = AttendanceService(db)
    sess = db.query_one("SELECT section_id FROM attendance_session WHERE id=?",
                        (session_id,))
    if sess is None:
        raise ValueError(f"Session {session_id} not found")

    roster = build_roster_from_db(svc, sess["section_id"])
    pipeline = RecognitionPipeline(FaceEngine(), roster)

    src = open_source(source_spec)
    try:
        results, _stats = pipeline.run(src, seconds=seconds)
    finally:
        src.release()

    present = [(r.student_id, r.confidence) for r in results if r.status == "present"]
    svc.record_recognition(session_id, present)
    return present
