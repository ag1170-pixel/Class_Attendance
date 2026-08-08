"""Live visual demo — your webcam with face boxes + names, in the browser.

Green box = recognised student (shows their name).  Amber box = not enrolled.
Works with headless OpenCV (no desktop GUI): it streams annotated frames as MJPEG
to a web page, so you can watch on your Mac AND on your phone (same Wi-Fi).

Enrol first, then run this:
    python -m recognition.enroll --id S001 --name "Your Name" --source webcam
    python -m recognition.live_view                 # open http://localhost:8000
    python -m recognition.live_view --source clip.mp4 --port 8000
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
 <h1>Class Attendance — live recognition</h1>
 <p>Green = recognised student · Amber = not enrolled</p>
 <div class="frame"><img src="/stream"></div>
 <div class="legend"><span><span class="dot" style="background:#34c759"></span>Recognised</span>
   <span><span class="dot" style="background:#ff9f0a"></span>Not enrolled</span></div>
</body></html>"""


class Server:
    def __init__(self, source: str):
        self.source = source
        self.engine = FaceEngine()
        self.roster = Roster.load()
        if len(self.roster) == 0:
            print("! Roster is empty — enrol first with `python -m recognition.enroll`.")

    def annotate(self, frame):
        present = set()
        for f in self.engine.detect(frame):
            x, y, w, h = (int(v) for v in f.bbox)
            name = None
            if f.inter_eye_px >= config.MIN_INTEREYE_PX:
                sid, nm, _sim = self.roster.match(self.engine.embed(frame, f))
                if sid:
                    name = nm
                    present.add(nm)
            color = GREEN if name else AMBER
            label = name or "Not enrolled"
            cv2.rectangle(frame, (x, y), (x + w, y + h), color, 2)
            cv2.rectangle(frame, (x, y - 24), (x + max(80, len(label) * 11), y), color, -1)
            cv2.putText(frame, label, (x + 5, y - 7), cv2.FONT_HERSHEY_SIMPLEX, 0.55, WHITE, 1, cv2.LINE_AA)
        cv2.putText(frame, f"Present: {len(present)} / {len(self.roster)}",
                    (14, 32), cv2.FONT_HERSHEY_SIMPLEX, 0.8, WHITE, 2, cv2.LINE_AA)
        return frame


def make_handler(server: "Server"):
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
                cap = open_source(server.source)
                try:
                    for frame in cap.frames():
                        ok, jpg = cv2.imencode(".jpg", server.annotate(frame))
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
    ap = argparse.ArgumentParser(description="Live webcam recognition in the browser.")
    ap.add_argument("--source", default="webcam", help="webcam[:N] | file | rtsp://...")
    ap.add_argument("--port", type=int, default=8000)
    args = ap.parse_args()

    srv = Server(args.source)
    httpd = ThreadingHTTPServer(("0.0.0.0", args.port), make_handler(srv))
    print(f"▶ Live view at http://localhost:{args.port}  (Ctrl-C to stop)")
    print(f"  On your phone (same Wi-Fi): http://<your-mac-ip>:{args.port}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        httpd.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
