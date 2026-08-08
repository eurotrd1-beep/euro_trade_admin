-- ── System Repair — operations audit log ──────────────────────────────────
-- Run this ONCE in the Supabase SQL Editor (project dlzqdmqkvlvwnjhqxqym).
-- Every destructive/repair action from the "إصلاح النظام" page is recorded here
-- (what, when, result). If this table is missing the page still works — it just
-- can't log. RLS is "allow all" to match the rest of the project (no roles).

create table if not exists public.repair_log (
  id         bigint generated always as identity primary key,
  at         timestamptz not null default now(),
  action     text        not null,
  result     text,
  created_at timestamptz not null default now()
);

alter table public.repair_log enable row level security;

drop policy if exists "repair_log allow all" on public.repair_log;
create policy "repair_log allow all"
  on public.repair_log for all
  using (true) with check (true);
