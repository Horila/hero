-- ============================================================
-- Chat between Horatio (main.html) and the trolley boys (trolley.html).
-- One thread per job_date, mirroring how trolley_jobs/counts already
-- scope anon access to whatever day is currently published.
-- ============================================================

create table if not exists chat_messages (
  id uuid primary key default gen_random_uuid(),
  job_date date not null default current_date,
  sender_role text not null check (sender_role in ('admin', 'trolley')),
  sender_name text,
  body text not null,
  created_at timestamptz not null default now()
);

create index if not exists chat_messages_job_date_idx on chat_messages (job_date, created_at);

alter table chat_messages enable row level security;
revoke all on chat_messages from anon, authenticated;

-- Horatio (main.html): full read/write, any day — he can scroll back
-- through history via the date picker same as the jobs list.
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

-- Trolley boys (anon, no login): scoped to whatever day is currently
-- published, and can only post as 'trolley' — same trust boundary as
-- the counts table.
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
