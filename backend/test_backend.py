"""End-to-end test of the backend workflow — stdlib unittest, no deps, no server.

Exercises the whole attendance lifecycle and the security guarantees:
  seed -> consent -> enroll -> create session (RBAC) -> record recognition ->
  teacher override -> submit -> audit trail, plus the consent-gate and
  authorization negative cases.

Run:  python -m unittest backend.test_backend -v
"""
from __future__ import annotations

import unittest

from .db import Database
from .seed import seed
from .services import (AttendanceService, AuthorizationError, ConsentError,
                       WorkflowError)


class BackendWorkflowTest(unittest.TestCase):
    def setUp(self):
        self.db = Database(":memory:")
        self.ids = seed(self.db)
        self.svc = AttendanceService(self.db)
        self.section = self.ids["section"]
        self.teacher = self.ids["teacher"]
        self.students = self.ids["students"]

    def _fake_embedding(self, seed_val: int):
        # Deterministic 128-d vector standing in for a real face embedding.
        return [((seed_val * 7 + i) % 100) / 100.0 for i in range(128)]

    # ── happy path ───────────────────────────────────────────────────────────
    def test_full_attendance_flow(self):
        # Consent + enroll first 4 students; leave the 5th un-enrolled.
        for i, s in enumerate(self.students[:4]):
            self.svc.grant_consent(s["id"], policy_version="v1", granted_by=self.teacher)
            self.svc.enroll_face(s["id"], self._fake_embedding(i), quality_score=0.9)

        roster = self.svc.roster_embeddings(self.section)
        self.assertEqual(len(roster), 4, "only consented+enrolled students appear")

        # Teacher triggers attendance.
        session = self.svc.create_session(self.teacher, self.section, "webcam")

        # Recognition says students 0 and 2 are present.
        present = [(self.students[0]["id"], 0.71), (self.students[2]["id"], 0.66)]
        self.svc.record_recognition(session, present)

        review = self.svc.get_review(session)
        self.assertEqual(len(review), 5, "review covers the whole roster")
        by_id = {r.student_id: r for r in review}
        self.assertEqual(by_id[self.students[0]["id"]].status, "present")
        self.assertEqual(by_id[self.students[0]["id"]].source, "auto")
        self.assertEqual(by_id[self.students[1]["id"]].status, "absent")

        # Teacher corrects student 1 -> present (they were there, camera missed them).
        self.svc.override_record(session, self.students[1]["id"], "present", self.teacher)
        review = {r.student_id: r for r in self.svc.get_review(session)}
        self.assertEqual(review[self.students[1]["id"]].status, "present")
        self.assertEqual(review[self.students[1]["id"]].source, "manual_override")

        # Submit.
        self.svc.submit_session(session, self.teacher)
        sess = self.db.query_one(
            "SELECT status FROM attendance_session WHERE id=?", (session,))
        self.assertEqual(sess["status"], "submitted")

        summary = self.svc.summary(session)
        self.assertEqual(summary["present"], 3)   # 0, 2 (auto) + 1 (override)
        self.assertEqual(summary["absent"], 2)

        # Audit trail recorded the key events.
        actions = {r["action"] for r in self.db.query("SELECT action FROM audit_log")}
        for expected in {"consent.grant", "enroll.face", "session.create",
                         "session.recognized", "record.override", "session.submit"}:
            self.assertIn(expected, actions)

    # ── security: consent gate ───────────────────────────────────────────────
    def test_enroll_without_consent_is_blocked(self):
        with self.assertRaises(ConsentError):
            self.svc.enroll_face(self.students[0]["id"], self._fake_embedding(1))

    def test_revoked_consent_deactivates_templates(self):
        s = self.students[0]
        self.svc.grant_consent(s["id"], "v1", self.teacher)
        self.svc.enroll_face(s["id"], self._fake_embedding(1))
        self.assertEqual(len(self.svc.roster_embeddings(self.section)), 1)
        self.svc.revoke_consent(s["id"], self.teacher)
        self.assertEqual(len(self.svc.roster_embeddings(self.section)), 0,
                         "revoking consent removes the student from matching")

    # ── security: RBAC ───────────────────────────────────────────────────────
    def test_other_teacher_cannot_trigger_section(self):
        other = "some-other-teacher-id"
        with self.assertRaises(AuthorizationError):
            self.svc.create_session(other, self.section, "webcam")

    # ── workflow guard ───────────────────────────────────────────────────────
    def test_cannot_submit_before_review(self):
        session = self.svc.create_session(self.teacher, self.section, "webcam")
        with self.assertRaises(WorkflowError):
            self.svc.submit_session(session, self.teacher)  # still 'processing'


if __name__ == "__main__":
    unittest.main(verbosity=2)
