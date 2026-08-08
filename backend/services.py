"""Service layer — the attendance workflow brain (docs/03_ARCHITECTURE.md §2).

Pure Python over the SQLite data layer, so it's fully testable without a server.
The optional FastAPI layer (api.py) is a thin wrapper over these functions.

Security properties enforced here:
  • RBAC — a teacher may only trigger attendance for their OWN section.
  • Consent gating — no face_template is written without an active consent row.
  • Time-window — a trigger is only valid during the section's scheduled slot.
  • Audit — every mark, override, and submit is written to audit_log.
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime
from typing import List, Optional, Tuple

from .db import Database, new_id, pack_embedding, unpack_embedding


class AuthorizationError(Exception):
    pass


class ConsentError(Exception):
    pass


class WorkflowError(Exception):
    pass


@dataclass
class ReviewRow:
    student_id: str
    register_no: str
    full_name: str
    status: str            # present | absent
    source: str            # auto | manual_override
    confidence: Optional[float]


class AttendanceService:
    MODEL_VERSION = "sface-2021dec"

    def __init__(self, db: Database):
        self.db = db

    # ── audit ────────────────────────────────────────────────────────────────
    def _audit(self, actor: Optional[str], action: str, entity: str,
               entity_id: Optional[str], detail: Optional[dict] = None) -> None:
        self.db.execute(
            "INSERT INTO audit_log(id, actor_user_id, action, entity, entity_id, detail)"
            " VALUES (?,?,?,?,?,?)",
            (new_id(), actor, action, entity, entity_id,
             json.dumps(detail) if detail else None),
        )

    # ── enrollment (consent-gated) ───────────────────────────────────────────
    def grant_consent(self, student_id: str, policy_version: str,
                      granted_by: Optional[str] = None) -> str:
        cid = new_id()
        self.db.execute(
            "INSERT INTO consent(id, student_id, policy_version, granted_by)"
            " VALUES (?,?,?,?)",
            (cid, student_id, policy_version, granted_by),
        )
        self._audit(granted_by, "consent.grant", "student", student_id,
                    {"policy_version": policy_version})
        return cid

    def revoke_consent(self, student_id: str, actor: Optional[str] = None) -> None:
        self.db.execute(
            "UPDATE consent SET revoked_at = datetime('now')"
            " WHERE student_id = ? AND revoked_at IS NULL",
            (student_id,),
        )
        # Revoking consent deactivates the biometric templates.
        self.db.execute(
            "UPDATE face_template SET is_active = 0 WHERE student_id = ?",
            (student_id,),
        )
        self._audit(actor, "consent.revoke", "student", student_id)

    def _active_consent(self, student_id: str) -> Optional[str]:
        row = self.db.query_one(
            "SELECT id FROM consent WHERE student_id = ? AND revoked_at IS NULL"
            " ORDER BY granted_at DESC LIMIT 1",
            (student_id,),
        )
        return row["id"] if row else None

    def enroll_face(self, student_id: str, embedding: List[float],
                    quality_score: float = 1.0) -> str:
        """Store a face template — ONLY if the student has active consent."""
        consent_id = self._active_consent(student_id)
        if consent_id is None:
            raise ConsentError(
                f"No active consent for student {student_id}; cannot enroll biometrics."
            )
        tid = new_id()
        self.db.execute(
            "INSERT INTO face_template"
            "(id, student_id, embedding, model_version, quality_score, consent_id)"
            " VALUES (?,?,?,?,?,?)",
            (tid, student_id, pack_embedding(embedding), self.MODEL_VERSION,
             quality_score, consent_id),
        )
        self._audit(None, "enroll.face", "student", student_id,
                    {"template_id": tid, "quality": quality_score})
        return tid

    # ── roster export for the recognition service ────────────────────────────
    def roster_embeddings(self, section_id: str) -> List[Tuple[str, str, List[float]]]:
        """(student_id, full_name, embedding) for every enrolled+consented student
        in the section. This is what the recognition service matches against."""
        rows = self.db.query(
            "SELECT s.id AS sid, s.full_name AS name, f.embedding AS emb"
            " FROM section_roster sr"
            " JOIN student s        ON s.id = sr.student_id"
            " JOIN face_template f  ON f.student_id = s.id AND f.is_active = 1"
            " WHERE sr.section_id = ?",
            (section_id,),
        )
        return [(r["sid"], r["name"], unpack_embedding(r["emb"])) for r in rows]

    # ── schedule ─────────────────────────────────────────────────────────────
    def list_sections(self, teacher_id: str) -> List[dict]:
        """Sections this teacher owns, for the schedule screen."""
        rows = self.db.query(
            "SELECT sec.id AS id, c.code AS code, c.title AS title, r.code AS room,"
            "       sch.start_time AS start, sch.end_time AS end"
            " FROM section sec"
            " JOIN course c ON c.id = sec.course_id"
            " JOIN room r   ON r.id = sec.room_id"
            " LEFT JOIN schedule sch ON sch.section_id = sec.id"
            " WHERE sec.teacher_id = ?"
            " ORDER BY sch.start_time",
            (teacher_id,),
        )
        return [
            {"id": r["id"], "course_code": r["code"], "course_title": r["title"],
             "room_code": r["room"], "start_time": r["start"] or "",
             "end_time": r["end"] or ""}
            for r in rows
        ]

    # ── session lifecycle ────────────────────────────────────────────────────
    def _assert_teacher_owns_section(self, teacher_id: str, section_id: str) -> "sqlite3.Row":  # noqa: F821
        sec = self.db.query_one("SELECT * FROM section WHERE id = ?", (section_id,))
        if sec is None:
            raise WorkflowError(f"Section {section_id} not found")
        if sec["teacher_id"] != teacher_id:
            raise AuthorizationError(
                f"Teacher {teacher_id} does not own section {section_id}"
            )
        return sec

    def _within_scheduled_window(self, section_id: str, when: datetime) -> bool:
        rows = self.db.query(
            "SELECT day_of_week, start_time, end_time FROM schedule WHERE section_id = ?",
            (section_id,),
        )
        if not rows:
            return True  # no schedule defined -> don't block (prototype)
        dow = when.weekday()
        hm = when.strftime("%H:%M")
        for r in rows:
            if r["day_of_week"] == dow and r["start_time"] <= hm <= r["end_time"]:
                return True
        return False

    def create_session(self, teacher_id: str, section_id: str,
                       capture_path: str = "webcam",
                       enforce_schedule: bool = False) -> str:
        """Teacher taps 'Take Attendance'. RBAC + optional time-window enforced."""
        sec = self._assert_teacher_owns_section(teacher_id, section_id)
        if enforce_schedule and not self._within_scheduled_window(section_id, datetime.now()):
            raise WorkflowError("Trigger outside the scheduled class window")

        cam = self.db.query_one(
            "SELECT id FROM camera WHERE room_id = ? AND is_active = 1 LIMIT 1",
            (sec["room_id"],),
        )
        sid = new_id()
        self.db.execute(
            "INSERT INTO attendance_session"
            "(id, section_id, teacher_id, room_id, camera_id, capture_path, status)"
            " VALUES (?,?,?,?,?,?, 'processing')",
            (sid, section_id, teacher_id, sec["room_id"],
             cam["id"] if cam else None, capture_path),
        )
        self._audit(teacher_id, "session.create", "attendance_session", sid,
                    {"section_id": section_id, "capture_path": capture_path})
        return sid

    def record_recognition(self, session_id: str,
                           present: List[Tuple[str, float]]) -> None:
        """Write auto results: `present` = [(student_id, confidence), ...].
        Everyone else on the roster is auto-marked absent. Status -> review."""
        sess = self.db.query_one(
            "SELECT * FROM attendance_session WHERE id = ?", (session_id,))
        if sess is None:
            raise WorkflowError(f"Session {session_id} not found")

        present_map = dict(present)
        roster = self.db.query(
            "SELECT student_id FROM section_roster WHERE section_id = ?",
            (sess["section_id"],),
        )
        for r in roster:
            sid = r["student_id"]
            is_present = sid in present_map
            self.db.execute(
                "INSERT INTO attendance_record"
                "(id, session_id, student_id, status, source, confidence, detected_at)"
                " VALUES (?,?,?,?, 'auto', ?, ?)"
                " ON CONFLICT(session_id, student_id) DO UPDATE SET"
                "   status=excluded.status, source='auto',"
                "   confidence=excluded.confidence, detected_at=excluded.detected_at",
                (new_id(), session_id, sid,
                 "present" if is_present else "absent",
                 present_map.get(sid), datetime.now().isoformat() if is_present else None),
            )
        self.db.execute(
            "UPDATE attendance_session SET status='review' WHERE id=?", (session_id,))
        self._audit(sess["teacher_id"], "session.recognized", "attendance_session",
                    session_id, {"present": len(present_map), "roster": len(roster)})

    def override_record(self, session_id: str, student_id: str, status: str,
                        actor: str) -> None:
        """Teacher corrects a result on the review screen."""
        if status not in ("present", "absent"):
            raise WorkflowError("status must be present|absent")
        self.db.execute(
            "UPDATE attendance_record SET status=?, source='manual_override'"
            " WHERE session_id=? AND student_id=?",
            (status, session_id, student_id),
        )
        self._audit(actor, "record.override", "attendance_record",
                    f"{session_id}:{student_id}", {"status": status})

    def submit_session(self, session_id: str, actor: str) -> None:
        sess = self.db.query_one(
            "SELECT status FROM attendance_session WHERE id=?", (session_id,))
        if sess is None:
            raise WorkflowError("Session not found")
        if sess["status"] != "review":
            raise WorkflowError(f"Session must be in 'review' (is '{sess['status']}')")
        self.db.execute(
            "UPDATE attendance_session SET status='submitted' WHERE id=?", (session_id,))
        self._audit(actor, "session.submit", "attendance_session", session_id)

    # ── review view ──────────────────────────────────────────────────────────
    def get_review(self, session_id: str) -> List[ReviewRow]:
        rows = self.db.query(
            "SELECT s.id AS sid, s.register_no AS reg, s.full_name AS name,"
            "       r.status AS st, r.source AS src, r.confidence AS conf"
            " FROM attendance_record r"
            " JOIN student s ON s.id = r.student_id"
            " WHERE r.session_id = ?"
            " ORDER BY s.register_no",
            (session_id,),
        )
        return [ReviewRow(r["sid"], r["reg"], r["name"], r["st"], r["src"], r["conf"])
                for r in rows]

    def summary(self, session_id: str) -> dict:
        rows = self.get_review(session_id)
        return {
            "present": sum(1 for r in rows if r.status == "present"),
            "absent": sum(1 for r in rows if r.status == "absent"),
            "total": len(rows),
        }
