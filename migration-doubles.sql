-- ============================================================
-- Adds "doubles" support: when a job is doubles, two cores share
-- one mould, so tonnage should be based on mould count (cores ÷ 2),
-- not raw core count.
-- Run once in Supabase SQL Editor.
-- ============================================================

alter table jobs add column if not exists is_doubles boolean default false;

drop view if exists job_summary;

create view job_summary as
select
  j.*,
  coalesce(c.cores_per_trolley, 0) * coalesce(c.trolley_count, 0) as counted_total,
  case
    when j.is_doubles then coalesce(c.cores_per_trolley, 0) * coalesce(c.trolley_count, 0) / 2.0
    else coalesce(c.cores_per_trolley, 0) * coalesce(c.trolley_count, 0)
  end as effective_qty,
  round(
    (
      case
        when j.is_doubles then coalesce(c.cores_per_trolley, 0) * coalesce(c.trolley_count, 0) / 2.0
        else coalesce(c.cores_per_trolley, 0) * coalesce(c.trolley_count, 0)
      end
    ) * coalesce(j.weight_kg, 0) / 1000.0,
    3
  ) as tonnage
from jobs j
left join counts c on c.job_id = j.id
order by j.created_at desc;

grant select on job_summary to authenticated;
