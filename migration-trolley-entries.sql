-- ============================================================
-- Switches counting from "cores per trolley × trolley count" to
-- a per-trolley list, since trolleys aren't always uniform.
-- Total is now the sum of whatever was logged per trolley.
-- Run once in Supabase SQL Editor.
-- ============================================================

alter table counts add column if not exists trolley_entries integer[] default '{}';

drop view if exists trolley_jobs;
drop view if exists job_summary;

alter table counts drop column if exists cores_per_trolley;
alter table counts drop column if exists trolley_count;

create view trolley_jobs as
select
  j.id as job_id,
  j.am_number,
  j.planned_qty,
  j.mingzhi_hansberg_no,
  j.needs_dipping,
  coalesce(c.trolley_entries, '{}') as trolley_entries,
  coalesce(cardinality(c.trolley_entries), 0) as trolley_count,
  coalesce(c.manual_total_override, ct.total) as total_cores
from jobs j
left join counts c on c.job_id = j.id
left join lateral (
  select coalesce(sum(x), 0) as total from unnest(coalesce(c.trolley_entries, '{}')) x
) ct on true
order by j.created_at desc;

create view job_summary as
select
  j.*,
  coalesce(c.manual_total_override, ct.total) as counted_total,
  case
    when j.is_doubles then coalesce(c.manual_total_override, ct.total) / 2.0
    else coalesce(c.manual_total_override, ct.total)
  end as effective_qty,
  round(
    (
      case
        when j.is_doubles then coalesce(c.manual_total_override, ct.total) / 2.0
        else coalesce(c.manual_total_override, ct.total)
      end
    ) * coalesce(j.weight_kg, 0) / 1000.0,
    3
  ) as tonnage
from jobs j
left join counts c on c.job_id = j.id
left join lateral (
  select coalesce(sum(x), 0) as total from unnest(coalesce(c.trolley_entries, '{}')) x
) ct on true
order by j.created_at desc;

grant select on trolley_jobs to anon;
grant select on job_summary to authenticated;
