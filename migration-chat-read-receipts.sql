-- ============================================================
-- Read receipts for the office->trolley chat. Lets main.html show
-- if/when/by-whom an admin message was read on the trolley sheet.
-- Trolley boys' local "seen" state was only ever in their own
-- browser's localStorage — never synced back, so Horatio had no way
-- to see it. This makes it a real DB column instead.
-- ============================================================

alter table chat_messages add column if not exists read_at timestamptz;
alter table chat_messages add column if not exists read_by text;

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

grant update on chat_messages to anon;
