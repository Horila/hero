# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A foundry core-counting app for a trial at Horatio's shop. Three standalone HTML files, no build step, no package.json — deployed straight to GitHub Pages at `https://horila.github.io/hero/`. Backend is entirely Supabase (Postgres + PostgREST + Auth + Edge Functions); there is no local dev server and no test suite.

- **main.html** — Horatio's admin page. Requires Supabase Auth login. Scans/enters jobs (via OCR or manually), manages the day's job list (edit/delete/reorder), and shows a summary sheet (tonnage, counted vs planned, dipping, comments).
- **trolley.html** — the trolley boys' counting page. No login, intentionally anonymous (`persistSession:false` etc. is set explicitly so it never inherits a login session from main.html on the same browser/origin — if that flag is ever removed, saves silently fail with "permission denied" because the `authenticated` role only has SELECT on `counts`, not INSERT/UPDATE). Shows only today's jobs.
- **pyrometer.html** — a standalone camera-based optical pyrometer utility. No Supabase, no relation to the counting app; self-contained.
- **index.ts** — Supabase Edge Function `ocr-plan`. Takes a base64 photo from main.html's scan flow, sends it to Gemini 2.5 Flash's vision API (free tier — chosen specifically to avoid requiring a billed API key during the trial), returns parsed job rows for review before saving. Deployed by pasting into the Supabase Dashboard editor, not via CLI.
- **schema.sql** + **migration-\*.sql** — the database. No migration runner: each file is pasted manually into the Supabase SQL Editor and run once. Filenames are NOT numbered/ordered — order is dependency-based (a later migration's view recreation may depend on an earlier migration's column addition) and must be inferred from what each file actually touches, not from the filename.

## Working in this repo

There is no build, lint, or test command — these are plain static files. The only "commands" that matter:

- **Ship a change**: edit the `.html`/`.ts` file directly, `git add`/`commit`/`push` to `main`. GitHub Pages rebuilds automatically (Jekyll-based `pages build and deployment` workflow in Actions). Deploys can lag several minutes, get stuck `Queued`, or fail outright during a GitHub platform outage — before assuming a pushed change is broken, check the live served content (`curl` the Pages URL and grep for a marker string from the new code) and `https://www.githubstatus.com/api/v2/status.json` / the repo's Actions tab.
- **Apply a schema change**: write a new `migration-*.sql` file (never edit an already-run one in place — treat migrations as append-only). The Supabase MCP connector is wired up for this project — Supabase project ID `dcaeetbbufwsbpdhsnhy` ("Horila's Project", eu-west-1; confirmed by matching `jobs`/`counts`/`dip_items`/`published_day` tables — do not confuse with the other project on this account, "cooking"). Use `mcp__claude_ai_Supabase__apply_migration` to run the new file directly instead of asking the user to paste it into the SQL Editor. Verify with `list_tables` (verbose) / `execute_sql` against `information_schema.role_table_grants` or `pg_policies`, and run `get_advisors` (security) after any RLS-touching change. `deploy_edge_function` can push `index.ts` updates the same way instead of pasting into the Dashboard editor.

## Data model

`jobs` (Horatio-only, authenticated CRUD via RLS) ←1:1→ `counts` (anon read/write, no delete — this is what the trolley boys write to). Two read views sit on top:

- **`trolley_jobs`** — anon-readable subset for the floor page (am_number, planned_qty, group A/B core counts, dipping flag, comment, still-making). Filtered client-side to today (`job_date`).
- **`job_summary`** — authenticated-only, `select j.*` plus computed `counted_total` / `effective_qty` (halved when `is_doubles`) / `tonnage`.

**The recurring gotcha**: both views use `select j.*`. Postgres freezes that column list at `CREATE VIEW` time — adding a column to `jobs` later does NOT propagate into the view. Any migration that adds a `jobs` column must `DROP VIEW` + `CREATE VIEW` (not just alter the table), or `job_summary`/`trolley_jobs` queries for that column will 42703 in production even though the table itself is fine.

Other things that aren't obvious from the schema alone:

- `dip_items` is a small standalone lookup (`item_number` → `needs_dipping`). Ticking dipping on in main.html's summary writes to it; new jobs with a matching `item_number` get auto-ticked on save. It only ever learns "true" — unticking a job never removes the memory.
- `jobs.id` is the only real identity — `(am_number, job_date)` is NOT unique (deliberately relaxed; there's a plain, non-unique index on the pair for lookup performance only). The same am_number can repeat across different days, and can even repeat on the *same* day when it's a genuinely different part that happens to share a work-order number. main.html's save flow (`saveAllBtn`) decides edit-vs-insert itself — it looks up an existing today's row by `(am_number, item_number)` and reuses its `id` for an edit, or generates a fresh `id` (`crypto.randomUUID()`) to force an insert — rather than relying on a DB `upsert(..., { onConflict })` target.
- `item_reference` is the crosscheck master record, keyed by **item_number** (the part), not am_number — am_number is recorded but never gates anything, since the same part legitimately gets a new work-order number every run. Every scan/manual add in main.html looks up the item_number's prior row(s) and compares `weight_kg` / `is_doubles` / `needs_dipping`; a mismatch pops up a modal (`itemRefModalOverlay`) offering "keep database" / "keep new" / "save as new entry" (which inserts an additional row instead of editing the match — multiple rows sharing an item_number is expected, not a bug). No unique constraint on this table at all; matching is entirely app-side.
- `sort_order` on `jobs` is a `bigint` defaulting to `extract(epoch from clock_timestamp())`, so newly-saved jobs land at the end of the list without needing a max-lookup. Reordering only ever swaps two adjacent rows' values — exact spacing never matters.
- Both `trolley.html` and `main.html` toggle a shared dark/light theme via the same `localStorage` key (`coreCountingTheme`) — they're same-origin so the choice carries across pages.

## Housekeeping note

The GitHub repo was renamed `horila/hero` → `Horila/hero` mid-project. Every `git push` against the old remote URL prints a harmless "This repository moved" notice — not an error.
