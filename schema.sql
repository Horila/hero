-- ============================================================
-- Core Counting App — schema, views, and access control
-- Run this once in Supabase: Dashboard → SQL Editor → New query → Run
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- Main jobs table (Horatio's app only) ----------
create table jobs (
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
  created_at timestamptz default now()
);

create unique index jobs_am_number_idx on jobs (am_number);

-- ---------- Counts table (trolley boys write here, no login) ----------
create table counts (
  id uuid primary key default gen_random_uuid(),
  job_id uuid references jobs(id) on delete cascade,
  cores_per_trolley integer default 0,
  trolley_count integer default 0,
  updated_at timestamptz default now()
);

create unique index counts_job_id_idx on counts (job_id);

-- ---------- View: what the trolley boys are allowed to see ----------
-- Only 3 job fields + their own count inputs + the computed total.
-- Views run with the OWNER's permissions, so this can read the full
-- jobs table internally while only ever exposing these columns.
create view trolley_jobs as
select
  j.id as job_id,
  j.am_number,
  j.planned_qty,
  j.mingzhi_hansberg_no,
  coalesce(c.cores_per_trolley, 0) as cores_per_trolley,
  coalesce(c.trolley_count, 0) as trolley_count,
  coalesce(c.cores_per_trolley, 0) * coalesce(c.trolley_count, 0) as total_cores
from jobs j
left join counts c on c.job_id = j.id
order by j.created_at desc;

-- ---------- View: Horatio's summary with tonnage ----------
create view job_summary as
select
  j.*,
  coalesce(c.cores_per_trolley, 0) * coalesce(c.trolley_count, 0) as counted_total,
  round(
    (coalesce(c.cores_per_trolley, 0) * coalesce(c.trolley_count, 0) * coalesce(j.weight_kg, 0)) / 1000.0,
    3
  ) as tonnage
from jobs j
left join counts c on c.job_id = j.id
order by j.created_at desc;

-- ============================================================
-- Access control
-- ============================================================

alter table jobs enable row level security;
alter table counts enable row level security;

-- Lock down default grants, then grant precisely what's needed
revoke all on jobs from anon, authenticated;
revoke all on counts from anon, authenticated;

-- jobs: only your logged-in account can touch this table at all
create policy "authenticated full access to jobs"
  on jobs for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

grant select, insert, update, delete on jobs to authenticated;

-- counts: trolley boys (anonymous) can read/write, but never delete
create policy "anon can read counts"
  on counts for select
  using (true);

create policy "anon can insert counts"
  on counts for insert
  with check (true);

create policy "anon can update counts"
  on counts for update
  using (true);

grant select, insert, update on counts to anon;
grant select on counts to authenticated;

-- Views: trolley_jobs is public (anon), job_summary is yours only
grant select on trolley_jobs to anon;
grant select on job_summary to authenticated;

grant usage on schema public to anon, authenticated;
