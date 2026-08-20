-- ============================================================
-- Adds a Horatio-facing free-text note per job (distinct from
-- counts.comment, which is the trolley boys' field). Surfaced in
-- main.html's per-job edit panel; a small icon appears in the desktop
-- Flags column / mobile badge row whenever a job has one.
--
-- job_summary does "select j.*", which freezes its column list at
-- CREATE VIEW time (see CLAUDE.md) — must drop+recreate for `notes` to
-- actually appear in it. trolley_jobs is untouched: notes aren't
-- exposed to the trolley boys.
-- ============================================================

alter table jobs add column if not exists notes text;

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
