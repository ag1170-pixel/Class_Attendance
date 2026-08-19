"""HTTP recognition service — the camera / CCTV (server) side of the hybrid.

POST a recorded clip or RTSP source + a section; the server detects + recognises
every face against that section's roster using the proven recognise-once-then-track
engine, and returns present/absent. The server has a generous time budget (minutes),
so this is where a heavier detector belongs:

  • default detector = **YuNet** (fast, already installed) — good for most rooms.
  • crowd / tiny-face upgrade = **RetinaFace** (`pip install retina-face`, pulls
    TensorFlow) — swap it in recognition/faces.py behind the same detect() interface.
    See docs / the Obsidian "RetinaFace on iPhone (future)" note for the tradeoffs.

    python -m backend.server --port 8080
    curl -s localhost:8080/recognize -H 'Content-Type: application/json' \
         -d '{"source":"recognition/data/biden_clip.mp4","seconds":5,"submit":false}'
"""
from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from .db import DEFAULT_DB, Database
from .live import only_section, only_teacher
from .recognition_bridge import run_session
from .services import AttendanceService


def recognize(body: dict) -> dict:
    """Run recognition for one clip/stream against a section's roster."""
    source = body.get("source")
    if not source:
        return {"error": "missing 'source' (a file path or rtsp://... the server can read)"}
    seconds = float(body.get("seconds", 30))   # generous server budget

    db = Database(DEFAULT_DB)
    svc = AttendanceService(db)
    teacher = only_teacher(db)
    section = body.get("section") or only_section(db)

    enrolled = len(svc.roster_embeddings(section))
    if enrolled == 0:
        return {"error": "no enrolled faces for this section — enrol first"}

    session = svc.create_session(teacher, section, capture_path="cctv")
    run_session(db, session, source, seconds=seconds)
    review = svc.get_review(session)

    present = [{"register_no": r.register_no, "name": r.full_name,
                "confidence": round(r.confidence, 3) if r.confidence else None}
               for r in review if r.status == "present"]
    absent = [{"register_no": r.register_no, "name": r.full_name}
              for r in review if r.status == "absent"]
    if body.get("submit"):
        svc.submit_session(session, teacher)
    return {"session": session, "enrolled": enrolled,
            "present": present, "absent": absent, "summary": svc.summary(session)}


class Handler(BaseHTTPRequestHandler):
    def _send(self, code: int, obj: dict) -> None:
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        self._send(200 if self.path == "/health" else 404,
                   {"ok": True} if self.path == "/health" else {"error": "POST /recognize"})

    def do_POST(self) -> None:
        if self.path.rstrip("/") != "/recognize":
            self._send(404, {"error": "POST /recognize"})
            return
        n = int(self.headers.get("Content-Length", 0))
        try:
            body = json.loads(self.rfile.read(n) or b"{}")
        except json.JSONDecodeError:
            self._send(400, {"error": "invalid JSON body"})
            return
        try:
            self._send(200, recognize(body))
        except Exception as e:   # noqa: BLE001 — always return a JSON error, never hang
            self._send(500, {"error": str(e)})

    def log_message(self, *args) -> None:
        pass


def main() -> int:
    ap = argparse.ArgumentParser(description="Camera/CCTV recognition server.")
    ap.add_argument("--port", type=int, default=8080)
    args = ap.parse_args()
    httpd = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print(f"▶ Recognition server on :{args.port}  (POST /recognize)")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        httpd.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
