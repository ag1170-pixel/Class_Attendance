# Class Attendance — Face-Recognition Attendance System

Mark class attendance from the classroom camera. The teacher taps **Take
Attendance**; the system pulls a short clip, recognises enrolled students'
faces, and shows a pre-filled present/absent list the teacher confirms and
submits. Marks a *recognised face in the room* — so it resists the proxy
attendance that QR / RFID / Bluetooth can't.

**Demo now** runs on the Mac webcam; the real classroom camera (RTSP / recorded
clip) drops into the same pluggable source with no pipeline changes.

---

## What's here

| Folder | What | Status |
|---|---|---|
| `recognition/` | Face detect + track + recognise (recognise-once-then-track) | ✅ built + tested on real faces |
| `backend/` | DB schema, workflow, security (consent, RBAC, audit) | ✅ built + 5/5 tests pass |
| `ios/` | SwiftUI teacher app + enrollment (AVFoundation + Vision) | ✅ scaffolded (build in Xcode) |
| `prototype/` | Interactive motion-UI prototype (teacher + student) | ✅ [open it](prototype/attendance-ui.html) |
| `docs/` | Feasibility, algorithm, architecture, challenges+answers | ✅ |

Read the thinking in [docs/01_FEASIBILITY.md](docs/01_FEASIBILITY.md),
[docs/02_ALGORITHM.md](docs/02_ALGORITHM.md),
[docs/03_ARCHITECTURE.md](docs/03_ARCHITECTURE.md),
[docs/04_CHALLENGES_AND_ANSWERS.md](docs/04_CHALLENGES_AND_ANSWERS.md).

---

## Setup (one time)

```bash
python3 -m venv .venv
.venv/bin/pip install -r recognition/requirements.txt
.venv/bin/python -m recognition.download_models     # YuNet + SFace (~37 MB)
```

## Run the tests (proves the core works)

```bash
.venv/bin/python -m unittest backend.test_backend -v   # workflow + security
.venv/bin/python -m recognition.selftest               # recognition on real faces
```

## The live webcam demo — camera → recognition → **database**

`backend.live` is the whole app on the command line: it enrols and takes
attendance straight into the DB (the same tables the API + iOS app use).
macOS will ask for camera permission the first time — grant it to your terminal.

```bash
python -m backend.live init                               # seed a demo class, print the roster
python -m backend.live enroll --who REG001 --source webcam   # scan a student's face → DB
python -m backend.live attend --source webcam --submit       # take attendance → stored + submitted
python -m backend.live status                             # show the latest session from the DB
```

Swap in the real classroom camera later — **no code change**, just the source:

```bash
python -m backend.live attend --source rtsp://user:pass@cam-ip:554/stream --submit
python -m backend.live attend --source classroom_clip.mp4 --submit
```

Recognition-only (no DB), handy for quick tests:

```bash
python -m recognition.enroll --id S001 --name "Your Name" --source webcam
python -m recognition.take_attendance --source webcam --seconds 5
```

## Backend API (optional, for the iOS app)

```bash
.venv/bin/pip install fastapi uvicorn
.venv/bin/python -m backend.seed          # demo institution/teacher/section/students
.venv/bin/uvicorn backend.api:app --reload
```

## iOS app

Open `ios/ClassAttendance/` in Xcode (add the files to a new iOS App target;
set `NSCameraUsageDescription` and `NSFaceIDUsageDescription` in Info.plist).
Point `BACKEND_URL` at the running backend. Design tokens + motion live in
`ios/ClassAttendance/Core/Theme.swift`, matching the prototype.

---

## The 3-sentence pitch (for review)

1. **It works** — one good frame per student (recognise-once-then-track), reusing
   cameras the campus already has, teacher confirms every result.
2. **It can't be gamed** like QR / RFID / Bluetooth, because it marks a
   *recognised face in the room*, not a device or a card.
3. **It's responsible** — biometric data is consent-gated, encrypted, on-premise,
   purpose-limited, human-in-the-loop, and revocable.
