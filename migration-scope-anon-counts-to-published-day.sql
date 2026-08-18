-- ============================================================
-- The anon insert/update policies on counts had no scoping at all
-- (using(true)/with check(true)) — anyone holding the public anon key
-- (visible in trolley.html's source on the public GH Pages site) could
-- overwrite counts for any job on any day, not just the currently
-- published one trolley.html actually shows. Scope anon writes to jobs
-- whose job_date matches published_day. authenticated keeps unrestricted
-- access (needed for the carry-forward insert in
-- migration-authenticated-counts-insert.sql, which writes counts for a
-- new, not-yet-published day).
-- Run once in Supabase SQL Editor.
-- ============================================================

drop policy if exists "anon can insert counts" on counts;
drop policy if exists "anon can update counts" on counts;

create policy "anon can insert counts for published day"
  on counts for insert
  to anon
  with check (
    exists (
      select 1 from jobs j, published_day p
      where j.id = counts.job_id and p.id = 1 and j.job_date = p.job_date
    )
  );

create policy "anon can update counts for published day"
  on counts for update
  to anon
  using (
    exists (
      select 1 from jobs j, published_day p
      where j.id = counts.job_id and p.id = 1 and j.job_date = p.job_date
    )
  )
  with check (
    exists (
      select 1 from jobs j, published_day p
      where j.id = counts.job_id and p.id = 1 and j.job_date = p.job_date
    )
  );

drop policy if exists "authenticated full access to counts writes" on counts;
create policy "authenticated full access to counts writes"
  on counts for all
  to authenticated
  using (true)
  with check (true);
