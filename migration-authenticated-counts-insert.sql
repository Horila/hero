-- ============================================================
-- main.html now carries a job's counts forward automatically when
-- the same am_number reappears on a later job_date (see
-- syncCountsFromPreviousDay in main.html). That runs as the logged-in
-- (authenticated) user and needs to INSERT into counts, not just
-- SELECT. The RLS policy already allows it ("with check (true)", no
-- TO clause — applies to any role), but the GRANT never did:
-- authenticated only ever got SELECT on counts (anon got
-- select/insert/update). Add the missing grant.
-- Run once in Supabase SQL Editor.
-- ============================================================

grant insert on counts to authenticated;
