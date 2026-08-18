-- ============================================================
-- Adds a per-job "done" flag main.html can tick once a job is fully
-- wrapped up. Done jobs drop out of trolley_jobs (the floor-worker view)
-- but keep showing normally everywhere else (job_summary, jobs table) —
-- ticking done only controls trolley visibility, nothing else.
-- Run once in Supabase SQL Editor.
-- ============================================================

alter table jobs add column if not exists is_done boolean default false;

-- job_summary uses "select j.*" which freezes its column list at CREATE
-- VIEW time (see the note further up this file) — recreate it so is_done
-- actually shows up for main.html.
drop view if exists job_summary;
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

drop view if exists trolley_jobs;
create view trolley_jobs as
select
  j.id as job_id,
  j.am_number,
  j.planned_qty,
  j.mingzhi_hansberg_no,
  j.job_date,
  j.needs_dipping,
  j.sort_order,
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
where coalesce(j.is_done, false) = false
order by j.job_date desc, j.sort_order asc;

grant select on trolley_jobs to anon;
