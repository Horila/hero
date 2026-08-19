-- ============================================================
-- Lets Horatio correct the current job's remaining mould count
-- mid-job (e.g. after downtime throws off the tonnage/hour
-- projection) — main.html re-anchors the ETA calc from "now" using
-- this instead of the job's full tonnage, for the current job only.
-- ============================================================

alter table job_pace add column if not exists remaining_qty numeric;
