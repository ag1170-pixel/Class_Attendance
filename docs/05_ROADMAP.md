# What's Built vs What's Left — App Developer's Roadmap

An honest gap analysis: what exists today, and everything a real, shippable
attendance app still needs. Ordered by what unblocks the most.

---

## ✅ Done and verified

- **Recognition engine** — detect → track → recognise-once, tested on real faces (true-positive, discrimination, pixel-gate).
- **Backend logic** — schema + services with consent-gate, RBAC, workflow guard, audit; 5/5 tests.
- **Cloud database** — Supabase project `mystjdepvvmfihcpiftx` live: schema applied, demo class seeded, RLS on every table.
- **Camera → recognition → DB** — `backend.live` writes attendance to the DB (proven end-to-end).
- **UI** — interactive prototype (teacher + student, iOS tab bar, motion), works in iPhone Safari.
- **iOS app** — SwiftUI screens + design system (needs an Xcode project to build).

---

## 🔧 What's left, by priority

### P0 — Make it a real connected app (the current gap)

1. **Authentication (Supabase Auth).** Replace the demo `X-User-Id` / fake Face ID with real accounts: teacher email/password or university SSO, JWT sessions, sign-out. Students get accounts to manage their own consent.
2. **Where recognition runs.** Python can't run on the iPhone or inside Supabase. Two real options:
   - **On-device (CoreML):** convert the face model to Core ML, recognise on the iPhone, write results to Supabase. Best for the iPhone fallback; no server to host. Needs the model conversion.
   - **Hosted service:** deploy the Python recognition + API to a small host (Render / Railway / Fly.io) that the phone and CCTV can reach. Best for the CCTV path.
3. **iOS ↔ Supabase.** Wire the app to the cloud: either the Supabase Swift SDK directly (with RLS policies) or through the hosted API. Right now the app points at `localhost`.
4. **RLS policies.** Tables have RLS *on* with no policies (locked down — correct default). Add policies matching the chosen access model so the app can read/write what it should, and nothing more. Keep `face_template` strictly server-only.
5. **Backend → Supabase connection.** `backend.live` currently uses local SQLite. Point it at Supabase (Postgres + pgvector) via a connection string in `.env` so the Mac-camera demo writes to the cloud DB.

### P1 — MVP completeness

6. **Real enrollment at scale** — import a class roster (CSV), enrol many students, store consent, support re-enrolment and multiple templates per face.
7. **Admin panel** — manage institutions, rooms, cameras, courses, sections, rosters, teachers (today these only exist as seed data).
8. **Attendance reports** — per-student and per-class history, % attendance, CSV export, and a path to push into the university academia CRM.
9. **Offline & errors** — capture when the network drops and sync later; timeouts, retries, and clear error states everywhere.
10. **iOS app packaging** — a real Xcode project, app icon, launch screen, `NSCameraUsageDescription` / `NSFaceIDUsageDescription`, and a TestFlight/dev build to run on your iPhone.

### P2 — Production hardening

11. **Real CCTV/VMS** — ONVIF Profile G client to pull clips from the university NVR; camera↔room admin mapping; multiple cameras per room.
12. **Notifications** — tell a student when they were marked absent (catch errors fast); remind teachers at class time.
13. **Security & compliance** — encrypt embeddings at rest, secrets management, retention automation, consent-revocation → data deletion, and a written DPDP/GDPR posture.
14. **Second-pass recognition** — an optional random mid-class check so "get marked then leave" fails.
15. **Accuracy tuning** — measure recognition on real target-room footage and tune thresholds; this is what makes or breaks the real deployment.

### P3 — Scale & polish

16. Analytics dashboard, multi-institution tenancy, load testing, CI/CD, monitoring/logging, on-call runbook.

---

## The two decisions that unblock everything

Almost all of P0 hinges on two choices:

- **A. Where does recognition run?** On-device CoreML (simplest for an iPhone demo, no server) vs a hosted Python service (needed for CCTV).
- **B. How does the app reach data?** iPhone → Supabase directly (fastest to a working iPhone app) vs iPhone → hosted API → Supabase (needed once recognition is server-side).

Recommended for **Monday / your iPhone**: on-device capture + **iPhone → Supabase directly** for the data, recognition run on the Mac via `backend.live` writing to the same Supabase. That gives a real iPhone app reading live attendance, with real recognition happening on the Mac camera — all sharing one cloud DB — without hosting anything.

---

## Immediate next steps (this week)

1. Connect `backend.live` to Supabase (Postgres connection in `.env`) — the Mac camera writes attendance to the cloud.
2. Add minimal RLS policies so a signed-in teacher can read their sections + attendance.
3. Stand up the iOS app as a real Xcode project pointed at Supabase (read schedule + live attendance review).
4. (Stretch) Convert the face model to Core ML for on-device enrolment on the iPhone.
