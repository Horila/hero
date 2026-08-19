-- ============================================================
-- Follow-up to migration-user-permissions.sql: widen what view_only can do.
-- Additions goes back to "any authenticated" (same trust level as job_pace),
-- and "done"/"dipping" toggles move behind narrow SECURITY DEFINER RPCs so
-- view_only can flip those two columns without a blanket full_access grant
-- on the jobs table's UPDATE policy.
-- ============================================================

drop policy if exists "authenticated can read additions" on additions;
drop policy if exists "full access can insert additions" on additions;
drop policy if exists "full access can update additions" on additions;
drop policy if exists "full access can delete additions" on additions;

drop policy if exists "authenticated full access to additions" on additions;
create policy "authenticated full access to additions"
  on additions for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

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
