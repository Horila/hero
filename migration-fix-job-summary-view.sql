-- ============================================================
-- job_summary used "select j.*" which froze its column list at
-- creation time — adding job_date to the jobs table didn't
-- propagate into the view. Recreating it picks up job_date (and
-- any other jobs columns) fresh.
-- Run once in Supabase SQL Editor.
-- ============================================================

drop view if exists job_summary;

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

grant select on job_summary to authenticated;
