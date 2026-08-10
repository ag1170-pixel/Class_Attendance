"""Live end-to-end: camera -> face recognition -> database.

This is the whole app on the command line. It ties the recognition engine to the
backend DB, so enrolling and taking attendance actually write to the database
(the same tables the API + iOS app use). Swap `--source webcam` for a classroom
`rtsp://...` or a recorded clip with no other change.

    python -m backend.live init                       # seed a demo class, print roster
    python -m backend.live enroll --who REG001 --source webcam
    python -m backend.live attend --source webcam --submit
    python -m backend.live status                     # show the latest session

State persists in backend/attendance.db between commands.
"""
from __future__ import annotations

import argparse
import sys

from .db import DEFAULT_DB, Database
from .services import AttendanceService, ConsentError, WorkflowError


# ── camera capture -> one best embedding ─────────────────────────────────────
def capture_embedding(source: str, seconds: float):
    """Grab the highest-quality face embedding seen in the window."""
    from recognition import config
    from recognition.capture import open_source
    from recognition.faces import FaceEngine

    engine = FaceEngine()
    src = open_source(source)
    best = None  # (embedding, inter_eye_px)
    try:
        for frame in src.frames(max_seconds=seconds):
            faces = engine.detect(frame)
            if not faces:
                continue
            f = max(faces, key=lambda x: x.inter_eye_px)
            if f.inter_eye_px < config.MIN_INTEREYE_PX:
                continue
            if best is None or f.inter_eye_px > best[1]:
                best = (engine.embed(frame, f), f.inter_eye_px)
    finally:
        src.release()
    return best


# ── DB lookups (friendly resolution for the demo's single class) ─────────────
def only_teacher(db: Database) -> str:
    return db.query_one("SELECT id FROM app_user WHERE role='teacher' LIMIT 1")["id"]


def only_section(db: Database) -> str:
    return db.query_one("SELECT id FROM section LIMIT 1")["id"]


def student_by_register(db: Database, register_no: str):
    return db.query_one("SELECT * FROM student WHERE register_no=?", (register_no,))


# ── commands ─────────────────────────────────────────────────────────────────
def cmd_init(db, args) -> int:
    from .seed import seed
    DEFAULT_DB.unlink(missing_ok=True)
    db = Database(DEFAULT_DB)
    ids = seed(db)
    print("Seeded demo class. Enroll these students, then take attendance:\n")
    print(f"  {'REGISTER':10} NAME")
    for s in ids["students"]:
        print(f"  {s['register_no']:10} {s['name']}")
    print(f"\n  section: {ids['section']}\n  teacher: {ids['teacher']}")
    return 0


def cmd_enroll(db, args) -> int:
    svc = AttendanceService(db)
    st = student_by_register(db, args.who)
    if st is None:
        print(f"No student with register_no {args.who}. Run `init` first.", file=sys.stderr)
        return 1

    print(f"Enrolling {st['full_name']} ({args.who}) from {args.source}…")
    cap = capture_embedding(args.source, args.seconds)
    if cap is None:
        print("No usable face captured. Better light / move closer and retry.", file=sys.stderr)
        return 1
    emb, ied = cap

    # Consent is required before any biometric write (enforced by the service).
    svc.grant_consent(st["id"], policy_version="v1", granted_by=only_teacher(db))
    try:
        svc.enroll_face(st["id"], emb.tolist(), quality_score=min(1.0, ied / 120.0))
    except ConsentError as e:
        print(str(e), file=sys.stderr)
        return 1
    print(f"✓ Stored face template in DB (inter-eye {ied:.0f}px).")
    return 0


def cmd_attend(db, args) -> int:
    from .recognition_bridge import run_session
    svc = AttendanceService(db)
    teacher, section = only_teacher(db), only_section(db)
    path = "webcam" if args.source.startswith("webcam") else \
           ("cctv" if args.source.startswith("rtsp") else "iphone")

    enrolled = len(svc.roster_embeddings(section))
    if enrolled == 0:
        print("No enrolled faces yet. Run `enroll` first.", file=sys.stderr)
        return 1

    print(f"Taking attendance from {args.source} ({enrolled} enrolled)…")
    session = svc.create_session(teacher, section, capture_path=path)
    present = run_session(db, session, args.source, seconds=args.seconds)

    _print_review(svc, session)
    if args.submit:
        svc.submit_session(session, teacher)
        print("\n✓ Submitted and audit-logged (local).")
    if args.cloud:
        from .supabase_sink import submit_demo
        regs = [r["register_no"] for (sid, _c) in present
                if (r := db.query_one("SELECT register_no FROM student WHERE id=?", (sid,)))]
        cloud_id = submit_demo(regs, capture_path=path)
        print(f"☁ Also submitted to Supabase (shared with iPhone): {cloud_id}")
    return 0


def cmd_status(db, args) -> int:
    svc = AttendanceService(db)
    row = db.query_one("SELECT id, status FROM attendance_session ORDER BY triggered_at DESC LIMIT 1")
    if row is None:
        print("No sessions yet.")
        return 0
    print(f"Latest session {row['id']} — status: {row['status']}")
    _print_review(svc, row["id"])
    return 0


def _print_review(svc: AttendanceService, session_id: str) -> None:
    print(f"\n─── ATTENDANCE (stored in DB) ───")
    for r in svc.get_review(session_id):
        mark = "✓ PRES" if r.status == "present" else "✗ ABS "
        conf = f"{r.confidence:.2f}" if r.confidence else ""
        tag = " (edited)" if r.source == "manual_override" else ""
        print(f"  {mark} {r.register_no:8} {r.full_name:20} {conf}{tag}")
    s = svc.summary(session_id)
    print(f"\n  Present: {s['present']}   Absent: {s['absent']}   Total: {s['total']}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Live camera → recognition → database.")
    sub = ap.add_subparsers(dest="cmd", required=True)

    sub.add_parser("init")

    pe = sub.add_parser("enroll")
    pe.add_argument("--who", required=True, help="student register_no, e.g. REG001")
    pe.add_argument("--source", default="webcam", help="webcam[:N] | file | rtsp://...")
    pe.add_argument("--seconds", type=float, default=4.0)

    pa = sub.add_parser("attend")
    pa.add_argument("--source", default="webcam", help="webcam[:N] | file | rtsp://...")
    pa.add_argument("--seconds", type=float, default=5.0)
    pa.add_argument("--submit", action="store_true", help="submit immediately after review")
    pa.add_argument("--cloud", action="store_true",
                    help="also submit to Supabase (shared cloud DB with the iPhone)")

    sub.add_parser("status")

    args = ap.parse_args()
    db = Database(DEFAULT_DB)
    return {"init": cmd_init, "enroll": cmd_enroll,
            "attend": cmd_attend, "status": cmd_status}[args.cmd](db, args)


if __name__ == "__main__":
    raise SystemExit(main())
