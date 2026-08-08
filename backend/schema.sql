-- Class Attendance — relational schema (SQLite dialect for the prototype;
-- maps 1:1 to the Postgres design in docs/03_ARCHITECTURE.md §3).
-- Postgres upgrade notes: UUID default gen_random_uuid(); embedding -> VECTOR(128)
-- via pgvector; TIMESTAMPTZ; ENUM types instead of CHECK constraints.

PRAGMA foreign_keys = ON;

-- ── Org / physical ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS institution (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    timezone    TEXT NOT NULL DEFAULT 'UTC',
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS building (
    id              TEXT PRIMARY KEY,
    institution_id  TEXT NOT NULL REFERENCES institution(id),
    name            TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS room (
    id          TEXT PRIMARY KEY,
    building_id TEXT NOT NULL REFERENCES building(id),
    code        TEXT NOT NULL,
    capacity    INTEGER
);

CREATE TABLE IF NOT EXISTS camera (
    id              TEXT PRIMARY KEY,
    room_id         TEXT NOT NULL REFERENCES room(id),
    vms_camera_ref  TEXT,                 -- id used by the university VMS
    stream_uri      TEXT,                 -- rtsp://... or 'webcam:0' for demo
    resolution_w    INTEGER,
    resolution_h    INTEGER,
    faces_students  INTEGER NOT NULL DEFAULT 1,  -- does it actually see faces?
    is_active       INTEGER NOT NULL DEFAULT 1
);

-- ── People ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS app_user (
    id              TEXT PRIMARY KEY,
    institution_id  TEXT NOT NULL REFERENCES institution(id),
    sso_subject     TEXT UNIQUE,
    email           TEXT UNIQUE,
    full_name       TEXT NOT NULL,
    role            TEXT NOT NULL CHECK (role IN ('teacher','admin')),
    is_active       INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS student (
    id              TEXT PRIMARY KEY,
    institution_id  TEXT NOT NULL REFERENCES institution(id),
    register_no     TEXT NOT NULL,
    roll_no         TEXT,
    full_name       TEXT NOT NULL,
    program         TEXT,
    batch_year      INTEGER,
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (institution_id, register_no)
);

-- ── Biometric (sensitive; encrypt embedding at rest in production) ────────────
CREATE TABLE IF NOT EXISTS consent (
    id              TEXT PRIMARY KEY,
    student_id      TEXT NOT NULL REFERENCES student(id),
    policy_version  TEXT NOT NULL,
    granted_at      TEXT NOT NULL DEFAULT (datetime('now')),
    granted_by      TEXT,
    revoked_at      TEXT
);

CREATE TABLE IF NOT EXISTS face_template (
    id              TEXT PRIMARY KEY,
    student_id      TEXT NOT NULL REFERENCES student(id),
    embedding       BLOB NOT NULL,        -- float32[] ; VECTOR(128) in Postgres
    model_version   TEXT NOT NULL,
    quality_score   REAL,
    enrolled_at     TEXT NOT NULL DEFAULT (datetime('now')),
    consent_id      TEXT REFERENCES consent(id),
    is_active       INTEGER NOT NULL DEFAULT 1
);

-- ── Academic structure ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS course (
    id              TEXT PRIMARY KEY,
    institution_id  TEXT NOT NULL REFERENCES institution(id),
    code            TEXT NOT NULL,
    title           TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS section (
    id          TEXT PRIMARY KEY,
    course_id   TEXT NOT NULL REFERENCES course(id),
    term        TEXT NOT NULL,
    teacher_id  TEXT NOT NULL REFERENCES app_user(id),
    room_id     TEXT NOT NULL REFERENCES room(id)
);

CREATE TABLE IF NOT EXISTS section_roster (
    section_id  TEXT NOT NULL REFERENCES section(id),
    student_id  TEXT NOT NULL REFERENCES student(id),
    PRIMARY KEY (section_id, student_id)
);

CREATE TABLE IF NOT EXISTS schedule (
    id          TEXT PRIMARY KEY,
    section_id  TEXT NOT NULL REFERENCES section(id),
    day_of_week INTEGER NOT NULL,         -- 0=Mon … 6=Sun
    start_time  TEXT NOT NULL,            -- 'HH:MM'
    end_time    TEXT NOT NULL
);

-- ── Attendance ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS attendance_session (
    id            TEXT PRIMARY KEY,
    section_id    TEXT NOT NULL REFERENCES section(id),
    teacher_id    TEXT NOT NULL REFERENCES app_user(id),
    room_id       TEXT NOT NULL REFERENCES room(id),
    camera_id     TEXT REFERENCES camera(id),
    capture_path  TEXT NOT NULL CHECK (capture_path IN ('cctv','iphone','webcam')),
    triggered_at  TEXT NOT NULL DEFAULT (datetime('now')),
    clip_ref      TEXT,
    status        TEXT NOT NULL DEFAULT 'processing'
                  CHECK (status IN ('processing','review','submitted','failed'))
);

CREATE TABLE IF NOT EXISTS attendance_record (
    id           TEXT PRIMARY KEY,
    session_id   TEXT NOT NULL REFERENCES attendance_session(id),
    student_id   TEXT NOT NULL REFERENCES student(id),
    status       TEXT NOT NULL CHECK (status IN ('present','absent')),
    source       TEXT NOT NULL CHECK (source IN ('auto','manual_override')),
    confidence   REAL,
    detected_at  TEXT,
    UNIQUE (session_id, student_id)
);

-- ── Integrity ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS audit_log (
    id             TEXT PRIMARY KEY,
    actor_user_id  TEXT REFERENCES app_user(id),
    action         TEXT NOT NULL,
    entity         TEXT NOT NULL,
    entity_id      TEXT,
    detail         TEXT,                  -- JSON
    at             TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_face_student   ON face_template(student_id);
CREATE INDEX IF NOT EXISTS idx_roster_section ON section_roster(section_id);
CREATE INDEX IF NOT EXISTS idx_record_session ON attendance_record(session_id);
CREATE INDEX IF NOT EXISTS idx_audit_entity   ON audit_log(entity, entity_id);
