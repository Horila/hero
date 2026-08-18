-- ============================================================
-- job_summary repeated the same counted-cores expression
-- (coalesce(manual_total_override, group_a_cores*group_a_trolleys +
-- group_b_cores*group_b_trolleys)) 4 times in one view definition —
-- a future change to that formula (e.g. the override logic) is easy to
-- miss in one of the copies. Compute it once in a joined subquery and
-- reference the alias everywhere else in the view. Same column list as
-- before (order matters for "select j.*" — see the CLAUDE.md note on
-- this view), so nothing downstream needs to change.
-- Run once in Supabase SQL Editor.
-- ============================================================

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
