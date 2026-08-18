-- ============================================================
-- Adds a single-row "published day" switch: which job_date the
-- trolley boys' page (trolley.html) currently shows. Lets Horatio
-- pick any day in main.html's date picker and "Push Live" it,
-- instead of trolley.html always defaulting to the real today.
-- ============================================================

create table if not exists published_day (
  id smallint primary key default 1 check (id = 1), -- singleton: exactly one row, ever
  job_date date not null default current_date,
  updated_at timestamptz not null default now()
);

insert into published_day (id, job_date)
values (1, current_date)
on conflict (id) do nothing;

alter table published_day enable row level security;

revoke all on published_day from anon, authenticated;

-- anyone (trolley boys, no login) can read which day is live
drop policy if exists "anyone can read published_day" on published_day;
create policy "anyone can read published_day"
  on published_day for select
  using (true);

-- only Horatio can change it
drop policy if exists "authenticated can update published_day" on published_day;
create policy "authenticated can update published_day"
  on published_day for update
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

grant select on published_day to anon, authenticated;
grant update on published_day to authenticated;
