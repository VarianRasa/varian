begin;

create table public.workspace_note_versions (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null references public.workspace_notes(id) on delete cascade,
  revision integer not null check (revision >= 1),
  title text not null,
  markdown_content text not null,
  actor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (note_id, revision)
);

create index workspace_note_versions_note_revision_idx
  on public.workspace_note_versions (note_id, revision desc);

-- Preserve the current materialized state as the first snapshot for legacy notes.
insert into public.workspace_note_versions (
  note_id, revision, title, markdown_content, actor_id, created_at
)
select
  n.id, n.revision, n.title, n.markdown_content, n.created_by, n.created_at
from public.workspace_notes n
on conflict (note_id, revision) do nothing;

alter table public.workspace_note_versions enable row level security;

create policy workspace_note_versions_read
  on public.workspace_note_versions
  for select to authenticated
  using (
    exists (
      select 1
      from public.workspace_notes n
      where n.id = workspace_note_versions.note_id
        and public.workspace_note_can_read(n.owner_user_id, n.project_id)
    )
  );

revoke all on table public.workspace_note_versions from public, anon, authenticated;
grant select on table public.workspace_note_versions to authenticated;

create or replace function public.capture_workspace_note_version()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
begin
  if tg_op = 'INSERT' then
    insert into public.workspace_note_versions (
      note_id, revision, title, markdown_content, actor_id, created_at
    ) values (
      new.id, new.revision, new.title, new.markdown_content, auth.uid(), now()
    );
  elsif new.title is distinct from old.title
     or new.markdown_content is distinct from old.markdown_content then
    if new.revision <> old.revision + 1 then
      raise exception 'workspace_note_revision_mismatch';
    end if;
    insert into public.workspace_note_versions (
      note_id, revision, title, markdown_content, actor_id, created_at
    ) values (
      new.id, new.revision, new.title, new.markdown_content, auth.uid(), now()
    );
  elsif new.revision is distinct from old.revision
    and new.deleted_at is not distinct from old.deleted_at then
    raise exception 'workspace_note_revision_without_content_change';
  end if;
  return new;
end;
$function$;

revoke all on function public.capture_workspace_note_version() from public, anon, authenticated;

create trigger workspace_note_versions_capture after insert or update on public.workspace_notes
for each row execute function public.capture_workspace_note_version();

commit;
