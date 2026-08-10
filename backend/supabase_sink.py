"""Write attendance to Supabase via its REST API — stdlib only.

No psycopg, no DB password: uses the project's publishable key + urllib, so the
Mac (`backend.live --cloud`) and the iPhone write to the SAME cloud database.

DEMO note: the publishable key + open RLS insert is fine for a prototype; in
production put this behind Supabase Auth (teacher role) and scoped policies.
"""
from __future__ import annotations

import json
import urllib.request
from typing import List

SUPABASE_URL = "https://mystjdepvvmfihcpiftx.supabase.co/rest/v1"
PUBLISHABLE_KEY = "sb_publishable_HvyNIVQ4emjhfQb5ZlkVmg_rCW9cvix"

_HEADERS = {
    "apikey": PUBLISHABLE_KEY,
    "Authorization": f"Bearer {PUBLISHABLE_KEY}",
    "Content-Type": "application/json",
}

# Seeded demo class in the cloud (see docs). One teacher/section/room for the demo.
DEMO_SECTION = "77777777-7777-7777-7777-777777777777"
DEMO_TEACHER = "55555555-5555-5555-5555-555555555555"
DEMO_ROOM = "33333333-3333-3333-3333-333333333333"


def submit_demo(present_registers: List[str], capture_path: str = "webcam") -> str:
    """Submit to the seeded demo class in Supabase (shared with the iPhone)."""
    return submit_attendance(DEMO_SECTION, DEMO_TEACHER, DEMO_ROOM,
                             present_registers, capture_path)


def _request(method: str, path: str, body=None, prefer=None):
    headers = dict(_HEADERS)
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
