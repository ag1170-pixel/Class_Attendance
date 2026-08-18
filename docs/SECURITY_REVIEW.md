# Security review — 2026-08-18

Self-pentest of the live Supabase backend, following the same methodology as
[Strix](https://github.com/usestrix/strix) (a multi-agent pentesting tool): whitebox
source triage → secrets scan → priority-ordered vuln testing (auth bypass, broken
access control/IDOR, injection, exposed secrets) → confirm exploitability with a
minimal proof-of-concept → fix → re-verify.

Strix itself needs a paid LLM API key it doesn't have here, so this pass was done
directly, using its published skill files (`skills/vulnerabilities/*.md`,
`skills/scan_modes/quick.md`) as the checklist, plus Supabase's own security advisor.

## Scope
`backend/` (local Python — SQLite, RBAC, consent gating) and the live Supabase
project (`mystjdepvvmfihcpiftx`) that both the Mac and iPhone read/write over its
public REST API. iOS/Swift source was reviewed but not fuzzed.

## Findings

### 1. CRITICAL — anon key could forge attendance and read student PII (FIXED)
The Supabase publishable key ships inside the iPhone app binary, so it must be
treated as public — anyone can extract it. RLS policies added during an earlier
session (`anon insert ... with check (true)`) let that public key:

- **Forge attendance**: `INSERT` an `attendance_session` for any class, then an
  `attendance_record` marking any student `present` — the exact fraud face
  recognition exists to prevent, achievable with zero login, in two curl calls.
- **Read the full student roster** (`student` table: names + register numbers).

**Proof of concept** (run 2026-08-18, artifacts cleaned up immediately after):
```
curl .../student?select=register_no,full_name         -> full roster, no auth
curl -X POST .../attendance_session {...}              -> HTTP 201, forged session
curl -X POST .../attendance_record {"status":"present"} -> HTTP 201, forged "present"
```
All three succeeded before the fix; all three return `401`/`[]` after.

**Fix**: dropped the `anon insert`/`anon read` policies on `attendance_session`,
`attendance_record`, and the `anon read` policy on `student` (migration
`fix_anon_write_and_pii_exposure`). Verified with the same PoCs post-fix — writes now
`401` with an RLS-violation message, PII reads return `[]`. Legitimate reads
(sections/schedule, needed for "today's classes") were left untouched and still work.

**Consequence — known gap, not yet fixed**: with no anon writes allowed, the app's
own "Submit Attendance" now also fails until a real teacher login exists
(Supabase Auth). This is the correct tradeoff for now (no auth ⇒ no write access),
but it means cloud sync is currently broken end-to-end. **Next step: add Supabase
Auth for teachers and scope the insert policies to `auth.uid() = teacher_id`.**

### 2. MEDIUM — failed cloud sync was silently swallowed as "success" (FIXED)
Found while fixing #1: both `AttendanceView.submit()` and
`BluetoothAttendanceView`'s submit button called `try? await
Supabase.submitAttendance(...)` — discarding any error. Once #1 was fixed, every
submission would fail (RLS now blocks anon writes) while the UI still showed
"Attendance submitted ✓". A teacher would believe attendance was recorded when it
silently was not, for every class, indefinitely — arguably worse than the original hole.

**Fix**:
- `SupabaseClient.swift`: requests now check the HTTP status explicitly and throw on
  anything outside 2xx, instead of relying on decode failure to (accidentally) surface
  errors.
- `AttendanceView`: added `cloudSynced: Bool?` published state; the submitted screen
  now shows a real error state ("Saved on this phone only — couldn't reach the cloud
  database") with a **Retry** button when the write fails, instead of a false success.
- `BluetoothAttendanceView`: same — the submit button shows an inline failure message
  and stays enabled to retry, rather than flipping to the submitted screen regardless.
- The Mac's `backend/supabase_sink.py` was already safe: `urllib.request.urlopen`
  raises `HTTPError` on non-2xx by default, so `backend.live attend --cloud` already
  fails loudly (uncaught exception) rather than lying. No change needed there.

## Reviewed and OK
- **SQL injection**: `backend/db.py` and `backend/services.py` use parameterized
  queries (`execute(sql, params)`) throughout — no string-built SQL found.
- **Secrets**: no service-role key, DB password, or other secret is hardcoded
  anywhere in the repo — only the intentionally-public `sb_publishable_...` key.
- **RBAC / consent (local backend)**: `AttendanceService` enforces teacher-owns-section
  on session creation, and refuses to write a `face_template` without an active
  `consent` row. Every write is audit-logged.
- **Biometrics**: `face_template` and `consent` tables have RLS enabled with **no**
  policies at all (confirmed via Supabase's advisor) — meaning nothing, not even
  anon, can read or write them over the API. Correct as-is.
- **`vector` extension in `public` schema**: Supabase advisor flagged this (WARN,
  not exploitable on its own) — low priority, move to a dedicated schema when
  convenient.

## Update 2026-08-18 — teacher authentication added, writes restored
Added real Supabase Auth for the teacher (`classattendance.teacher@gmail.com`,
linked to the existing `app_user` row via a new `auth_user_id` column) and scoped
every write policy to `auth.uid()` — a signed-in teacher can only write/read their
**own** sections, never another teacher's or an anonymous request's. Both the camera
flow (`AttendanceView`) and the Bluetooth flow (`BluetoothAttendanceView`) now sign
in via **Settings → Cloud sync → Sign in** before Submit will succeed; the Mac's
`backend.live attend --cloud` signs in the same way via `supabase_sink.py`.

**Verified with the same PoC pattern**: signed-in write to the teacher's own
section → `201`; the same token attempting to write under a *different*
`teacher_id` → `403`; anonymous request → `401`; anonymous student-PII read →
empty. All four checked together in one pass, artifacts cleaned up after each test.

**A build-time bug found and fixed along the way**: the new policies chained
through `app_user` → `section` → `section_roster` → `student` to prove "this
teacher owns this class," but `section` only had an `anon`-role policy — RLS
policies are role-scoped, so a policy written for `anon` does not apply to
`authenticated` requests. That silently zeroed out every nested lookup for a
legitimately signed-in teacher too, not just attackers. Since `section` data
(course/room/schedule) was already fully public via `anon`, granting
`authenticated` the same read closed the gap with no new exposure.

## Summary
| Finding | Severity | Status |
|---|---|---|
| Anon could forge attendance / read student PII | Critical | Fixed |
| Failed writes showed false "submitted" success | Medium | Fixed |
| No teacher authentication (root cause of both) | High | **Fixed** — Supabase Auth, RLS scoped to `auth.uid()` |
| `vector` extension in `public` schema | Low | Open, low priority |
