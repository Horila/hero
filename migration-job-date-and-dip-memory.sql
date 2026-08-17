-- ============================================================
-- 1. Adds job_date to jobs, so each day starts on a blank sheet
--    without deleting prior days (uniqueness becomes am_number +
--    date instead of am_number alone).
-- 2. Adds dip_items: remembers which item numbers need dipping,
--    so future jobs with the same item auto-tick the box.
-- Run once in Supabase SQL Editor.
-- ============================================================

-- ---------- job_date ----------
alter table jobs add column if not exists job_date date not null default current_date;

drop index if exists jobs_am_number_idx;
create unique index if not exists jobs_am_number_date_idx on jobs (am_number, job_date);

-- ---------- dip_items (dipping memory, by item number) ----------
create table if not exists dip_items (
  item_number text primary key,
  needs_dipping boolean not null default true,
  updated_at timestamptz default now()
);

alter table dip_items enable row level security;

drop policy if exists "authenticated full access to dip_items" on dip_items;
create policy "authenticated full access to dip_items"
  on dip_items for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

grant select, insert, update, delete on dip_items to authenticated;

-- ---------- Recreate trolley_jobs to expose job_date ----------
drop view if exists trolley_jobs;

create view trolley_jobs as
select
  j.id as job_id,
  j.am_number,
  j.planned_qty,
  j.mingzhi_hansberg_no,
  j.job_date,
  j.needs_dipping,
  coalesce(c.group_a_cores, 0) as group_a_cores,
  coalesce(c.group_a_trolleys, 0) as group_a_trolleys,
  coalesce(c.group_b_cores, 0) as group_b_cores,
  coalesce(c.group_b_trolleys, 0) as group_b_trolleys,
  coalesce(c.comment, '') as comment,
  coalesce(c.still_making, false) as still_making,
  coalesce(
    c.manual_total_override,
    coalesce(c.group_a_cores, 0) * coalesce(c.group_a_trolleys, 0)
    + coalesce(c.group_b_cores, 0) * coalesce(c.group_b_trolleys, 0)
  ) as total_cores
from jobs j
left join counts c on c.job_id = j.id
order by j.created_at desc;

grant select on trolley_jobs to anon;
-- job_summary already exposes job_date via "j.*" — no change needed there.
