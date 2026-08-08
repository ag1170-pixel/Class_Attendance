# System Architecture, Database & Security

Full-system design for the camera-based class attendance system. Scope: iOS app + backend + recognition + CCTV integration.

---

## 1. Components

```
┌─────────────────────────┐          ┌──────────────────────────────────────┐
│      iOS App (SwiftUI)   │          │            OUR BACKEND                │
│  Teacher + Enrollment    │          │                                      │
│                          │  HTTPS   │  ┌────────────────────────────────┐  │
│  • SSO + Face ID login   │◄────────►│  │ API + Auth Gateway (RBAC/JWT)  │  │
│  • Today's classes       │          │  └───────────────┬────────────────┘  │
│  • "Take Attendance"     │          │                  │                    │
│  • Room QR / BLE confirm │          │  ┌───────────────▼────────────────┐  │
│  • Tick/cross review     │          │  │ Attendance Orchestration Svc   │  │
│  • Enrollment capture    │          │  └───┬───────────────────┬────────┘  │
└─────────────────────────┘          │      │                   │           │
                                      │  ┌───▼─────────┐   ┌─────▼────────┐  │
┌─────────────────────────┐          │  │ VMS Adapter │   │ Recognition  │  │
│  University Recording    │  ONVIF   │  │ (Profile G) │──►│ Service (GPU)│  │
│  Server (NVR / VMS)      │◄─Profile─│  │ pull 5s clip│   │ YOLOv8+track │  │
│  continuous CCTV record  │    G     │  └─────────────┘   │ +ArcFace     │  │
└─────────────────────────┘          │                    └─────┬────────┘  │
                                      │                          │           │
                                      │  ┌───────────────────────▼────────┐  │
                                      │  │ PostgreSQL + pgvector           │  │
                                      │  │ Object store (transient clips)  │  │
                                      │  │ Redis (job queue)               │  │
                                      │  └─────────────────────────────────┘  │
                                      └──────────────────────────────────────┘
```

- **iOS App** — teacher control + review, and student/admin enrollment capture.
- **API + Auth Gateway** — authenticates, enforces role-based access, rate-limits, signs trigger requests.
- **Attendance Orchestration** — the workflow brain: create session → get clip → run recognition → build review list → store on submit.
- **VMS Adapter** — talks to the university recording server via **ONVIF Profile G** (or vendor SDK) to pull the 5s clip for (camera, timestamp).
- **Recognition Service (GPU)** — the "recognize once, then track" pipeline (see `02_ALGORITHM.md`).
- **PostgreSQL + pgvector** — relational data + face embedding vectors for similarity search.
- **Object store** — transient clip storage; auto-purged per retention policy.
- **Redis** — async job queue (recognition can take a few seconds).

---

## 2. End-to-end flow (attendance)

1. Teacher opens app → **SSO + Face ID** unlock.
2. App shows **today's scheduled classes** for this teacher.
3. Teacher opens the current class → **confirms room** (scan room QR or BLE beacon in range) — proves physical presence, anti-teacher-proxy.
4. Teacher taps **"Take Attendance"** → app sends a **signed trigger** `{section_id, room_id, timestamp}`.
5. Orchestration creates an `attendance_session (status=processing)`, resolves `room → camera`.
6. **VMS Adapter** pulls the **5s clip** for that camera at that timestamp (or the app uploads the teacher's 5s iPhone video for the fallback path).
7. **Recognition Service** loads the **class roster embeddings**, runs the pipeline → present/absent + confidence.
8. Session → `status=review`; app shows the **tick/cross review screen**, pre-filled, low-confidence flagged.
9. Teacher corrects any errors → **Submit** → records finalized (`source=auto` or `manual_override`), `status=submitted`, **audit-logged**.
10. Optional: sync to the university academia CRM.

---

## 3. Database schema (clean, normalized)

Postgres. `pgvector` for embeddings. UUID primary keys. `snake_case`. Every table has `created_at`, `updated_at`.

```sql
-- ── Org / physical ────────────────────────────────────────────
institution(id, name, timezone)
building(id, institution_id → institution, name)
room(id, building_id → building, code, capacity)
camera(id, room_id → room, vms_camera_ref, stream_uri,
       resolution_w, resolution_h, faces_students BOOL,  -- is it pointed at faces?
       is_active BOOL)

-- ── People ────────────────────────────────────────────────────
app_user(id, institution_id → institution, sso_subject, email,
         full_name, role ENUM('teacher','admin'), is_active BOOL)
student(id, institution_id → institution, register_no UNIQUE, roll_no,
        full_name, program, batch_year)

-- ── Biometric (sensitive; encrypted) ──────────────────────────
consent(id, student_id → student, policy_version, granted_at,
        granted_by, revoked_at NULL)
face_template(id, student_id → student, embedding VECTOR(512),
              model_version, quality_score, enrolled_at,
              consent_id → consent, is_active BOOL)
-- embedding column encrypted at rest; access strictly controlled

-- ── Academic structure ────────────────────────────────────────
course(id, institution_id → institution, code, title)
section(id, course_id → course, term, teacher_id → app_user,
        room_id → room)                         -- a specific offering
section_roster(section_id → section, student_id → student,
               PRIMARY KEY(section_id, student_id))
schedule(id, section_id → section, day_of_week, start_time, end_time)

-- ── Attendance ────────────────────────────────────────────────
attendance_session(id, section_id → section, teacher_id → app_user,
                   room_id → room, camera_id → camera NULL,
                   capture_path ENUM('cctv','iphone'),
                   triggered_at, clip_ref NULL,
                   status ENUM('processing','review','submitted','failed'))
attendance_record(id, session_id → attendance_session, student_id → student,
                  status ENUM('present','absent'),
                  source ENUM('auto','manual_override'),
                  confidence NUMERIC NULL, detected_at NULL,
                  UNIQUE(session_id, student_id))

-- ── Integrity ─────────────────────────────────────────────────
audit_log(id, actor_user_id → app_user, action, entity, entity_id,
          detail JSONB, at)
```

**Design notes**
- **Roster-scoped matching**: recognition compares only against `face_template`s of students in that `section_roster` — fast + accurate.
- **`camera.faces_students`** flags whether a room's camera actually sees faces (vs backs of heads) — drives whether CCTV or iPhone path is used.
- **`source` on each record** distinguishes machine guess vs teacher override — critical for trust and analytics.
- **`consent`** linked to every `face_template` — no biometric data without a consent record.
- Biometric tables isolated so access can be locked down separately from ordinary data.

---

## 4. Security model

**Authentication & authorization**
- **University SSO (OAuth2/OIDC)** preferred; JWT access (short-lived) + refresh tokens.
- **RBAC**: `teacher` (own sections only), `admin` (institution scope). Students have no write access.
- **Face ID / Touch ID** unlock on device; tokens in **Keychain**; **TLS + certificate pinning**.

**Data protection**
- **Face embeddings encrypted at rest** (KMS-managed keys); DB-level encryption.
- **Clips are transient** — processed then purged on a retention timer; **never sent to student devices**; university is the data custodian.
- **Least-privilege VMS credentials** — read-only clip export, scoped to needed cameras.

**Integrity / anti-abuse**
- **Signed, time-boxed triggers** — an attendance trigger is only valid for the scheduled class window + confirmed room; prevents replayed/spoofed triggers.
- **Full audit trail** — every mark, override, and biometric access logged (`audit_log`).
- **Rate limiting + input validation** on all endpoints.
- **NTP clock sync** so the trigger timestamp maps to the correct 5s of recording.

**Legal / privacy**
- Biometric data is legally "sensitive" (GDPR Art. 9, India DPDP Act, US BIPA-style laws). University = data controller; documented **consent at enrollment**, **purpose limitation**, **retention + deletion** policy, and a revocation path (`consent.revoked_at` → deactivate templates).

---

## 5. iOS app structure (SwiftUI)

```
ClassAttendance/
├── App/                     app entry, DI, config
├── Core/
│   ├── Networking/          URLSession async client, auth interceptor, cert pinning
│   ├── Auth/                SSO + LocalAuthentication (Face ID), Keychain
│   └── Models/              Codable DTOs (Session, Student, Record…)
├── Features/
│   ├── Login/
│   ├── Schedule/            today's classes
│   ├── Attendance/
│   │   ├── Trigger/         room QR (VisionKit) / BLE (CoreBluetooth) confirm
│   │   ├── Processing/
│   │   └── Review/          tick/cross list, confidence badges
│   ├── Enrollment/          AVFoundation capture + Vision quality gate + consent
│   └── Settings/
└── Resources/               CoreML model (YOLOv8 for on-device fallback), assets
```

**Native iOS frameworks used:** SwiftUI, AVFoundation, Vision, Core ML, VisionKit (QR), Core Bluetooth, LocalAuthentication, Keychain Services, UserNotifications, URLSession (async/await).

---

## 6. Backend tech choices

- **Recognition service:** Python + **FastAPI**; `ultralytics` (YOLOv8 + BoT-SORT), `insightface` (ArcFace), ONNX/TensorRT for speed. GPU host.
- **API/orchestration:** FastAPI (one language keeps it simple) — or Node if preferred.
- **DB:** PostgreSQL + **pgvector**.
- **Queue:** Redis (async recognition jobs).
- **Storage:** S3-compatible object store (MinIO for dev) for transient clips.
- **VMS integration:** ONVIF Profile G client library; vendor SDK adapters behind a common interface.
- **Deploy:** Docker Compose (dev) → the university's servers (prod, on-prem so data stays on campus).

---

## 7. Recommended build order

1. **Recognition prototype** (Python) on a sample classroom video — prove accuracy, tune thresholds. *De-risks the hardest part first.*
2. **Backend API + DB schema** — auth, sessions, review/submit, `/recognize` endpoint.
3. **iOS app** — login → schedule → trigger → review → submit (talking to the API).
4. **Enrollment flow** (iOS capture + consent).
5. **VMS adapter** (ONVIF Profile G) for real CCTV clips; iPhone-video fallback path.
6. **Hardening** — security, audit, retention, polish.

Building the recognition prototype first means we confirm the make-or-break part works before investing in the app and backend around it.
