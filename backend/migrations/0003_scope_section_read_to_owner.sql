-- Phase 1d: a teacher's phone (auth token) reads only THEIR OWN classes.
-- Pre-login anon read is unchanged.
drop policy if exists "authenticated read" on section;
create policy "teacher reads own sections" on section for select to authenticated
  using (teacher_id = public.current_teacher_id());
