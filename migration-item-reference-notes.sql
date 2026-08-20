-- ============================================================
-- item_reference_notes: same timestamped notes-with-trolley-visibility
-- idea as job_notes, but for a PART (item_reference row) instead of a
-- specific day's job. item_number is denormalized (snapshotted at
-- insert time) alongside the item_reference_id FK — anon (trolley.html)
-- reads by item_number only, so its RLS policy needs no cross-table
-- join/grant into item_reference. A part isn't day-scoped like a job
-- is, so — unlike job_notes — there's no published_day gate here: any
-- visible_to_trolley note for a part shows up wherever that part's
-- item_number appears in today's job list.
-- ============================================================

create table if not exists item_reference_notes (
  id uuid primary key default gen_random_uuid(),
  item_reference_id uuid not null references item_reference(id) on delete cascade,
  item_number text not null,
  body text not null,
  visible_to_trolley boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists item_reference_notes_ref_idx on item_reference_notes (item_reference_id);
create index if not exists item_reference_notes_item_number_idx on item_reference_notes (item_number);

alter table item_reference_notes enable row level security;
revoke all on item_reference_notes from anon, authenticated;

drop policy if exists "authenticated can read item_reference_notes" on item_reference_notes;
create policy "authenticated can read item_reference_notes"
  on item_reference_notes for select to authenticated using (auth.role() = 'authenticated');

drop policy if exists "full access can insert item_reference_notes" on item_reference_notes;
create policy "full access can insert item_reference_notes"
  on item_reference_notes for insert to authenticated with check (is_full_access());

drop policy if exists "full access can update item_reference_notes" on item_reference_notes;
create policy "full access can update item_reference_notes"
  on item_reference_notes for update to authenticated using (is_full_access()) with check (is_full_access());

drop policy if exists "full access can delete item_reference_notes" on item_reference_notes;
create policy "full access can delete item_reference_notes"
  on item_reference_notes for delete to authenticated using (is_full_access());

grant select, insert, update, delete on item_reference_notes to authenticated;

drop policy if exists "anon can read trolley-visible item reference notes" on item_reference_notes;
create policy "anon can read trolley-visible item reference notes"
  on item_reference_notes for select to anon using (visible_to_trolley = true);

grant select on item_reference_notes to anon;

-- ---------- trolley_jobs: expose item_number, needed to match part-level notes ----------
drop view if exists trolley_jobs;
create view trolley_jobs as
select
  j.id as job_id,
  j.am_number,
  j.item_number,
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
where coalesce(j.is_done, false) = false
order by j.job_date desc, j.sort_order asc;

grant select on trolley_jobs to anon;
