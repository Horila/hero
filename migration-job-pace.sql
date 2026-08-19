-- ============================================================
-- Job pace / ETA tracking. One row per job_date holding which job
-- is currently being cast, when it started, and the current
-- tons/hour speed — main.html uses this to project a rough start
-- time for every job below it in the list. Authenticated-only
-- (main.html feature, no trolley/anon involvement), synced across
-- devices the same way additions is.
-- ============================================================

create table if not exists job_pace (
  job_date date primary key,
  current_job_id uuid references jobs(id) on delete set null,
  started_at timestamptz,
  tons_per_hour numeric,
  updated_at timestamptz not null default now()
);

alter table job_pace enable row level security;
revoke all on job_pace from anon, authenticated;

drop policy if exists "authenticated full access to job_pace" on job_pace;
create policy "authenticated full access to job_pace"
  on job_pace for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

grant select, insert, update, delete on job_pace to authenticated;
