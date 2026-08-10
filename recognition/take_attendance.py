"""Run an attendance session (the teacher's "Take Attendance" trigger).

Usage:
  python -m recognition.take_attendance --source webcam --seconds 5
  python -m recognition.take_attendance --source classroom.mp4 --seconds 5

Prints the pre-filled present/absent list the teacher would review, plus
capture stats that validate feasibility (how many faces were recognisable, and
the median inter-eye pixel distance actually observed).
"""
from __future__ import annotations

import argparse
import json

from . import config
from .capture import open_source
from .faces import FaceEngine
from .pipeline import RecognitionPipeline
from .roster import Roster


def main() -> int:
    ap = argparse.ArgumentParser(description="Run an attendance session.")
    ap.add_argument("--source", default="webcam",
                    help="webcam[:N] | path/to/video | rtsp://...")
    ap.add_argument("--seconds", type=float, default=config.ATTENDANCE_SECONDS)
    ap.add_argument("--json", action="store_true", help="emit JSON only")
    args = ap.parse_args()

    roster = Roster.load()
    if len(roster) == 0:
        print("Roster is empty. Enrol students first with recognition.enroll.")
        return 1

    engine = FaceEngine()
    pipeline = RecognitionPipeline(engine, roster)

    src = open_source(args.source)
    try:
        results, stats = pipeline.run(src, seconds=args.seconds)
    finally:
        src.release()

    present = [r for r in results if r.status == "present"]
    review = [r for r in results if r.status == "review"]
    absent = [r for r in results if r.status == "absent"]

    if args.json:
        print(json.dumps({
            "present": [r.__dict__ for r in present],
            "review": [r.__dict__ for r in review],
            "absent": [r.__dict__ for r in absent],
            "stats": stats.__dict__,
        }, indent=2))
        return 0

    marks = {"present": "✓ PRES", "review": "~ REVW", "absent": "✗ ABS "}
    print("\n─── ATTENDANCE (pre-filled — teacher reviews before submit) ───")
    print(f"{'STATUS':8} {'ID':6} {'NAME':22} {'CONF':6} {'FRAMES':6} {'EYE_PX'}")
    for r in results:
        print(f"{marks[r.status]:8} {r.student_id:6} {r.name:22} "
              f"{r.confidence:<6} {r.frames_seen:<6} {r.best_inter_eye_px}")

    print("\n─── CAPTURE STATS (feasibility evidence) ───")
    print(f"  frames processed     : {stats.frames_processed}")
    print(f"  faces detected       : {stats.faces_detected}")
    print(f"  faces recognisable   : {stats.faces_recognizable}  "
          f"(cleared {config.MIN_INTEREYE_PX}px inter-eye gate)")
    print(f"  median inter-eye px  : {stats.median_inter_eye_px:.1f}  "
          f"(need ~{config.RELIABLE_INTEREYE_PX}px for reliable ID)")
    print(f"\n  Present: {len(present)}   Needs review: {len(review)}   Absent: {len(absent)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
