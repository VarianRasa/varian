alter table public.workspace_notes
  add column if not exists deleted_at timestamptz;

create index if not exists workspace_notes_owner_deleted_updated_idx
  on public.workspace_notes (owner_user_id, deleted_at, updated_at desc);
