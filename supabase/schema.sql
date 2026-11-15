-- Run this once in Supabase: Dashboard > SQL Editor > New query > paste > Run
create table if not exists public.notes (
  id         uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  sender     text not null,
  body       text not null,
  reply_to   uuid references public.notes(id) on delete cascade,
  read_at    timestamptz
);

create index if not exists notes_created_at_idx on public.notes (created_at desc);

alter table public.notes enable row level security;

drop policy if exists "read notes" on public.notes;
drop policy if exists "write notes" on public.notes;
drop policy if exists "mark read" on public.notes;
create policy "read notes"  on public.notes for select to anon using (true);
create policy "write notes" on public.notes for insert to anon with check (true);
create policy "mark read"   on public.notes for update to anon using (true) with check (true);

grant select, insert, update on public.notes to anon;
