"""Live visual demo — recognise once, then TRACK the person everywhere.

Green box = recognised student (name shown).  Amber box = tracked but not enrolled.
Unlike plain face detection, once a person is picked up an object tracker follows
them every frame — so a mask, a turned head, or moving around does NOT lose them
(this is the café / assembly-line "detect once, track after" idea). Periodic face
detection only adds NEW people, or fills in a name if someone was masked at first.

Works with headless OpenCV (streams MJPEG to the browser — Mac and phone).

    python -m recognition.enroll --id S001 --name "Your Name" --source webcam
    python -m recognition.live_view                 # open http://localhost:8000
"""
from __future__ import annotations

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import cv2

from . import config
from .capture import open_source
from .faces import FaceEngine
from .roster import Roster

GREEN = (89, 199, 52)     # BGR
AMBER = (10, 159, 255)
WHITE = (255, 255, 255)

DETECT_EVERY = 12         # run face detection every N frames; track in between
MAX_MISSES = 10           # frames a lost tracker survives before being dropped

PAGE = """<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Class Attendance — Live</title>
<style>
 body{margin:0;background:#000;color:#f5f5f7;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text',system-ui,sans-serif;
   min-height:100vh;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:16px;padding:24px}
 h1{font-size:20px;font-weight:650;letter-spacing:-.02em;margin:0}
 p{color:#98989f;font-size:14px;margin:0}
 .frame{border-radius:18px;overflow:hidden;box-shadow:0 30px 70px -20px rgba(0,0,0,.8);border:1px solid #2c2c2e;max-width:96vw}
 img{display:block;width:820px;max-width:96vw;height:auto}
 .legend{display:flex;gap:18px;font-size:13px;color:#98989f}
 .dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:6px;vertical-align:middle}
</style></head><body>
 <h1>Class Attendance — recognise once, then track</h1>
 <p>Put on a mask or turn away — the box stays locked on you.</p>
 <div class="frame"><img src="/stream"></div>
 <div class="legend"><span><span class="dot" style="background:#34c759"></span>Recognised</span>
   <span><span class="dot" style="background:#ff9f0a"></span>Tracked · not enrolled</span></div>
</body></html>"""


class Tracker:
    """One person: a visual tracker + the identity bound to them."""
    __slots__ = ("cv", "name", "box", "misses")

    def __init__(self, frame, box, name):
        self.cv = cv2.TrackerCSRT_create()
        self.cv.init(frame, tuple(int(v) for v in box))
        self.box = box
        self.name = name
        self.misses = 0


class Engine:
    def __init__(self, source: str):
        self.source = source
        self.faces = FaceEngine()
        self.roster = Roster.load()
        self.tracks: list[Tracker] = []
        self.frame_i = 0
        if len(self.roster) == 0:
            print("! Roster empty — enrol first with `python -m recognition.enroll`.")

    @staticmethod
    def _center_in(box, cx, cy):
        x, y, w, h = box
        return x <= cx <= x + w and y <= cy <= y + h

    @staticmethod
    def _expand(fb, shape):
        x, y, w, h = fb
        nx = max(0, x - 0.20 * w); ny = max(0, y - 0.25 * h)
        nw = min(shape[1] - nx, w * 1.4); nh = min(shape[0] - ny, h * 2.4)
        return (nx, ny, nw, nh)

    def _recognise(self, frame, face):
        if face.inter_eye_px < config.MIN_INTEREYE_PX:
            return None
        sid, name, _ = self.roster.match(self.faces.embed(frame, face))
        return name if sid else None

    def process(self, frame):
        self.frame_i += 1

        # 1) advance every existing tracker (this is what survives a mask/turn)
        alive = []
        for t in self.tracks:
            ok, box = t.cv.update(frame)
            if ok:
                t.box = box; t.misses = 0
                alive.append(t)
            else:
                t.misses += 1
                if t.misses < MAX_MISSES:
                    alive.append(t)
        self.tracks = alive

        # 2) periodically detect faces to add new people / name masked ones
        if self.frame_i % DETECT_EVERY == 1:
            for f in self.faces.detect(frame):
                fx, fy, fw, fh = (int(v) for v in f.bbox)
                cx, cy = fx + fw / 2, fy + fh / 2
                match = next((t for t in self.tracks if self._center_in(t.box, cx, cy)), None)
                if match is not None:
                    if match.name is None:                 # was masked/unknown before
                        match.name = self._recognise(frame, f)
                else:
                    self.tracks.append(
                        Tracker(frame, self._expand((fx, fy, fw, fh), frame.shape),
                                self._recognise(frame, f)))

        # 3) draw
        present = set()
        for t in self.tracks:
            x, y, w, h = (int(v) for v in t.box)
            if t.name:
                present.add(t.name)
            color = GREEN if t.name else AMBER
            label = t.name or "Tracking · not enrolled"
            cv2.rectangle(frame, (x, y), (x + w, y + h), color, 2)
            cv2.rectangle(frame, (x, y - 24), (x + max(90, len(label) * 10), y), color, -1)
            cv2.putText(frame, label, (x + 5, y - 7), cv2.FONT_HERSHEY_SIMPLEX, 0.5, WHITE, 1, cv2.LINE_AA)
        cv2.putText(frame, f"Tracking {len(self.tracks)} · Present {len(present)}/{len(self.roster)}",
                    (14, 32), cv2.FONT_HERSHEY_SIMPLEX, 0.75, WHITE, 2, cv2.LINE_AA)
        return frame


def make_handler(engine: "Engine"):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/":
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.end_headers()
                self.wfile.write(PAGE.encode())
            elif self.path == "/stream":
                self.send_response(200)
                self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
                self.end_headers()
                cap = open_source(engine.source, sample_fps=24)   # high fps = smooth tracking
                try:
                    for frame in cap.frames():
                        ok, jpg = cv2.imencode(".jpg", engine.process(frame))
                        if not ok:
                            continue
                        self.wfile.write(b"--frame\r\nContent-Type: image/jpeg\r\n\r\n"
                                         + jpg.tobytes() + b"\r\n")
                except (BrokenPipeError, ConnectionResetError):
                    pass
                finally:
                    cap.release()
            else:
                self.send_error(404)

        def log_message(self, *a):
            pass
    return Handler


def main() -> int:
    ap = argparse.ArgumentParser(description="Live recognise-once-then-track in the browser.")
    ap.add_argument("--source", default="webcam", help="webcam[:N] | file | rtsp://...")
    ap.add_argument("--port", type=int, default=8000)
    args = ap.parse_args()

    engine = Engine(args.source)
    httpd = ThreadingHTTPServer(("0.0.0.0", args.port), make_handler(engine))
    print(f"▶ Live view at http://localhost:{args.port}  (Ctrl-C to stop)")
    print(f"  On your phone (same Wi-Fi): http://<your-mac-ip>:{args.port}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        httpd.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
