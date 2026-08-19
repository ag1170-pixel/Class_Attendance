-- Phase 1 (live app): a signed-in teacher manages the face dataset for THEIR OWN
-- classes only. Ownership chain:
--   auth.uid() -> app_user.auth_user_id -> section.teacher_id
--               -> section_roster -> student -> face_template / consent
--
-- Applied to Supabase project mystjdepvvmfihcpiftx. Verified end-to-end with a
-- real teacher token: read own roster, create consent, insert a 128-d face
-- template, read it back; anon is denied.

-- ── ownership helpers (SECURITY DEFINER -> bypass RLS inside, avoids recursion) ──
create or replace function public.current_teacher_id() returns uuid
  language sql stable security definer set search_path = public as
$$ select id from app_user where auth_user_id = auth.uid() limit 1 $$;

create or replace function public.teacher_owns_section(sec uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from section
                 where id = sec and teacher_id = public.current_teacher_id()) $$;

create or replace function public.teacher_owns_student(sid uuid) returns boolean
  language sql stable security definer set search_path = public as
$$ select exists(select 1 from section_roster sr
                 join section s on s.id = sr.section_id
                 where sr.student_id = sid
                   and s.teacher_id = public.current_teacher_id()) $$;

-- Helpers are for RLS only — not public RPC endpoints.
revoke execute on function public.current_teacher_id()          from public, anon;
revoke execute on function public.teacher_owns_section(uuid)    from public, anon;
revoke execute on function public.teacher_owns_student(uuid)    from public, anon;
grant  execute on function public.current_teacher_id()          to authenticated;
grant  execute on function public.teacher_owns_section(uuid)    to authenticated;
grant  execute on function public.teacher_owns_student(uuid)    to authenticated;

-- ── face_template: read/enroll/deactivate for students in my classes ─────────────
create policy "teacher read templates"   on face_template for select to authenticated
  using (public.teacher_owns_student(student_id));
create policy "teacher insert templates" on face_template for insert to authenticated
  with check (public.teacher_owns_student(student_id));
create policy "teacher update templates" on face_template for update to authenticated
  using (public.teacher_owns_student(student_id))
  with check (public.teacher_owns_student(student_id));

-- ── consent: same scope (biometric write requires an active consent row) ─────────
create policy "teacher read consent"   on consent for select to authenticated
  using (public.teacher_owns_student(student_id));
create policy "teacher insert consent" on consent for insert to authenticated
  with check (public.teacher_owns_student(student_id));
create policy "teacher update consent" on consent for update to authenticated
  using (public.teacher_owns_student(student_id))
  with check (public.teacher_owns_student(student_id));

-- ── roster management: add/remove students in my own sections ────────────────────
create policy "teacher add roster"    on section_roster for insert to authenticated
  with check (public.teacher_owns_section(section_id));
create policy "teacher remove roster" on section_roster for delete to authenticated
  using (public.teacher_owns_section(section_id));

-- ── create a brand-new student (institution-level; tighten in a later phase) ─────
create policy "teacher insert student" on student for insert to authenticated
  with check (true);

-- ── reference data the phone reads when using the teacher's auth token ───────────
create policy "authenticated read course"   on course   for select to authenticated using (true);
create policy "authenticated read room"     on room     for select to authenticated using (true);
create policy "authenticated read building" on building for select to authenticated using (true);
create policy "authenticated read schedule" on schedule for select to authenticated
  using (public.teacher_owns_section(section_id));
