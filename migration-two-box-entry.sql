-- ============================================================
-- Replaces the open-ended "add trolley" list with 2 fixed boxes
-- per job: each box is a cores-per-trolley number + a trolley
-- counter. Total = (boxA cores × boxA trolleys) + (boxB cores × boxB trolleys).
-- Covers uniform jobs (use box A only) and jobs with 2 different
-- core counts per trolley (box A + box B).
-- Also re-asserts counts table grants/policies to fix
-- "permission denied for table counts".
-- Run once in Supabase SQL Editor.
-- ============================================================

drop view if exists trolley_jobs;
drop view if exists job_summary;

alter table counts drop column if exists trolley_entries;
alter table counts drop column if exists cores_per_trolley;
alter table counts drop column if exists trolley_count;

alter table counts add column if not exists group_a_cores integer default 0;
alter table counts add column if not exists group_a_trolleys integer default 0;
alter table counts add column if not exists group_b_cores integer default 0;
alter table counts add column if not exists group_b_trolleys integer default 0;

create view trolley_jobs as
select
  j.id as job_id,
  j.am_number,
  j.planned_qty,
  j.mingzhi_hansberg_no,
  j.needs_dipping,
  coalesce(c.group_a_cores, 0) as group_a_cores,
  coalesce(c.group_a_trolleys, 0) as group_a_trolleys,
  coalesce(c.group_b_cores, 0) as group_b_cores,
  coalesce(c.group_b_trolleys, 0) as group_b_trolleys,
  coalesce(
    c.manual_total_override,
    coalesce(c.group_a_cores, 0) * coalesce(c.group_a_trolleys, 0)
    + coalesce(c.group_b_cores, 0) * coalesce(c.group_b_trolleys, 0)
  ) as total_cores
from jobs j
left join counts c on c.job_id = j.id
order by j.created_at desc;

create view job_summary as
select
  j.*,
  coalesce(
    c.manual_total_override,
    coalesce(c.group_a_cores, 0) * coalesce(c.group_a_trolleys, 0)
    + coalesce(c.group_b_cores, 0) * coalesce(c.group_b_trolleys, 0)
  ) as counted_total,
  case
    when j.is_doubles then coalesce(
      c.manual_total_override,
      coalesce(c.group_a_cores, 0) * coalesce(c.group_a_trolleys, 0)
      + coalesce(c.group_b_cores, 0) * coalesce(c.group_b_trolleys, 0)
    ) / 2.0
    else coalesce(
      c.manual_total_override,
      coalesce(c.group_a_cores, 0) * coalesce(c.group_a_trolleys, 0)
      + coalesce(c.group_b_cores, 0) * coalesce(c.group_b_trolleys, 0)
    )
  end as effective_qty,
  round(
    (
      case
        when j.is_doubles then coalesce(
          c.manual_total_override,
          coalesce(c.group_a_cores, 0) * coalesce(c.group_a_trolleys, 0)
          + coalesce(c.group_b_cores, 0) * coalesce(c.group_b_trolleys, 0)
        ) / 2.0
        else coalesce(
          c.manual_total_override,
          coalesce(c.group_a_cores, 0) * coalesce(c.group_a_trolleys, 0)
          + coalesce(c.group_b_cores, 0) * coalesce(c.group_b_trolleys, 0)
        )
      end
    ) * coalesce(j.weight_kg, 0) / 1000.0,
    3
  ) as tonnage
from jobs j
left join counts c on c.job_id = j.id
order by j.created_at desc;

-- ---------- Re-assert counts permissions (fixes permission denied) ----------
alter table counts enable row level security;

drop policy if exists "anon can read counts" on counts;
drop policy if exists "anon can insert counts" on counts;
drop policy if exists "anon can update counts" on counts;

create policy "anon can read counts"
  on counts for select
  using (true);

create policy "anon can insert counts"
  on counts for insert
  with check (true);

create policy "anon can update counts"
  on counts for update
  using (true)
  with check (true);

grant usage on schema public to anon, authenticated;
grant select, insert, update on counts to anon;
grant select on counts to authenticated;

grant select on trolley_jobs to anon;
grant select on job_summary to authenticated;
