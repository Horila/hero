-- ============================================================
-- trolley_jobs never exposed sort_order, so trolley.html couldn't
-- explicitly order by it and just relied on the view's internal
-- ORDER BY — not guaranteed once queried from outside, and in
-- practice its job order was drifting from main.html's (which does
-- explicitly order by sort_order). Expose the column so both pages
-- can request the same explicit order.
-- ============================================================

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
order by j.job_date desc, j.sort_order asc;

grant select on trolley_jobs to anon;
