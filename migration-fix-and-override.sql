-- ============================================================
-- 1. Reset counts table policies/grants cleanly (fixes "save failed")
-- 2. Add support for a directly-typed final total that overrides
--    the cores-per-trolley × trolley-count calculation
-- Run once in Supabase SQL Editor.
-- ============================================================

-- ---------- Fix counts permissions ----------
drop policy if exists "anon can read counts" on counts;
drop policy if exists "anon can insert counts" on counts;
drop policy if exists "anon can update counts" on counts;

create policy "anon can read counts"
  on counts for select
  using (true);

create policy "anon can insert counts"
  on counts for insert
  with check (true);

create policy "anon can update counts"
  on counts for update
  using (true)
  with check (true);

grant select, insert, update on counts to anon;
grant select on counts to authenticated;

-- ---------- Manual override column ----------
alter table counts add column if not exists manual_total_override integer;

-- ---------- Recreate views to respect the override ----------
create or replace view trolley_jobs as
select
  j.id as job_id,
  j.am_number,
  j.planned_qty,
  j.mingzhi_hansberg_no,
  coalesce(c.cores_per_trolley, 0) as cores_per_trolley,
  coalesce(c.trolley_count, 0) as trolley_count,
  coalesce(c.manual_total_override, coalesce(c.cores_per_trolley, 0) * coalesce(c.trolley_count, 0)) as total_cores
from jobs j
left join counts c on c.job_id = j.id
order by j.created_at desc;

create or replace view job_summary as
select
  j.*,
  coalesce(c.manual_total_override, coalesce(c.cores_per_trolley, 0) * coalesce(c.trolley_count, 0)) as counted_total,
  case
    when j.is_doubles then coalesce(c.manual_total_override, coalesce(c.cores_per_trolley, 0) * coalesce(c.trolley_count, 0)) / 2.0
    else coalesce(c.manual_total_override, coalesce(c.cores_per_trolley, 0) * coalesce(c.trolley_count, 0))
  end as effective_qty,
  round(
    (
      case
        when j.is_doubles then coalesce(c.manual_total_override, coalesce(c.cores_per_trolley, 0) * coalesce(c.trolley_count, 0)) / 2.0
        else coalesce(c.manual_total_override, coalesce(c.cores_per_trolley, 0) * coalesce(c.trolley_count, 0))
      end
    ) * coalesce(j.weight_kg, 0) / 1000.0,
    3
  ) as tonnage
from jobs j
left join counts c on c.job_id = j.id
order by j.created_at desc;

grant select on trolley_jobs to anon;
grant select on job_summary to authenticated;
