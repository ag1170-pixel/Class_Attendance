"""Write attendance to Supabase via its REST API — stdlib only.

No psycopg, no DB password: uses Supabase Auth (teacher sign-in) + urllib, so the
Mac (`backend.live attend --cloud`) and the iPhone write to the SAME cloud database,
both as the same authenticated teacher identity.

Writes are RLS-scoped to sections that teacher owns (see docs/SECURITY_REVIEW.md —
the anon key ships inside the iPhone app and is publicly extractable, so it can
never be allowed to write attendance or read student PII; it stays read-only for
non-sensitive class/schedule data).

Demo credentials below are the same teacher account the iPhone app signs in with
(a single shared demo account, matching this prototype's single hardcoded teacher
row) — override via env vars for anything beyond the demo.
"""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import List

SUPABASE_URL = "https://mystjdepvvmfihcpiftx.supabase.co/rest/v1"
AUTH_URL = "https://mystjdepvvmfihcpiftx.supabase.co/auth/v1"
PUBLISHABLE_KEY = "sb_publishable_HvyNIVQ4emjhfQb5ZlkVmg_rCW9cvix"

TEACHER_EMAIL = os.environ.get("SUPABASE_TEACHER_EMAIL", "admin@gmail.com")
TEACHER_PASSWORD = os.environ.get("SUPABASE_TEACHER_PASSWORD", "1234")

# Seeded demo class in the cloud (see docs). One teacher/section/room for the demo.
DEMO_SECTION = "77777777-7777-7777-7777-777777777777"
DEMO_TEACHER = "55555555-5555-5555-5555-555555555555"
DEMO_ROOM = "33333333-3333-3333-3333-333333333333"

_access_token: str | None = None


def _sign_in() -> str:
    """Sign in as the demo teacher and cache the access token for this process."""
    global _access_token
    if _access_token:
        return _access_token
    body = json.dumps({"email": TEACHER_EMAIL, "password": TEACHER_PASSWORD}).encode()
    req = urllib.request.Request(
        f"{AUTH_URL}/token?grant_type=password", data=body,
        headers={"apikey": PUBLISHABLE_KEY, "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            data = json.loads(r.read())
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"Supabase teacher sign-in failed: {e.read().decode()}") from e
    _access_token = data["access_token"]
    return _access_token


def submit_demo(present_registers: List[str], capture_path: str = "webcam") -> str:
    """Submit to the seeded demo class in Supabase (shared with the iPhone)."""
    return submit_attendance(DEMO_SECTION, DEMO_TEACHER, DEMO_ROOM,
                             present_registers, capture_path)


def _request(method: str, path: str, body=None, prefer=None):
    headers = {
        "apikey": PUBLISHABLE_KEY,
        "Authorization": f"Bearer {_sign_in()}",
        "Content-Type": "application/json",
    }
    if prefer:
        headers["Prefer"] = prefer
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{SUPABASE_URL}/{path}", data=data,
                                 headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=30) as r:
        raw = r.read()
    return json.loads(raw) if raw else []


def roster_register_to_id(section_id: str) -> dict:
    """{register_no: student_uuid} for everyone on the section (to map results)."""
    rows = _request(
        "GET",
        f"section_roster?section_id=eq.{section_id}&select=student(id,register_no)")
    return {r["student"]["register_no"]: r["student"]["id"] for r in rows}


def submit_attendance(section_id: str, teacher_id: str, room_id: str,
                      present_registers: List[str], capture_path: str = "webcam") -> str:
    """Create a submitted session + one record per rostered student in Supabase.
    `present_registers` = register numbers recognised present. Returns session id.
    """
    roster = roster_register_to_id(section_id)
    session = _request("POST", "attendance_session", {
        "section_id": section_id, "teacher_id": teacher_id, "room_id": room_id,
        "capture_path": capture_path, "status": "submitted",
    }, prefer="return=representation")[0]
    sid = session["id"]

    present = set(present_registers)
    records = [{
        "session_id": sid, "student_id": uid,
        "status": "present" if reg in present else "absent",
        "source": "auto",
    } for reg, uid in roster.items()]
    if records:
        _request("POST", "attendance_record", records, prefer="return=minimal")
    return sid
