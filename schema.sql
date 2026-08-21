-- ============================================================
-- Core Counting App — CONSOLIDATED schema, views, and access control
-- This file represents the CURRENT full desired state of the database
-- (everything the individual migration-*.sql files added, merged).
-- Safe to run on a fresh Supabase project. Also safe to re-run on the
-- already-migrated project — every statement is idempotent
-- (if not exists / or replace / drop if exists).
--
-- The old migration-*.sql files are kept as a historical record of
-- how the schema evolved — they don't need to be run again once this
-- file has been applied.
--
-- Run in Supabase: Dashboard → SQL Editor → New query → Run
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- Main jobs table (Horatio's app only) ----------
create table if not exists jobs (
  id uuid primary key default gen_random_uuid(),
  am_number text not null,
  item_number text,
  grade text,
  customer_name text,
  weight_kg numeric,
  planned_qty integer,
  mingzhi_hansberg_no text,
  status text,
  is_trial boolean default false,
  is_doubles boolean default false,
  needs_dipping boolean default false,
  is_done boolean default false,
  job_date date not null default current_date,
  sort_order bigint default extract(epoch from clock_timestamp())::bigint,
  created_at timestamptz default now()
);

-- (am_number, job_date) is deliberately NOT unique — jobs.id is the only
-- real identity. The same am_number can legitimately reappear on a
-- different programme day, and (since item_reference below) can even
-- repeat on the SAME day when it's a genuinely different part that just
-- happens to share a work-order number — main.html's save flow decides
-- edit-vs-insert itself by looking up (am_number, item_number) among
-- today's jobs, not by relying on a DB constraint. This index is kept
-- purely for that lookup's performance.
drop index if exists jobs_am_number_idx;
-- CREATE INDEX IF NOT EXISTS only checks the name — it won't replace an
-- existing UNIQUE index of the same name with this non-unique one, so the
-- old unique constraint must be dropped explicitly first.
drop index if exists jobs_am_number_date_idx;
create index if not exists jobs_am_number_date_idx on jobs (am_number, job_date);

-- ---------- Counts table (trolley boys write here, no login) ----------
create table if not exists counts (
  id uuid primary key default gen_random_uuid(),
  job_id uuid references jobs(id) on delete cascade,
  group_a_cores integer default 0,
  group_a_trolleys integer default 0,
  group_b_cores integer default 0,
  group_b_trolleys integer default 0,
  manual_total_override integer,
  comment text,
  still_making boolean default false,
  updated_at timestamptz default now()
);

create unique index if not exists counts_job_id_idx on counts (job_id);

-- ---------- Published day (singleton) ----------
-- Which job_date trolley.html currently shows. Horatio picks any day
-- in main.html's date picker and hits "Push Live" to change it, so
-- trolley boys aren't locked to the real today.
create table if not exists published_day (
  id smallint primary key default 1 check (id = 1),
  job_date date not null default current_date,
  updated_at timestamptz not null default now()
);

insert into published_day (id, job_date)
values (1, current_date)
on conflict (id) do nothing;

-- ---------- Dipping memory (by item number) ----------
-- Ticking dipping on for a job remembers its item_number here; future
-- jobs with the same item_number auto-tick on save. Only ever learns
-- "true" — unticking a job does not erase the memory.
create table if not exists dip_items (
  item_number text primary key,
  needs_dipping boolean not null default true,
  updated_at timestamptz default now()
);

-- ---------- Item reference (master record, by part number) ----------
-- Crosscheck baseline for main.html's save flow. Identity is the PART
-- (item_number), not the work order — am_number is recorded but not part
-- of the match, since the same part legitimately gets a new am_number
-- every run. Multiple rows can share an item_number on purpose: each
-- distinct (am_number, grade, weight, doubles, dipping) combo ever
-- confirmed is its own row, including via "save as new entry" in the
-- crosscheck popup.
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

-- ---------- Item reference notes (Horatio-facing, timestamped, per part) ----------
-- The single notes store for both main.html's day's-job list and its Parts panel —
-- keyed by item_number (the part), not by any one day's job, so a note added from
-- either screen shows up on both. item_number is denormalized (snapshotted at insert
-- time) alongside the item_reference_id FK so trolley.html's anon read policy needs
-- no cross-table join. Not day-scoped — a visible note follows the part wherever its
-- item_number shows up today.
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

-- Backfill from every job ever saved. DISTINCT (not "latest only") so a
-- genuinely different historical variant keeps its own row. Guarded with
-- NOT EXISTS so re-running this file never re-inserts duplicates.
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

-- ---------- Chat between Horatio and the trolley boys ----------
-- One thread per job_date, mirroring how trolley_jobs/counts already
-- scope anon access to whatever day is currently published.
create table if not exists chat_messages (
  id uuid primary key default gen_random_uuid(),
  job_date date not null default current_date,
  sender_role text not null check (sender_role in ('admin', 'trolley')),
  sender_name text,
  body text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  read_by text
);

create index if not exists chat_messages_job_date_idx on chat_messages (job_date, created_at);

-- ---------- Additions bubble (Cr/Cu/Mo/Sn/Ni/Gr/Ti dosing) ----------
-- Synced across Horatio's devices instead of per-browser localStorage.
-- Authenticated-only, same trust level as dip_items.
create table if not exists additions (
  element text primary key check (element in ('Cr','Cu','Mo','Sn','Ni','Gr','Ti')),
  per_tonne numeric,
  per_laddle numeric,
  updated_at timestamptz not null default now()
);

-- ---------- Job pace / ETA tracking ----------
-- One row per job_date: which job is currently being cast, when it
-- started, and the current tons/hour speed. main.html projects a
-- rough start time for every job below it in the list from this.
create table if not exists job_pace (
  job_date date primary key,
  current_job_id uuid references jobs(id) on delete set null,
  started_at timestamptz,
  tons_per_hour numeric,
  remaining_qty numeric,
  updated_at timestamptz not null default now()
);

-- ---------- User permissions ----------
-- One row per Supabase Auth login. permission gates write access via
-- is_full_access() below (view_only can read everything but write nothing
-- except job_pace); is_owner gates the manage-users edge function, which is
-- the ONLY thing allowed to insert/update/delete this table (service-role
-- client bypasses RLS — no direct authenticated writes are granted here).
create table if not exists app_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  name text not null,
  permission text not null default 'full_access'
    check (permission in ('view_only','full_access')),
  is_owner boolean not null default false,
  created_at timestamptz not null default now()
);

alter table app_users enable row level security;
revoke all on app_users from anon, authenticated;

drop policy if exists "authenticated can read app_users" on app_users;
create policy "authenticated can read app_users"
  on app_users for select to authenticated using (true);

grant select on app_users to authenticated;

create or replace function is_full_access() returns boolean
  language sql stable security definer set search_path = public as $$
  select exists(
    select 1 from app_users
    where user_id = auth.uid() and permission = 'full_access'
  )
$$;
revoke execute on function is_full_access() from public, anon;
grant execute on function is_full_access() to authenticated;

-- ---------- View: what the trolley boys are allowed to see ----------
-- Only the fields they need + their own count inputs + the computed
-- total. Views run with the OWNER's permissions, so this can read the
-- full jobs table internally while only ever exposing these columns.
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

-- ---------- View: Horatio's summary with tonnage ----------
-- NOTE: "select j.*" freezes its column list at CREATE VIEW time —
-- any future jobs column that should appear here needs this view
-- dropped and recreated, not just the table altered.
-- counted_total is computed once in the joined subquery below and reused
-- for effective_qty/tonnage, instead of repeating the expression inline —
-- one place to change the override/doubles logic instead of four.
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

-- ============================================================
-- Access control
-- ============================================================

alter table jobs enable row level security;
alter table counts enable row level security;
alter table dip_items enable row level security;
alter table published_day enable row level security;
alter table item_reference enable row level security;
alter table item_reference_notes enable row level security;

revoke all on jobs from anon, authenticated;
revoke all on counts from anon, authenticated;
revoke all on dip_items from anon, authenticated;
revoke all on published_day from anon, authenticated;
revoke all on item_reference from anon, authenticated;
revoke all on item_reference_notes from anon, authenticated;

-- jobs: any authenticated login can read (view_only sees everything), only
-- full_access (per app_users) can write. See "User permissions" section below.
drop policy if exists "authenticated full access to jobs" on jobs;

drop policy if exists "authenticated can read jobs" on jobs;
create policy "authenticated can read jobs"
  on jobs for select to authenticated using (auth.role() = 'authenticated');

drop policy if exists "full access can insert jobs" on jobs;
create policy "full access can insert jobs"
  on jobs for insert to authenticated with check (is_full_access());

drop policy if exists "full access can update jobs" on jobs;
create policy "full access can update jobs"
  on jobs for update to authenticated using (is_full_access()) with check (is_full_access());

drop policy if exists "full access can delete jobs" on jobs;
create policy "full access can delete jobs"
  on jobs for delete to authenticated using (is_full_access());

grant select, insert, update, delete on jobs to authenticated;

-- anon also needs a narrow read here: the counts policies below check a
-- job's job_date against published_day, and that EXISTS check runs as the
-- anon role itself, so it needs its own (very limited) read access to jobs
-- or every anon counts write fails with "permission denied for table jobs".
-- Scoped to today's published day, and only the two columns that check
-- needs — trolley_jobs remains the only place anon sees fuller job detail.
drop policy if exists "anon can read published-day jobs for counts check" on jobs;
create policy "anon can read published-day jobs for counts check"
  on jobs for select
  to anon
  using (
    job_date = (select job_date from published_day where id = 1)
  );

grant select (id, job_date) on jobs to anon;

-- counts: trolley boys (anonymous) can read/write, but never delete, and
-- only for jobs on the currently published day — the anon key is public
-- (visible in trolley.html's source), so writes are scoped to stop it being
-- used to rewrite historical jobs' counts. authenticated (Horatio) keeps
-- unrestricted access, including the carry-forward insert that writes counts
-- for a new, not-yet-published day.
drop policy if exists "anon can read counts" on counts;
drop policy if exists "anon can insert counts" on counts;
drop policy if exists "anon can update counts" on counts;
drop policy if exists "anon can insert counts for published day" on counts;
drop policy if exists "anon can update counts for published day" on counts;
drop policy if exists "authenticated full access to counts writes" on counts;

create policy "anon can read counts"
  on counts for select
  using (true);

create policy "anon can insert counts for published day"
  on counts for insert
  to anon
  with check (
    exists (
      select 1 from jobs j, published_day p
      where j.id = counts.job_id and p.id = 1 and j.job_date = p.job_date
    )
  );

create policy "anon can update counts for published day"
  on counts for update
  to anon
  using (
    exists (
      select 1 from jobs j, published_day p
      where j.id = counts.job_id and p.id = 1 and j.job_date = p.job_date
    )
  )
  with check (
    exists (
      select 1 from jobs j, published_day p
      where j.id = counts.job_id and p.id = 1 and j.job_date = p.job_date
    )
  );

create policy "authenticated full access to counts writes"
  on counts for all
  to authenticated
  using (true)
  with check (true);

grant select, insert, update on counts to anon;
-- authenticated needs insert too: main.html carries a job's counts forward
-- automatically when the same am_number reappears on a later job_date.
grant select, insert on counts to authenticated;

-- dip_items: same read/write split as jobs
drop policy if exists "authenticated full access to dip_items" on dip_items;

drop policy if exists "authenticated can read dip_items" on dip_items;
create policy "authenticated can read dip_items"
  on dip_items for select to authenticated using (auth.role() = 'authenticated');

drop policy if exists "full access can insert dip_items" on dip_items;
create policy "full access can insert dip_items"
  on dip_items for insert to authenticated with check (is_full_access());

drop policy if exists "full access can update dip_items" on dip_items;
create policy "full access can update dip_items"
  on dip_items for update to authenticated using (is_full_access()) with check (is_full_access());

drop policy if exists "full access can delete dip_items" on dip_items;
create policy "full access can delete dip_items"
  on dip_items for delete to authenticated using (is_full_access());

grant select, insert, update, delete on dip_items to authenticated;

-- item_reference: same read/write split as jobs/dip_items
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

-- published_day: anyone can read which day is live, only you can change it
drop policy if exists "anyone can read published_day" on published_day;
create policy "anyone can read published_day"
  on published_day for select
  using (true);

drop policy if exists "authenticated can update published_day" on published_day;
create policy "authenticated can update published_day"
  on published_day for update
  using (auth.role() = 'authenticated' and is_full_access())
  with check (auth.role() = 'authenticated' and is_full_access());

grant select on published_day to anon, authenticated;
grant update on published_day to authenticated;

-- chat_messages: Horatio reads/writes any day; trolley boys (anon) are
-- scoped to whatever day is currently published, and can only post as
-- 'trolley' — same trust boundary as counts.
alter table chat_messages enable row level security;
revoke all on chat_messages from anon, authenticated;

drop policy if exists "authenticated can read chat" on chat_messages;
create policy "authenticated can read chat"
  on chat_messages for select
  to authenticated
  using (true);

drop policy if exists "authenticated can send chat" on chat_messages;
create policy "authenticated can send chat"
  on chat_messages for insert
  to authenticated
  with check (auth.role() = 'authenticated' and is_full_access());

drop policy if exists "anon can read published-day chat" on chat_messages;
create policy "anon can read published-day chat"
  on chat_messages for select
  to anon
  using (
    job_date = (select job_date from published_day where id = 1)
  );

drop policy if exists "anon can send published-day chat" on chat_messages;
create policy "anon can send published-day chat"
  on chat_messages for insert
  to anon
  with check (
    sender_role = 'trolley'
    and job_date = (select job_date from published_day where id = 1)
  );

grant select, insert on chat_messages to anon, authenticated;

-- Read receipts: trolley boys mark an admin message read_at/read_by when they
-- open the chat panel on their side, so main.html can show if/when/by-whom.
drop policy if exists "anon can mark admin chat read" on chat_messages;
create policy "anon can mark admin chat read"
  on chat_messages for update
  to anon
  using (
    sender_role = 'admin'
    and job_date = (select job_date from published_day where id = 1)
  )
  with check (
    sender_role = 'admin'
    and job_date = (select job_date from published_day where id = 1)
  );

grant update (read_at, read_by) on chat_messages to anon;

-- item_reference_notes: same read/write split as jobs for Horatio (authenticated
-- read, full_access-gated writes); anon read is scoped to visible_to_trolley = true
-- only, with no day-scoping (a part isn't tied to one job_date) and no cross-table
-- join needed since item_number is denormalized on the row itself.
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

-- additions: your logged-in account only — DELIBERATELY not gated by
-- is_full_access(), same trust level as job_pace: view_only users can use this too.
alter table additions enable row level security;
revoke all on additions from anon, authenticated;

drop policy if exists "authenticated can read additions" on additions;
drop policy if exists "full access can insert additions" on additions;
drop policy if exists "full access can update additions" on additions;
drop policy if exists "full access can delete additions" on additions;

drop policy if exists "authenticated full access to additions" on additions;
create policy "authenticated full access to additions"
  on additions for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

grant select, insert, update, delete on additions to authenticated;

-- Narrow RPCs so view_only users can toggle "done" and "dipping" on a job
-- without a blanket full_access grant on the jobs table's UPDATE policy.
create or replace function set_job_done(p_job_id uuid, p_done boolean) returns void
  language sql security definer set search_path = public as $$
  update jobs set is_done = p_done where id = p_job_id
$$;
revoke execute on function set_job_done(uuid, boolean) from public, anon;
grant execute on function set_job_done(uuid, boolean) to authenticated;

create or replace function set_job_dipping(p_job_id uuid, p_needs_dipping boolean) returns void
  language plpgsql security definer set search_path = public as $$
declare
  v_item_number text;
begin
  update jobs set needs_dipping = p_needs_dipping where id = p_job_id
    returning item_number into v_item_number;
  if p_needs_dipping and v_item_number is not null then
    insert into dip_items (item_number, needs_dipping, updated_at)
    values (v_item_number, true, now())
    on conflict (item_number) do update set needs_dipping = true, updated_at = now();
  end if;
end;
$$;
revoke execute on function set_job_dipping(uuid, boolean) from public, anon;
grant execute on function set_job_dipping(uuid, boolean) to authenticated;

-- job_pace: full access for your logged-in account; read-only for anon so
-- trolley.html can fetch today's pace row for its ETA projection.
alter table job_pace enable row level security;
revoke all on job_pace from anon, authenticated;

drop policy if exists "authenticated full access to job_pace" on job_pace;
create policy "authenticated full access to job_pace"
  on job_pace for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

grant select, insert, update, delete on job_pace to authenticated;

drop policy if exists "anon read job_pace" on job_pace;
create policy "anon read job_pace"
  on job_pace for select
  to anon
  using (true);

grant select on job_pace to anon;

-- Views: trolley_jobs is public (anon), job_summary is yours only
grant select on trolley_jobs to anon;
grant select on job_summary to authenticated;

grant usage on schema public to anon, authenticated;
