-- ============================================================
-- Replaces the single jobs.notes text column (added in
-- migration-job-notes.sql, never shipped/used) with a proper job_notes
-- table: a timestamped, append-only log of notes per job, each
-- optionally flagged visible_to_trolley so it also surfaces on
-- trolley.html (read-only there, scoped to the published day like
-- counts/chat_messages).
-- ============================================================

drop view if exists job_summary;
alter table jobs drop column if exists notes;

create table if not exists job_notes (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references jobs(id) on delete cascade,
  body text not null,
  visible_to_trolley boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists job_notes_job_id_idx on job_notes (job_id);

alter table job_notes enable row level security;
revoke all on job_notes from anon, authenticated;

drop policy if exists "authenticated can read job_notes" on job_notes;
create policy "authenticated can read job_notes"
  on job_notes for select to authenticated using (auth.role() = 'authenticated');

drop policy if exists "full access can insert job_notes" on job_notes;
create policy "full access can insert job_notes"
  on job_notes for insert to authenticated with check (is_full_access());

drop policy if exists "full access can update job_notes" on job_notes;
create policy "full access can update job_notes"
  on job_notes for update to authenticated using (is_full_access()) with check (is_full_access());

drop policy if exists "full access can delete job_notes" on job_notes;
create policy "full access can delete job_notes"
  on job_notes for delete to authenticated using (is_full_access());

grant select, insert, update, delete on job_notes to authenticated;

-- anon (trolley boys): read-only, only notes explicitly marked visible, only
-- for jobs on the currently published day — same trust boundary as
-- counts/chat_messages.
drop policy if exists "anon can read trolley-visible notes for published-day jobs" on job_notes;
create policy "anon can read trolley-visible notes for published-day jobs"
  on job_notes for select
  to anon
  using (
    visible_to_trolley = true
    and exists (
      select 1 from jobs j, published_day p
      where j.id = job_notes.job_id and p.id = 1 and j.job_date = p.job_date
    )
  );

grant select on job_notes to anon;

create view job_summary as
select
  j.*,
  coalesce(c.comment_text, '') as comment,
  coalesce(c.still_making_flag, false) as still_making,
  coalesce(c.counted_total, 0) as counted_total,
  case
    when j.is_doubles then coalesce(c.counted_total, 0) / 2.0
    else coalesce(c.counted_total, 0)
  end as effective_qty,
  round(
    (
      case
        when j.is_doubles then coalesce(c.counted_total, 0) / 2.0
        else coalesce(c.counted_total, 0)
      end
    ) * coalesce(j.weight_kg, 0) / 1000.0,
    3
  ) as tonnage
from jobs j
left join (
  select
    job_id,
    coalesce(
      manual_total_override,
      coalesce(group_a_cores, 0) * coalesce(group_a_trolleys, 0)
      + coalesce(group_b_cores, 0) * coalesce(group_b_trolleys, 0)
    ) as counted_total,
    still_making as still_making_flag,
    comment as comment_text
  from counts
) c on c.job_id = j.id
order by j.job_date desc, j.sort_order asc;

grant select on job_summary to authenticated;
