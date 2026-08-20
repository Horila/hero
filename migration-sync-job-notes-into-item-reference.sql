-- ============================================================
-- Unifies job-level and part-level notes: job_notes is retired and
-- item_reference_notes (keyed by item_number) becomes the single shared
-- notes store for both main.html's job list and its Parts panel — a
-- note added from either screen now shows up on both, since it's the
-- same row, not a copy.
--
-- Jobs with no item_number have no item_reference row to attach a note
-- to, so notes on such a job cannot be migrated — the NOTICE below
-- surfaces how many (if any) so nothing real is silently discarded by
-- the DROP TABLE at the end. Safe to re-run: both INSERTs are guarded
-- against re-inserting rows already migrated.
-- ============================================================

do $$
declare
  orphan_count integer;
begin
  select count(*) into orphan_count
  from job_notes jn
  join jobs j on j.id = jn.job_id
  where j.item_number is null or j.item_number = '';
  if orphan_count > 0 then
    raise notice 'job_notes: % row(s) belong to a job with no item_number and cannot be migrated to item_reference_notes — they will be permanently lost when job_notes is dropped below.', orphan_count;
  end if;
end $$;

-- Any job_notes row whose job's item_number has no item_reference row yet
-- gets a minimal one created, so the migration below always has somewhere
-- to attach the note.
insert into item_reference (item_number, am_number, grade, weight_kg, is_doubles, needs_dipping)
select distinct j.item_number, j.am_number, j.grade, j.weight_kg,
  coalesce(j.is_doubles, false), coalesce(j.needs_dipping, false)
from job_notes jn
join jobs j on j.id = jn.job_id
where j.item_number is not null and j.item_number <> ''
  and not exists (select 1 from item_reference ir where ir.item_number = j.item_number);

insert into item_reference_notes (item_reference_id, item_number, body, visible_to_trolley, created_at)
select
  (select ir.id from item_reference ir where ir.item_number = j.item_number
   order by ir.updated_at desc nulls last limit 1),
  j.item_number, jn.body, jn.visible_to_trolley, jn.created_at
from job_notes jn
join jobs j on j.id = jn.job_id
where j.item_number is not null and j.item_number <> ''
  and not exists (
    select 1 from item_reference_notes existing
    where existing.item_number = j.item_number
      and existing.body = jn.body
      and existing.created_at = jn.created_at
  );

drop table if exists job_notes;
