# Recognition Prototype

The make-or-break core of the attendance system: turn a short video (Mac webcam
now, classroom camera later) into a present/absent list bound to enrolled
students. Implements **recognise once, then track** (see `../docs/02_ALGORITHM.md`).

## Stack (lightweight, CPU-friendly)

| Role | Prototype (here) | Production upgrade |
|---|---|---|
| Face detection | OpenCV **YuNet** | YOLOv8 / SCRFD |
| Face embedding | OpenCV **SFace** | ArcFace (insightface) |
| Tracking | IoU tracker | ByteTrack / BoT-SORT |
| Templates | JSON on disk | Postgres + pgvector (encrypted) |

Same `detect → embed → match → track` interface, so upgrading models doesn't
touch the pipeline.

## Setup

```bash
python3 -m venv ../.venv
../.venv/bin/pip install -r requirements.txt
../.venv/bin/python -m recognition.download_models   # ~5 MB, one time
```

## Demo (Mac webcam)

```bash
# 1) Enrol yourself (the one-time face scan)
../.venv/bin/python -m recognition.enroll --id S001 --name "Your Name" --source webcam

# 2) Take attendance — recognises enrolled people in the next 5 seconds
../.venv/bin/python -m recognition.take_attendance --source webcam --seconds 5
```

Swap the classroom camera in later with **zero pipeline changes**:

```bash
../.venv/bin/python -m recognition.take_attendance --source rtsp://user:pass@cam-ip:554/stream
../.venv/bin/python -m recognition.take_attendance --source classroom_clip.mp4
```

## Validate without a camera

```bash
../.venv/bin/python -m recognition.selftest
```

Enrols real faces, composites a synthetic classroom at shrinking face sizes, and
shows recognition is correct while faces are large enough and degrades exactly
at the documented pixel budget.

## Key thresholds (`config.py`)

- `COSINE_MATCH_THRESHOLD` — identity match cutoff (favours precision on "present")
- `MIN_INTEREYE_PX` / `RELIABLE_INTEREYE_PX` — the pixel quality gate
- `MIN_FRAMES_PRESENT` — how long an identity must persist to count present
