-- Supabase / Postgres migration — the schema.sql tables in Postgres form.
-- Apply with the Supabase MCP (apply_migration) or `supabase db push`.
-- Differences from the SQLite prototype: gen_random_uuid() defaults, TIMESTAMPTZ,
-- and a real pgvector column for fast similarity search.

create extension if not exists vector;

-- ── Org / physical ───────────────────────────────────────────────────────────
create table institution (
    id          uuid primary key default gen_random_uuid(),
    name        text not null,
    timezone    text not null default 'UTC',
    created_at  timestamptz not null default now()
);
create table building (
    id              uuid primary key default gen_random_uuid(),
    institution_id  uuid not null references institution(id),
    name            text not null
);
create table room (
    id          uuid primary key default gen_random_uuid(),
    building_id uuid not null references building(id),
    code        text not null,
    capacity    int
);
create table camera (
    id              uuid primary key default gen_random_uuid(),
    room_id         uuid not null references room(id),
    vms_camera_ref  text,
    stream_uri      text,
    resolution_w    int,
    resolution_h    int,
    faces_students  boolean not null default true,
    is_active       boolean not null default true
);

-- ── People ───────────────────────────────────────────────────────────────────
create table app_user (
    id              uuid primary key default gen_random_uuid(),
    institution_id  uuid not null references institution(id),
    sso_subject     text unique,
    email           text unique,
    full_name       text not null,
    role            text not null check (role in ('teacher','admin')),
    is_active       boolean not null default true,
    created_at      timestamptz not null default now()
);
create table student (
    id              uuid primary key default gen_random_uuid(),
    institution_id  uuid not null references institution(id),
    register_no     text not null,
    roll_no         text,
    full_name       text not null,
    program         text,
    batch_year      int,
    created_at      timestamptz not null default now(),
    unique (institution_id, register_no)
);

-- ── Biometric (sensitive) ────────────────────────────────────────────────────
create table consent (
    id              uuid primary key default gen_random_uuid(),
    student_id      uuid not null references student(id),
    policy_version  text not null,
    granted_at      timestamptz not null default now(),
    granted_by      uuid,
    revoked_at      timestamptz
);
create table face_template (
    id              uuid primary key default gen_random_uuid(),
    student_id      uuid not null references student(id),
    embedding       vector(128) not null,          -- SFace 128-d; vector(512) for ArcFace
    model_version   text not null,
    quality_score   real,
    enrolled_at     timestamptz not null default now(),
    consent_id      uuid references consent(id),
    is_active       boolean not null default true
);

-- ── Academic structure ───────────────────────────────────────────────────────
create table course (
    id              uuid primary key default gen_random_uuid(),
    institution_id  uuid not null references institution(id),
    code            text not null,
    title           text not null
);
create table section (
    id          uuid primary key default gen_random_uuid(),
    course_id   uuid not null references course(id),
    term        text not null,
    teacher_id  uuid not null references app_user(id),
    room_id     uuid not null references room(id)
);
create table section_roster (
    section_id  uuid not null references section(id),
    student_id  uuid not null references student(id),
    primary key (section_id, student_id)
);
create table schedule (
    id          uuid primary key default gen_random_uuid(),
    section_id  uuid not null references section(id),
    day_of_week int not null,
    start_time  text not null,
    end_time    text not null
);

-- ── Attendance ───────────────────────────────────────────────────────────────
create table attendance_session (
    id            uuid primary key default gen_random_uuid(),
    section_id    uuid not null references section(id),
    teacher_id    uuid not null references app_user(id),
    room_id       uuid not null references room(id),
    camera_id     uuid references camera(id),
    capture_path  text not null check (capture_path in ('cctv','iphone','webcam')),
    triggered_at  timestamptz not null default now(),
    clip_ref      text,
    status        text not null default 'processing'
                  check (status in ('processing','review','submitted','failed'))
);
create table attendance_record (
    id           uuid primary key default gen_random_uuid(),
    session_id   uuid not null references attendance_session(id),
    student_id   uuid not null references student(id),
    status       text not null check (status in ('present','absent')),
    source       text not null check (source in ('auto','manual_override')),
    confidence   real,
    detected_at  timestamptz,
    unique (session_id, student_id)
);

-- ── Integrity ────────────────────────────────────────────────────────────────
create table audit_log (
    id             uuid primary key default gen_random_uuid(),
    actor_user_id  uuid references app_user(id),
    action         text not null,
    entity         text not null,
    entity_id      text,
    detail         jsonb,
    at             timestamptz not null default now()
);

create index idx_face_student   on face_template(student_id);
create index idx_roster_section on section_roster(section_id);
create index idx_record_session on attendance_record(session_id);
create index idx_audit_entity   on audit_log(entity, entity_id);

-- Fast cosine similarity search over enrolled faces (roster-scoped in queries):
create index idx_face_embedding on face_template
    using ivfflat (embedding vector_cosine_ops) with (lists = 100);
