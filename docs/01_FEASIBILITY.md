# Class Attendance via Face Recognition — Feasibility Analysis

**Status:** Pre-build feasibility study. Goal: confirm what is actually possible in a real classroom *before* writing the application, so we don't build something that only works on paper.

**Date:** 2026-08-07

---

## 1. The concept (as agreed)

- Universities already run CCTV that records **continuously** to a **university recording server** (an NVR / VMS).
- We do **not** install software on the cameras and we do **not** trigger the camera directly.
- When a teacher taps **"Take Attendance"** on an iOS app, our system asks the university recording server for the **5-second slice** of already-recorded video for *that room at that moment*.
- Our processing server runs **face recognition** on that clip and marks who is present.
- The teacher reviews a pre-filled present/absent list (tick/cross), corrects errors, and submits — mirroring the current academia-CRM workflow.
- Face dataset + recordings are owned and held by the **university**. Teachers and university have access; students do not.

Verdict up front: **The architecture is sound and standard. One part — recognizing an entire seated class from one existing wide-angle room camera — is where reality bites. That part needs a design change to actually work.**

---

## 2. Part-by-part feasibility

| Component | Feasible in practice? | Notes |
|---|---|---|
| iOS teacher app (trigger + review) | ✅ Yes | Straightforward client app |
| Pull a 5s clip by (camera, timestamp) from the recording server | ✅ Yes — standardized | ONVIF **Profile G** is the industry standard for exactly this: search + retrieve + export recorded video by time. Also vendor VMS APIs (Milestone, Genetec, Hikvision/Dahua, Axis). |
| Face **enrollment** (student scanned once) | ✅ Yes | Close, frontal, controlled capture — easy and accurate |
| Face **recognition of a whole seated class** from existing wide room CCTV | ⚠️ **This is the risk** | See §3. Usually fails on pixel density and camera angle. |
| Central storage of face data at the university | ✅ Yes | University is the data custodian |
| Secure auth, DB, audit trail | ✅ Yes | Standard engineering |

---

## 3. The one hard reality: can the camera actually SEE the faces?

Face recognition needs a **minimum number of pixels between the eyes** (inter-eye distance, "IED") to work:

- **~32 px IED** = absolute minimum to attempt a match
- **~64 px IED** = recommended for reliable recognition
- **120+ px IED** = ideal (ISO best practice)

A human's inter-eye distance is about **6.3 cm**. So for reliable (64 px) recognition we need roughly **10 pixels per cm** at the student's face — about **1000 px per meter** of scene width.

### The classroom math (this is the crux)

Take a **1080p** camera (1920 px wide) trying to cover a classroom ~**8 m** wide:

```
horizontal density = 1920 px / 800 cm ≈ 2.4 px per cm
IED in pixels       = 2.4 px/cm × 6.3 cm ≈ 15 px
```

**~15 px IED — less than half the bare minimum, a quarter of "reliable."** A single 1080p camera covering a whole room simply cannot resolve seated students' faces well enough.

To hit the reliable **64 px IED**, one 1080p camera can only cover about **1.9 m of width**. A full classroom would need either:

- a very high-resolution camera (8K-class) aimed at the seats, **or**
- several cameras, each covering ~2 m zones, **or**
- a different capture strategy (see §4).

### The second problem: camera **angle**

Recognition needs to see **faces**, not the backs of heads. Students face the board/teacher. A camera mounted at the **front** (over the board) sees faces — good. A camera at the **back or corner** (where monitoring cameras usually are) sees the **backs of heads** — recognition impossible. Existing classroom CCTV is very often placed for *monitoring*, not for *facing the students*.

### What this means

The research literature reports 90–96% accuracy — but explicitly notes this holds **only in controlled conditions**, and "deteriorates significantly" with real lighting, motion blur, camera resolution, and viewing geometry. In plain terms: **the demo works; the wide-classroom real-world deployment is where most of these systems quietly fail.** This is precisely the trap to avoid.

---

## 4. The fix that makes it actually work: recognize at the **entrance**

This is what real, working deployments do (confirmed across the sources): instead of trying to identify 40 small, angled, seated faces in a wide shot, **recognize each student as they walk through the door** — one at a time, close to the camera (~1–2 m), frontal, well-lit.

At 1.5 m a face easily exceeds 64–120 px IED. The pixel budget is met. The angle is frontal. Lighting at a doorway is controllable.

**How this preserves your whole design:**

- Still uses **existing recording infrastructure** + **our server pulls the clip** — just from the **door camera** feed instead of the wide room feed.
- The teacher's **"Take Attendance"** trigger defines the **session window**: everyone recognized entering the room in, say, the 10 minutes before the trigger (and during class) is marked present.
- Proxy is *harder*, not easier: each entering face is large and frontal, so liveness / anti-spoof is more reliable than in a wide shot.
- A student who was distracted and "forgot to mark attendance" is still captured — they physically walked in, so they're recognized. This directly solves the problem you described.

**Trade-off:** it marks "entered the room," not "sat through the class." For most universities that's exactly what manual roll-call does today anyway. If mid-class presence matters, add a second recognition pass at a random time.

---

## 5. Options summary (pick one to build on)

| Option | Works in practice today? | Hardware reality | iOS-boot-camp demoable? |
|---|---|---|---|
| **A. Entrance camera + server pull** (recommended) | ✅ Yes | Needs a door-facing camera per room (often already there, or one cheap addition) | ✅ Yes |
| **B. Wide room camera, whole seated class** | ⚠️ Only with 4K–8K cameras placed at the front | Existing 1080p monitoring cams won't cut it | Risky to demo honestly |
| **C. Teacher's iPhone/iPad as the capture device** | ✅ For a demo | No server/CCTV access needed; strongest native-iOS story | ✅ Best for boot camp |
| **D. High-res multi-camera room rig** | ✅ Yes | Expensive, real install project | Overkill for boot camp |

**Recommendation:**
- **For the boot-camp deliverable:** build **Option C** as the working, honest demo (iPhone/iPad camera does close-range recognition — e.g. a "door greeter" iPad, or teacher pans the device). It gives the richest native-iOS story (AVFoundation + Vision + Core ML) and it *actually works* at the range a phone is used.
- **Design the server/API so Option A (entrance CCTV via ONVIF Profile G) can be swapped in for real university deployment** without rewriting the app. That's your "scales to production" slide.
- **Be explicit in the write-up** that Option B (whole seated class from one existing wide cam) is *not* reliable with typical installed hardware, and explain the pixel math. Reviewers respect a candidate who knows this; it's a differentiator.

---

## 6. iOS integration story (what the boot camp asked for)

Even with heavy recognition running server-side, the native-iOS surface is rich and real:

- **AVFoundation** — live camera capture (enrollment; and Option C recognition)
- **Vision** (`VNDetectFaceRectanglesRequest`, `VNDetectFaceLandmarksRequest`, `VNDetectFaceCaptureQualityRequest`) — face detection, quality gating, landmark-based **liveness** (blink / head-turn) so a held-up photo fails
- **Core ML** — run a face-embedding model **on-device** for enrollment and Option-C recognition (convert FaceNet/ArcFace via `coremltools`)
- **AVFoundation metadata / VisionKit** — scan a **room QR code** to prove which room the teacher is in
- **Core Bluetooth** — optional BLE room beacon as an alternative room-presence signal (this is BLE used for its *right* job — "which room," not attendance itself)
- **LocalAuthentication (Face ID)** — biometric app unlock for the teacher
- **Keychain** — secure token storage
- **URLSession** (TLS) — secure API to the server
- **UserNotifications** — attendance-confirmed push

---

## 7. Open risks / to validate with the university later

1. **Does the university VMS expose ONVIF Profile G or a documented export API?** (Almost all modern ones do; confirm the specific VMS.)
2. **Where are the cameras physically pointed** in target rooms — faces or backs of heads?
3. **Camera resolution** in target rooms (drives whether Option A/B is viable).
4. **Legal/consent**: biometric data is legally "sensitive" in most jurisdictions (GDPR Art. 9, India DPDP Act, US state BIPA-style laws). University must be the data controller with a documented consent + retention policy. Enrollment must capture consent.
5. **Clock sync** between the iOS trigger and the recording server (so the right 5s slice is pulled).

---

## 8. Bottom line

- **Your architecture is real and standard.** Pulling recorded clips by timestamp is a solved problem (ONVIF Profile G).
- **The only thing that would fail in practice** is recognizing a whole seated class from one existing wide-angle camera — the faces are ~15 px between the eyes when you need ~64. That's physics, not code.
- **The fix is the entrance-recognition pattern** (what working deployments use), which keeps your entire server-pull design intact and actually meets the pixel budget.
- **For the boot camp**, capture on the **iPhone/iPad** at close range so it genuinely works and showcases native iOS, while architecting for CCTV swap-in later.

**Sources:**
- ONVIF Profile G (recording search/retrieval/export standard): https://www.onvif.org/profiles/profile-g/
- Enhancing Classroom Attendance with Face Recognition through CCTV (ScienceDirect): https://www.sciencedirect.com/science/article/pii/S1877050925016655
- CCTV-Based Deep Face Recognition attendance case study (MDPI): https://www.mdpi.com/2073-8994/12/2/307
- Where CCTV Face Recognition for Attendance Works Best (entrance-based, real-world): https://www.timeteccloud.com/blog/where-cctv-with-face-recognition-works-best-for-attendance-real-world-applications/
- Kairos face recognition best practices (64 px inter-eye minimum): https://face.kairos.com/docs/api/best-practices
- Resolution considerations for face recognition accuracy (BriefCam): https://www.briefcam.com/resources/videos/resolution-considerations-for-face-recognition-accuracy/
