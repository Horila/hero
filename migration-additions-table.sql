-- ============================================================
-- Additions bubble (Cr/Cu/Mo/Sn/Ni/Gr/Ti dosing) moves from
-- per-browser localStorage to a real table so it syncs across
-- Horatio's devices. Authenticated-only, same trust level as
-- dip_items — no anon/trolley access, this bubble only exists
-- on main.html.
-- ============================================================

create table if not exists additions (
  element text primary key check (element in ('Cr','Cu','Mo','Sn','Ni','Gr','Ti')),
  per_tonne numeric,
  per_laddle numeric,
  updated_at timestamptz not null default now()
);

alter table additions enable row level security;
revoke all on additions from anon, authenticated;

drop policy if exists "authenticated full access to additions" on additions;
create policy "authenticated full access to additions"
  on additions for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

grant select, insert, update, delete on additions to authenticated;
