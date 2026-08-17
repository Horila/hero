-- ============================================================
-- Adds manual ordering to jobs, so Horatio can reorder the day's
-- programme from Manage Jobs. New jobs default to the end of the
-- list (epoch-scale value); existing jobs get backfilled in their
-- current per-day order. Reordering only needs to swap two rows'
-- sort_order values, so exact number spacing never matters.
-- Run once in Supabase SQL Editor.
-- ============================================================

alter table jobs add column if not exists sort_order bigint default extract(epoch from clock_timestamp())::bigint;

with numbered as (
  select id, row_number() over (partition by job_date order by created_at) as rn
  from jobs
)
update jobs set sort_order = numbered.rn
from numbered
where jobs.id = numbered.id and jobs.sort_order is null;

drop view if exists trolley_jobs;
drop view if exists job_summary;

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
order by j.job_date desc, j.sort_order asc;

create view job_summary as
select
  j.*,
  coalesce(c.comment, '') as comment,
  coalesce(c.still_making, false) as still_making,
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
order by j.job_date desc, j.sort_order asc;

grant select on trolley_jobs to anon;
grant select on job_summary to authenticated;
