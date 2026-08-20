-- ============================================================
-- item_reference: master record of every distinct part (item_number)
-- ever saved, used to crosscheck new scans/manual entries against
-- history. am_number is recorded but deliberately NOT part of the
-- match/uniqueness — it's a work-order number that legitimately
-- changes every time the same part is run again. Multiple rows can
-- share an item_number on purpose (the "save as new entry" choice
-- in the crosscheck popup adds one instead of editing the match).
--
-- Also relaxes jobs' (am_number, job_date) unique constraint to a
-- plain index — the app now decides edit-vs-insert itself (see
-- main.html saveAllBtn), so the same am_number can appear twice in
-- one day's job list when the popup's "save as new entry" is used.
--
-- Run once in Supabase SQL Editor (or via the Supabase MCP connector).
-- ============================================================

-- ---------- item_reference ----------
create table if not exists item_reference (
  id uuid primary key default gen_random_uuid(),
  am_number text,
  item_number text not null,
  grade text,
  weight_kg numeric,
  is_doubles boolean not null default false,
  needs_dipping boolean not null default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index if not exists item_reference_item_number_idx
  on item_reference (item_number);

alter table item_reference enable row level security;
revoke all on item_reference from anon, authenticated;

drop policy if exists "authenticated can read item_reference" on item_reference;
create policy "authenticated can read item_reference"
  on item_reference for select to authenticated using (auth.role() = 'authenticated');

drop policy if exists "full access can insert item_reference" on item_reference;
create policy "full access can insert item_reference"
  on item_reference for insert to authenticated with check (is_full_access());

drop policy if exists "full access can update item_reference" on item_reference;
create policy "full access can update item_reference"
  on item_reference for update to authenticated using (is_full_access()) with check (is_full_access());

drop policy if exists "full access can delete item_reference" on item_reference;
create policy "full access can delete item_reference"
  on item_reference for delete to authenticated using (is_full_access());

grant select, insert, update, delete on item_reference to authenticated;

-- Backfill from every job ever saved. DISTINCT (not "latest only") so a
-- genuinely different historical variant keeps its own row, same as a
-- "save as new entry" would going forward. Guarded with NOT EXISTS so
-- re-running this file (via schema.sql) never re-inserts duplicates.
insert into item_reference (am_number, item_number, grade, weight_kg, is_doubles, needs_dipping)
select distinct j.am_number, j.item_number, j.grade, j.weight_kg, coalesce(j.is_doubles, false), coalesce(j.needs_dipping, false)
from jobs j
where j.item_number is not null and j.item_number <> ''
  and not exists (
    select 1 from item_reference r
    where r.item_number = j.item_number
      and r.am_number is not distinct from j.am_number
      and r.grade is not distinct from j.grade
      and r.weight_kg is not distinct from j.weight_kg
      and r.is_doubles = coalesce(j.is_doubles, false)
      and r.needs_dipping = coalesce(j.needs_dipping, false)
  );

-- ---------- jobs: (am_number, job_date) is no longer unique ----------
-- jobs.id is the only real identity now; main.html looks up a same-day
-- am_number+item_number match itself and decides edit vs. insert, so a
-- duplicate am_number on the same day is allowed when the user chooses
-- "save as new entry" in the crosscheck popup. Kept as a plain index
-- (not unique) purely for the existing lookup queries' performance.
drop index if exists jobs_am_number_date_idx;
create index if not exists jobs_am_number_date_idx on jobs (am_number, job_date);
