-- ============================================================
-- Expose job pace (current job / start time / tons-per-hour) and the
-- fields needed to project ETAs to the trolley boys' anon sheet, so
-- trolley.html can show the same ETA times main.html does.
-- ============================================================

-- job_pace was authenticated-only (see migration-job-pace.sql); add a
-- read-only anon policy so trolley.html can fetch today's pace row.
drop policy if exists "anon read job_pace" on job_pace;
create policy "anon read job_pace"
  on job_pace for select
  to anon
  using (true);

grant select on job_pace to anon;

-- trolley_jobs needs weight_kg + is_doubles to compute planned tonnage
-- for the ETA projection (same formula main.html's plannedTonnage() uses).
-- Dropping+recreating a view does NOT preserve its prior grants, so the
-- anon grant below is required, not just a copy-paste leftover.
drop view if exists trolley_jobs;
create view trolley_jobs as
select
  j.id as job_id,
  j.am_number,
  j.item_number,
  j.planned_qty,
  j.weight_kg,
  j.is_doubles,
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
