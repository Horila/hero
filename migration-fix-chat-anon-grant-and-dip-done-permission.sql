-- Two security fixes found during a full-repo bug scan:
--
-- 1. chat_messages: anon's UPDATE grant was table-wide (all columns), even though
--    trolley.html only ever needs to touch read_at/read_by. The RLS policy only scopes
--    which ROWS anon can touch (admin messages on the published day), not which columns —
--    so the public anon key could rewrite body/sender_name/sender_role on any admin
--    message, i.e. impersonate Horatio in the trolley chat. Narrow the grant to the two
--    columns actually used, matching the column-scoped pattern already used for jobs.
--
-- 2. set_job_done / set_job_dipping: these SECURITY DEFINER RPCs are granted to the whole
--    `authenticated` role, not gated by is_full_access() internally. A view_only user
--    (who main.html's UI correctly hides the done/dipping controls from) could still call
--    them directly via /rest/v1/rpc/set_job_done or set_job_dipping and mutate jobs,
--    bypassing the view-only restriction the rest of the schema enforces. Add the same
--    is_full_access() gate every other write path in this schema already uses.

revoke update on chat_messages from anon;
grant update (read_at, read_by) on chat_messages to anon;

create or replace function set_job_done(p_job_id uuid, p_done boolean) returns void
  language sql security definer set search_path = public as $$
  update jobs set is_done = p_done where id = p_job_id and is_full_access()
$$;

create or replace function set_job_dipping(p_job_id uuid, p_needs_dipping boolean) returns void
  language plpgsql security definer set search_path = public as $$
declare
  v_item_number text;
begin
  if not is_full_access() then
    return;
  end if;
  update jobs set needs_dipping = p_needs_dipping where id = p_job_id
    returning item_number into v_item_number;
  if p_needs_dipping and v_item_number is not null then
    insert into dip_items (item_number, needs_dipping, updated_at)
    values (v_item_number, true, now())
    on conflict (item_number) do update set needs_dipping = true, updated_at = now();
  end if;
end;
$$;
