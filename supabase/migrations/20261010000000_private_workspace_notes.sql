create table if not exists public.workspace_notes (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  title text not null default 'Untitled Note',
  markdown_content text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint workspace_notes_title_not_blank check (length(btrim(title)) > 0)
);

create index if not exists workspace_notes_owner_updated_idx
  on public.workspace_notes (owner_user_id, updated_at desc);

alter table public.workspace_notes enable row level security;

create policy workspace_notes_owner_select
  on public.workspace_notes
  for select to authenticated
  using (owner_user_id = (select auth.uid()));

create policy workspace_notes_owner_insert
  on public.workspace_notes
  for insert to authenticated
  with check (owner_user_id = (select auth.uid()));

create policy workspace_notes_owner_update
  on public.workspace_notes
  for update to authenticated
  using (owner_user_id = (select auth.uid()))
  with check (owner_user_id = (select auth.uid()));

create policy workspace_notes_owner_delete
  on public.workspace_notes
  for delete to authenticated
  using (owner_user_id = (select auth.uid()));

revoke all on public.workspace_notes from anon;
revoke all on public.workspace_notes from public;
grant select, insert, update, delete on public.workspace_notes to authenticated;
