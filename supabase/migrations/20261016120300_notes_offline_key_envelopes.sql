create table if not exists public.workspace_note_key_envelopes (
  owner_user_id uuid primary key references auth.users(id) on delete cascade,
  version integer not null check (version = 1),
  kdf_iterations integer not null check (kdf_iterations between 100000 and 1000000),
  salt bytea not null check (octet_length(salt) = 16),
  nonce bytea not null check (octet_length(nonce) = 12),
  wrapped_key bytea not null check (octet_length(wrapped_key) = 48),
  updated_at timestamptz not null default now()
);
alter table public.workspace_note_key_envelopes enable row level security;
create policy workspace_note_key_envelopes_owner_select on public.workspace_note_key_envelopes for select to authenticated using (owner_user_id = auth.uid());
create policy workspace_note_key_envelopes_owner_insert on public.workspace_note_key_envelopes for insert to authenticated with check (owner_user_id = auth.uid());
create policy workspace_note_key_envelopes_owner_update on public.workspace_note_key_envelopes for update to authenticated using (owner_user_id = auth.uid()) with check (owner_user_id = auth.uid());
revoke all on public.workspace_note_key_envelopes from anon;
grant select, insert, update on public.workspace_note_key_envelopes to authenticated;
