-- ============================================================
-- Adds a free-text comment field and a "still making" checkbox
-- for the trolley boys to fill in, surfaced on Horatio's main
-- summary sheet.
-- Run once in Supabase SQL Editor.
-- ============================================================

alter table counts add column if not exists comment text;
alter table counts add column if not exists still_making boolean default false;

drop view if exists trolley_jobs;
drop view if exists job_summary;

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
order by j.created_at desc;

grant select on trolley_jobs to anon;
grant select on job_summary to authenticated;
