-- ============================================================
-- URGENT FIX: migration-scope-anon-counts-to-published-day.sql added
-- EXISTS(select ... from jobs ...) checks to the counts anon insert/update
-- policies, but anon has no read access to jobs at all (jobs' only policy
-- is authenticated-only, no anon grant either) — so every anon write to
-- counts now fails with "permission denied for table jobs", breaking
-- trolley.html's saves entirely (cores, dip, still-making, notes, all of
-- it), not just notes.
--
-- Give anon just enough to make that EXISTS check work: read access to
-- jobs.id/jobs.job_date, and only for rows on today's published day — same
-- data-minimization as everywhere else anon touches jobs data (trolley_jobs
-- already curates which columns are exposed; this does not change that).
-- Run once in Supabase SQL Editor, immediately.
-- ============================================================

drop policy if exists "anon can read published-day jobs for counts check" on jobs;
create policy "anon can read published-day jobs for counts check"
  on jobs for select
  to anon
  using (
    job_date = (select job_date from published_day where id = 1)
  );

grant select (id, job_date) on jobs to anon;
