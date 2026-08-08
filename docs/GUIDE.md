# Class Attendance — Setup & Run Guide

Mark class attendance from a camera: the teacher taps **Take Attendance**, the
system recognises enrolled students' faces (recognise **once**, then **track**
each person even through a mask or a turned head), shows a pre-filled
present/absent list to confirm, and stores it. Not-enrolled faces are flagged so
the teacher can spot them and ask them to enrol.

Follow the steps below to run it on your own Mac (and iPhone).

---

## 0. Prerequisites

| You need | Why |
|---|---|
| **macOS** with **Xcode 15+** (16/26 fine) | to build & run the iOS app |
| **Python 3.9+** | to run the face-recognition engine on the Mac |
| An **iPhone** (optional) | the camera works on a real device (the Simulator has no camera) |
| **Git** | to clone the repo |

---

## 1. Get the code

```bash
git clone https://github.com/ag1170-pixel/Class_Attendance.git
cd Class_Attendance
```

---

## 2. Mac — the face-recognition engine

**Set up (one time):**
```bash
python3 -m venv .venv
.venv/bin/pip install -r recognition/requirements.txt
.venv/bin/python -m recognition.download_models
```

**Give the camera permission:** System Settings → Privacy & Security → **Camera**
→ turn on **Terminal** (or iTerm) → quit and reopen it. (This is the usual reason
the webcam "doesn't work.")

**A) Live tracking demo — webcam with boxes + names in your browser:**
```bash
.venv/bin/python -m recognition.enroll --id S001 --name "Your Name" --source webcam
```
```bash
.venv/bin/python -m recognition.live_view
```
Open **http://localhost:8000** — green box = recognised (name shown), amber =
tracked but not enrolled. Put on a mask or turn around: the box **stays on you**
(recognise-once-then-track). Phone on the same Wi-Fi: `http://<your-mac-ip>:8000`.

**B) Camera → recognition → database demo (terminal):**
```bash
.venv/bin/python -m backend.live init
```
```bash
.venv/bin/python -m backend.live attend --source webcam --submit
```
`init` prints the class + register numbers; `attend` captures ~5s and stores
present/absent. Swap `--source webcam` for `--source rtsp://…` for a real
classroom camera — no code change.

---

## 3. Prove it works (tests)

```bash
.venv/bin/python -m unittest backend.test_backend
```
```bash
.venv/bin/python -m recognition.selftest
```
The first checks the workflow + security (consent, teacher-only access, audit);
the second recognises real faces and shows accuracy degrading exactly at the
pixel limit.

---

## 4. iPhone — the app

```bash
open ios/ClassAttendance.xcodeproj
```
1. Plug in your iPhone and select it as the run destination.
2. Select the **ClassAttendance** target → **Signing & Capabilities** →
   **Automatically manage signing** → choose your **Team** (add your Apple ID in
   Xcode → Settings → Accounts). If the bundle id clashes, change it to
   `com.yourname.classattendance`.
3. Press **⌘R**. First run: on the phone, **Settings → General → VPN & Device
   Management → trust** your developer profile, then reopen the app.

You'll see: Face ID unlock → **Today** (classes pulled **live from Supabase**) →
tap a class → **Take Attendance** → review with separate **Present / Absent**
sections, a **not-enrolled** flag + locate, and **add-by-register-no** → Submit.
The real **camera** is used in **Settings → Enroll a student**.

*No iPhone?* Pick a Simulator and ⌘R — everything works except the live camera.

---

## 5. Cloud database (Supabase) — already live

The app reads live class data from a Supabase project (Postgres + pgvector, with
row-level security: only class/schedule tables are readable by the app key;
biometrics and attendance records stay locked). To point it at **your own**
Supabase: create a project, run `backend/migrations/0001_init.sql` in its SQL
editor, then update the URL + key in `ios/ClassAttendance/Core/SupabaseClient.swift`.

---

## What's inside

| Folder | What |
|---|---|
| `recognition/` | face detect + recognise-once + track (Python, OpenCV) |
| `backend/` | schema, workflow, security, Supabase, camera→DB CLI |
| `ios/` | the SwiftUI iPhone app |
| `prototype/` | interactive UI prototype (open in any browser) |
| `docs/` | feasibility, algorithm, architecture, challenges, roadmap, this guide |

---

## 📱 The iOS technologies we use (why this is a real iOS app)

This isn't a web page in a wrapper — it's built on Apple's native frameworks:

**Used in the app today**
- **SwiftUI** — the entire UI: `TabView`, `NavigationStack`, `List`, `Form`,
  `.searchable`, `.refreshable`, `.sheet`, `.task`.
- **Swift Concurrency** — `async`/`await`, `@MainActor`, an `actor` for the API
  client, `Task` for the capture flow.
- **Combine** — `ObservableObject` / `@Published` / `@StateObject` /
  `@EnvironmentObject` drive live UI state.
- **AVFoundation** — live camera capture: `AVCaptureSession`,
  `AVCaptureVideoDataOutput`, `AVCaptureVideoPreviewLayer` (enrollment).
- **Vision** — on-device face **quality gate**:
  `VNDetectFaceCaptureQualityRequest` only accepts a clean, single face.
- **LocalAuthentication** — **Face ID / Touch ID** unlock (`LAContext`).
- **Core Image** — generates a **real, scannable class QR**
  (`CIFilter.qrCodeGenerator`).
- **URLSession** (async) — reads **live data from Supabase**.
- **UIKit interop** — `UIViewRepresentable` bridges the camera preview;
  trait-aware colors via `UIColor`.
- **SF Symbols + system animations** — `symbolEffect(.bounce)`,
  `contentTransition(.numericText())`, spring transitions; full **light/dark**.
- **Codable** — type-safe models over the REST API.

**On the roadmap (next iOS milestones)**
- **Core ML** — run the face-embedding model **on-device** so the iPhone camera
  recognises faces itself (recognise-once-then-track on iOS).
- **VisionKit `DataScannerViewController`** — scan the class QR with the camera.
- **Core Bluetooth** — optional room beacon to confirm the teacher is in the room.
- **Keychain** + **Supabase Auth** — real teacher sign-in and secure tokens.
- **UserNotifications** — tell a student the moment they're marked absent.

**The one-line pitch:** a native SwiftUI app using AVFoundation + Vision for
on-device face capture, Core Image for QR, Face ID for auth, and a live Supabase
backend — with a recognise-once-then-track engine that can't be fooled by a
proxy, a mask, or a turned head.
