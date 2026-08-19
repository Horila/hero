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

-- Uniqueness is (am_number, job_date), not am_number alone — the same
-- job number can legitimately reappear on a different programme day.
drop index if exists jobs_am_number_idx;
create unique index if not exists jobs_am_number_date_idx on jobs (am_number, job_date);

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

-- ---------- Chat between Horatio and the trolley boys ----------
-- One thread per job_date, mirroring how trolley_jobs/counts already
-- scope anon access to whatever day is currently published.
create table if not exists chat_messages (
  id uuid primary key default gen_random_uuid(),
  job_date date not null default current_date,
  sender_role text not null check (sender_role in ('admin', 'trolley')),
  sender_name text,
  body text not null,
  created_at timestamptz not null default now()
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

-- ---------- View: what the trolley boys are allowed to see ----------
-- Only the fields they need + their own count inputs + the computed
-- total. Views run with the OWNER's permissions, so this can read the
-- full jobs table internally while only ever exposing these columns.
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

revoke all on jobs from anon, authenticated;
revoke all on counts from anon, authenticated;
revoke all on dip_items from anon, authenticated;
revoke all on published_day from anon, authenticated;

-- jobs: only your logged-in account can touch this table for real work
drop policy if exists "authenticated full access to jobs" on jobs;
create policy "authenticated full access to jobs"
  on jobs for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

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

-- dip_items: your logged-in account only
drop policy if exists "authenticated full access to dip_items" on dip_items;
create policy "authenticated full access to dip_items"
  on dip_items for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

grant select, insert, update, delete on dip_items to authenticated;

-- published_day: anyone can read which day is live, only you can change it
drop policy if exists "anyone can read published_day" on published_day;
create policy "anyone can read published_day"
  on published_day for select
  using (true);

drop policy if exists "authenticated can update published_day" on published_day;
create policy "authenticated can update published_day"
  on published_day for update
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

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
  with check (auth.role() = 'authenticated');

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

-- additions: your logged-in account only
alter table additions enable row level security;
revoke all on additions from anon, authenticated;

drop policy if exists "authenticated full access to additions" on additions;
create policy "authenticated full access to additions"
  on additions for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

grant select, insert, update, delete on additions to authenticated;

-- Views: trolley_jobs is public (anon), job_summary is yours only
grant select on trolley_jobs to anon;
grant select on job_summary to authenticated;

grant usage on schema public to anon, authenticated;
