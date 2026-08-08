"""Optional HTTP API (FastAPI) — a thin wrapper over the tested service layer.

The iOS app talks to these endpoints. All business logic lives in services.py,
so this file is deliberately thin. Requires:  pip install fastapi uvicorn

Run:  uvicorn backend.api:app --reload
Docs: http://127.0.0.1:8000/docs

NOTE: Auth here is a simplified header (`X-User-Id`) standing in for the
production SSO/JWT + RBAC described in docs/03_ARCHITECTURE.md §4. Every handler
still goes through the service layer, which enforces ownership and consent.
"""
from __future__ import annotations

from typing import List, Optional

try:
    from fastapi import Depends, FastAPI, Header, HTTPException
    from pydantic import BaseModel
except ImportError as e:  # pragma: no cover
    raise SystemExit(
        "FastAPI not installed. Run: pip install fastapi uvicorn\n"
        "(The service layer in backend/services.py works without it.)"
    ) from e

from .db import DEFAULT_DB, Database
from .services import (AttendanceService, AuthorizationError, ConsentError,
                       WorkflowError)

app = FastAPI(title="Class Attendance API", version="0.1.0")


def get_service() -> AttendanceService:
    return AttendanceService(Database(DEFAULT_DB))


def current_user(x_user_id: Optional[str] = Header(default=None)) -> str:
    if not x_user_id:
        raise HTTPException(401, "Missing X-User-Id (stands in for SSO/JWT)")
    return x_user_id


# ── DTOs ─────────────────────────────────────────────────────────────────────
class CreateSession(BaseModel):
    section_id: str
    capture_path: str = "webcam"


class PresentEntry(BaseModel):
    student_id: str
    confidence: float


class RecordRecognition(BaseModel):
    present: List[PresentEntry]


class Override(BaseModel):
    student_id: str
    status: str


# ── endpoints ────────────────────────────────────────────────────────────────
@app.get("/sections")
def list_sections(user: str = Depends(current_user),
                  svc: AttendanceService = Depends(get_service)):
    return svc.list_sections(user)


@app.post("/sessions")
def create_session(body: CreateSession, user: str = Depends(current_user),
                   svc: AttendanceService = Depends(get_service)):
    try:
        sid = svc.create_session(user, body.section_id, body.capture_path)
    except AuthorizationError as e:
        raise HTTPException(403, str(e))
    except WorkflowError as e:
        raise HTTPException(400, str(e))
    return {"session_id": sid, "status": "processing"}


@app.post("/sessions/{session_id}/recognition")
def record_recognition(session_id: str, body: RecordRecognition,
                       user: str = Depends(current_user),
                       svc: AttendanceService = Depends(get_service)):
    svc.record_recognition(session_id, [(p.student_id, p.confidence) for p in body.present])
    return {"status": "review", "summary": svc.summary(session_id)}


@app.get("/sessions/{session_id}/review")
def get_review(session_id: str, user: str = Depends(current_user),
               svc: AttendanceService = Depends(get_service)):
    return {"rows": [r.__dict__ for r in svc.get_review(session_id)],
            "summary": svc.summary(session_id)}


@app.post("/sessions/{session_id}/override")
def override(session_id: str, body: Override, user: str = Depends(current_user),
             svc: AttendanceService = Depends(get_service)):
    try:
        svc.override_record(session_id, body.student_id, body.status, user)
    except WorkflowError as e:
        raise HTTPException(400, str(e))
    return {"ok": True}


@app.post("/sessions/{session_id}/submit")
def submit(session_id: str, user: str = Depends(current_user),
           svc: AttendanceService = Depends(get_service)):
    try:
        svc.submit_session(session_id, user)
    except WorkflowError as e:
        raise HTTPException(400, str(e))
    return {"status": "submitted", "summary": svc.summary(session_id)}


@app.get("/health")
def health():
    return {"ok": True}
