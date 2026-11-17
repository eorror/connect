-- Run once in Supabase: Dashboard > SQL Editor > New query > paste > Run.
-- Note: this replaces any earlier "notes" table.
drop table if exists public.notes cascade;

create table public.notes (
  id              uuid primary key default gen_random_uuid(),
  created_at      timestamptz not null default now(),
  sender_email    text not null default lower(auth.jwt() ->> 'email'),
  sender_name     text not null,
  recipient_email text not null,
  body            text not null,
  reply_to        uuid references public.notes(id) on delete cascade,
  read_at         timestamptz
);

create index notes_created_at_idx on public.notes (created_at desc);

alter table public.notes enable row level security;

-- You only ever see notes you sent or received.
create policy "see my notes" on public.notes for select to authenticated
  using (lower(auth.jwt() ->> 'email') in (sender_email, recipient_email));

-- You can only send notes as yourself.
create policy "send as me" on public.notes for insert to authenticated
  with check (sender_email = lower(auth.jwt() ->> 'email'));

-- Only the recipient can mark a note as read.
create policy "mark my notes read" on public.notes for update to authenticated
  using (recipient_email = lower(auth.jwt() ->> 'email'))
  with check (recipient_email = lower(auth.jwt() ->> 'email'));

revoke all on public.notes from anon;
revoke all on public.notes from authenticated;   -- undo Supabase's automatic "expose new tables" grants
grant select, insert on public.notes to authenticated;
grant update (read_at) on public.notes to authenticated;
