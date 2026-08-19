-- ============================================================
-- User accounts + permissions (view_only vs full_access) for main.html
-- Run once via Supabase MCP apply_migration (or paste into SQL Editor).
-- ============================================================

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
-- No insert/update/delete grants for anon/authenticated — every write goes through the
-- manage-users edge function's service-role client, which bypasses RLS/grants by design.
-- That's the only path that can write this table.

create or replace function is_full_access() returns boolean
  language sql stable security definer set search_path = public as $$
  select exists(
    select 1 from app_users
    where user_id = auth.uid() and permission = 'full_access'
  )
$$;
grant execute on function is_full_access() to authenticated;

-- Bootstrap: mark the existing (only) login as owner + full_access.
insert into app_users (user_id, email, name, permission, is_owner)
select id, email, 'Horatio', 'full_access', true
from auth.users where email = 'eurac@hero.com'
on conflict (user_id) do update set is_owner = true, permission = 'full_access';

-- ---------- jobs: split "authenticated full access" into select (any authenticated,
-- view-only still needs to SEE everything) vs. insert/update/delete (full_access only) ----------
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

-- ---------- dip_items: same split ----------
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

-- ---------- additions: same split ----------
drop policy if exists "authenticated full access to additions" on additions;

drop policy if exists "authenticated can read additions" on additions;
create policy "authenticated can read additions"
  on additions for select to authenticated using (auth.role() = 'authenticated');

drop policy if exists "full access can insert additions" on additions;
create policy "full access can insert additions"
  on additions for insert to authenticated with check (is_full_access());

drop policy if exists "full access can update additions" on additions;
create policy "full access can update additions"
  on additions for update to authenticated using (is_full_access()) with check (is_full_access());

drop policy if exists "full access can delete additions" on additions;
create policy "full access can delete additions"
  on additions for delete to authenticated using (is_full_access());

-- ---------- chat_messages: select stays open to any authenticated (view-only can read),
-- only sending requires full_access ----------
drop policy if exists "authenticated can send chat" on chat_messages;
create policy "authenticated can send chat"
  on chat_messages for insert
  to authenticated
  with check (auth.role() = 'authenticated' and is_full_access());

-- ---------- published_day: only full_access can push a day live ----------
drop policy if exists "authenticated can update published_day" on published_day;
create policy "authenticated can update published_day"
  on published_day for update
  using (auth.role() = 'authenticated' and is_full_access())
  with check (auth.role() = 'authenticated' and is_full_access());

-- ---------- job_pace: DELIBERATELY UNCHANGED — any authenticated user (including
-- view_only) keeps full read/write here. This is the one thing view-only can edit. ----------
