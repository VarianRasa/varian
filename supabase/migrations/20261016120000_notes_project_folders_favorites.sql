begin;

alter table public.workspace_notes
  add column if not exists project_id text references public.projects(id) on delete set null,
  add column if not exists folder_id uuid,
  add column if not exists created_by uuid;
update public.workspace_notes set created_by = owner_user_id where created_by is null;
alter table public.workspace_notes alter column created_by set default auth.uid();
alter table public.workspace_notes alter column created_by set not null;

create table public.workspace_note_folders (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  project_id text references public.projects(id) on delete set null,
  parent_folder_id uuid,
  name text not null check (length(btrim(name)) > 0),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, project_id),
  foreign key (parent_folder_id) references public.workspace_note_folders(id) on delete restrict
);
-- Folder deletion is handled by the rehome trigger; FK actions must not erase scope.
alter table public.workspace_notes add constraint workspace_notes_folder_scope_fk
  foreign key (folder_id) references public.workspace_note_folders(id) on delete restrict;
create unique index workspace_note_folders_private_sibling_name
  on public.workspace_note_folders(owner_user_id, coalesce(parent_folder_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name)) where project_id is null;
create unique index workspace_note_folders_project_sibling_name
  on public.workspace_note_folders(project_id, coalesce(parent_folder_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name)) where project_id is not null;
create index workspace_notes_project_updated_idx on public.workspace_notes(project_id, updated_at desc) where project_id is not null;

create or replace function public.workspace_notes_scope_guard()
returns trigger language plpgsql security definer set search_path = pg_catalog, public, auth
as $$
begin
  if new.folder_id is not null and not exists (
    select 1 from public.workspace_note_folders f
    where f.id = new.folder_id and f.project_id is not distinct from new.project_id
      and ((new.project_id is null and f.owner_user_id = new.owner_user_id)
        or (new.project_id is not null and f.project_id = new.project_id))
  ) then raise exception 'Note folder scope or owner mismatch'; end if;
  if tg_op = 'UPDATE' and new.project_id is distinct from old.project_id then
    if old.project_id is not null then
      if not public.is_project_owner(old.project_id) then raise exception 'Only current project owner may unlink or relink'; end if;
    elsif new.project_id is not null then
      if old.owner_user_id <> auth.uid() or not public.can_edit_project(new.project_id) then raise exception 'Private owner must be project editor to link'; end if;
    end if;
  end if;
  return new;
end $$;
create trigger workspace_notes_scope_guard before insert or update on public.workspace_notes
for each row execute function public.workspace_notes_scope_guard();

create or replace function public.workspace_note_folders_scope_guard()
returns trigger language plpgsql security definer set search_path = pg_catalog, public, auth
as $$
begin
  if new.parent_folder_id is not null and not exists (
    select 1 from public.workspace_note_folders p where p.id = new.parent_folder_id
      and p.project_id is not distinct from new.project_id
      and ((new.project_id is null and p.owner_user_id = new.owner_user_id)
        or (new.project_id is not null and p.project_id = new.project_id))
      and p.id <> new.id
  ) then raise exception 'Parent folder scope or owner mismatch'; end if;
  if auth.uid() is not null and new.project_id is null and new.owner_user_id <> auth.uid() then raise exception 'Private folder owner mismatch'; end if;
  if auth.uid() is not null and new.project_id is not null and not public.can_edit_project(new.project_id) then raise exception 'Project edit membership required'; end if;
  return new;
end $$;
create trigger workspace_note_folders_scope_guard before insert or update on public.workspace_note_folders
for each row execute function public.workspace_note_folders_scope_guard();

create or replace function public.workspace_note_folder_delete_rehome()
returns trigger language plpgsql security definer set search_path = pg_catalog, public
as $$
begin
  update public.workspace_notes set folder_id = old.parent_folder_id where folder_id = old.id;
  update public.workspace_note_folders set parent_folder_id = old.parent_folder_id where parent_folder_id = old.id;
  return old;
end $$;
create trigger workspace_note_folder_delete_rehome before delete on public.workspace_note_folders
for each row execute function public.workspace_note_folder_delete_rehome();

create table public.workspace_note_preferences (
  user_id uuid not null references auth.users(id) on delete cascade,
  note_id uuid not null references public.workspace_notes(id) on delete cascade,
  pinned_at timestamptz not null default now(),
  primary key (user_id, note_id)
);

create or replace function public.workspace_note_can_read(p_owner uuid, p_project text)
returns boolean language sql stable security definer set search_path = pg_catalog, public, auth
as $$ select case when p_project is null then p_owner = auth.uid() else public.can_read_project(p_project) end $$;
create or replace function public.workspace_note_can_edit(p_owner uuid, p_project text)
returns boolean language sql stable security definer set search_path = pg_catalog, public, auth
as $$ select case when p_project is null then p_owner = auth.uid() else public.can_edit_project(p_project) end $$;
revoke all on function public.workspace_note_can_read(uuid,text) from public, anon;
revoke all on function public.workspace_note_can_edit(uuid,text) from public, anon;
grant execute on function public.workspace_note_can_read(uuid,text), public.workspace_note_can_edit(uuid,text) to authenticated;

drop policy if exists workspace_notes_owner_select on public.workspace_notes;
drop policy if exists workspace_notes_owner_insert on public.workspace_notes;
drop policy if exists workspace_notes_owner_update on public.workspace_notes;
drop policy if exists workspace_notes_owner_delete on public.workspace_notes;
create policy workspace_notes_read on public.workspace_notes for select to authenticated using (public.workspace_note_can_read(owner_user_id, project_id));
create policy workspace_notes_insert on public.workspace_notes for insert to authenticated with check (
  created_by = auth.uid() and ((project_id is null and owner_user_id = auth.uid()) or (project_id is not null and owner_user_id = auth.uid() and public.can_edit_project(project_id)))
);
create policy workspace_notes_update on public.workspace_notes for update to authenticated
  using (public.workspace_note_can_edit(owner_user_id, project_id))
  with check (public.workspace_note_can_edit(owner_user_id, project_id));
create policy workspace_notes_delete on public.workspace_notes for delete to authenticated using (public.workspace_note_can_edit(owner_user_id, project_id));

create or replace function public.workspace_notes_immutable_creator()
returns trigger language plpgsql security invoker set search_path = pg_catalog
as $$
begin
  if new.created_by is distinct from old.created_by then
    raise exception 'created_by is immutable';
  end if;
  if old.project_id is not null and new.project_id is distinct from old.project_id
     and not public.is_project_owner(old.project_id) then
    raise exception 'Only a project owner may relink or unlink notes';
  end if;
  if old.project_id is null and new.project_id is not null
     and not public.can_edit_project(new.project_id) then
    raise exception 'Project edit membership required to link note';
  end if;
  return new;
end $$;
create trigger workspace_notes_immutable_creator
before update on public.workspace_notes for each row
execute function public.workspace_notes_immutable_creator();

-- Rename/write operations must use a single scope selected from the target note;
-- this guard prevents snapshot writes from crossing private/project boundaries.
create or replace function public.workspace_notes_rename_scope(p_owner uuid, p_project text)
returns boolean language sql stable security definer set search_path = pg_catalog, public, auth
as $$ select case when p_project is null then p_owner = auth.uid() else public.can_edit_project(p_project) end $$;

-- The existing statement trigger takes the caller's owner lock first. Project
-- row triggers then take the project lock; rename follows that same order.
create or replace function public.lock_workspace_notes_project_writes()
returns trigger language plpgsql security definer set search_path = pg_catalog, public
as $$
begin
  if new.project_id is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('workspace_notes:project:' || new.project_id, 0)
    );
  end if;
  return new;
end $$;
revoke all on function public.lock_workspace_notes_project_writes() from public, anon, authenticated;
grant execute on function public.lock_workspace_notes_project_writes() to authenticated;
create trigger workspace_notes_project_write_lock
before insert or update on public.workspace_notes
for each row execute function public.lock_workspace_notes_project_writes();

create or replace function public.rename_workspace_notes_with_links(
  p_target_id uuid,
  p_expected_revision integer,
  p_title text,
  p_snapshot jsonb,
  p_source_updates jsonb
)
returns setof public.workspace_notes
language plpgsql security invoker set search_path = pg_catalog, public, auth
as $function$
declare
  v_actor uuid := auth.uid();
  v_owner uuid;
  v_project text;
  v_active_count bigint;
  v_snapshot_count bigint;
  v_target_revision integer;
  v_updated_count bigint;
  v_expected_update_count bigint;
begin
  if v_actor is null then raise exception 'workspace_notes_unavailable' using errcode = 'P0001'; end if;
  -- Acquire the same caller lock as the legacy statement trigger before scope lock.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('workspace_notes:' || v_actor::text, 0));
  select n.owner_user_id, n.project_id into v_owner, v_project
  from public.workspace_notes n where n.id = p_target_id and n.deleted_at is null;
  if not found or not public.workspace_notes_rename_scope(v_owner, v_project) then
    raise exception 'workspace_notes_unavailable' using errcode = 'P0001';
  end if;
  if v_project is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('workspace_notes:project:' || v_project, 0));
  end if;
  if p_expected_revision is null or p_expected_revision < 1 or p_title is null or length(btrim(p_title)) = 0
    or jsonb_typeof(p_snapshot) is distinct from 'array' or jsonb_typeof(p_source_updates) is distinct from 'array' then
    raise exception 'workspace_notes_unavailable' using errcode = 'P0001';
  end if;
  if exists (select 1 from jsonb_to_recordset(p_snapshot) s(id text, revision integer)
    where s.id is null or s.id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' or s.revision is null or s.revision < 1)
    or exists (select 1 from jsonb_to_recordset(p_source_updates) u(id text, revision integer, markdown_content text)
    where u.id is null or u.id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' or u.revision is null or u.revision < 1 or u.markdown_content is null)
    or exists (select id from jsonb_to_recordset(p_snapshot) s(id text, revision integer) group by id having count(*) > 1)
    or exists (select id from jsonb_to_recordset(p_source_updates) u(id text, revision integer, markdown_content text) group by id having count(*) > 1) then
    raise exception 'workspace_notes_unavailable' using errcode = 'P0001';
  end if;
  perform n.id from public.workspace_notes n
    where n.deleted_at is null and ((v_project is null and n.project_id is null and n.owner_user_id = v_owner) or n.project_id = v_project)
    order by n.id for update;
  select revision into v_target_revision from public.workspace_notes n where n.id = p_target_id
    and n.deleted_at is null and ((v_project is null and n.project_id is null and n.owner_user_id = v_owner) or n.project_id = v_project);
  if not found then raise exception 'workspace_notes_unavailable' using errcode = 'P0001'; end if;
  if v_target_revision <> p_expected_revision then raise exception 'workspace_notes_conflict' using errcode = 'P0001'; end if;
  select count(*) into v_active_count from public.workspace_notes n where n.deleted_at is null
    and ((v_project is null and n.project_id is null and n.owner_user_id = v_owner) or n.project_id = v_project);
  select count(*) into v_snapshot_count from jsonb_to_recordset(p_snapshot) s(id text, revision integer);
  if v_snapshot_count <> v_active_count or exists (
    select 1 from jsonb_to_recordset(p_snapshot) s(id text, revision integer)
    left join public.workspace_notes n on n.id = s.id::uuid and n.deleted_at is null
      and ((v_project is null and n.project_id is null and n.owner_user_id = v_owner) or n.project_id = v_project)
    where n.id is null or n.revision is distinct from s.revision
  ) then raise exception 'workspace_notes_conflict' using errcode = 'P0001'; end if;
  if exists (select 1 from jsonb_to_recordset(p_source_updates) u(id text, revision integer, markdown_content text)
    left join jsonb_to_recordset(p_snapshot) s(id text, revision integer) on s.id = u.id where s.id is null) then
    raise exception 'workspace_notes_unavailable' using errcode = 'P0001'; end if;
  if exists (select 1 from jsonb_to_recordset(p_source_updates) u(id text, revision integer, markdown_content text)
    join jsonb_to_recordset(p_snapshot) s(id text, revision integer) on s.id = u.id where u.revision is distinct from s.revision) then
    raise exception 'workspace_notes_conflict' using errcode = 'P0001'; end if;
  select 1 + count(*) into v_expected_update_count from jsonb_to_recordset(p_source_updates) u(id text, revision integer, markdown_content text) where u.id <> p_target_id::text;
  return query with source_updates as (
    select id::uuid id, revision, markdown_content from jsonb_to_recordset(p_source_updates) u(id text, revision integer, markdown_content text)
  ), changed_notes as (
    select n.id, n.revision, case when n.id = p_target_id then btrim(p_title) else n.title end title,
      coalesce(s.markdown_content, n.markdown_content) markdown_content from public.workspace_notes n
    left join source_updates s on s.id = n.id
    where (n.id = p_target_id or s.id is not null) and n.deleted_at is null
      and ((v_project is null and n.project_id is null and n.owner_user_id = v_owner) or n.project_id = v_project)
  ), updated as (
    update public.workspace_notes n set title = c.title, markdown_content = c.markdown_content,
      revision = n.revision + 1, updated_at = now() from changed_notes c where n.id = c.id
      and n.revision = c.revision and n.deleted_at is null
      and ((v_project is null and n.project_id is null and n.owner_user_id = v_owner) or n.project_id = v_project)
    returning n.*
  ) select u.* from updated u order by u.id;
  get diagnostics v_updated_count = row_count;
  if v_updated_count <> v_expected_update_count then raise exception 'workspace_notes_unavailable' using errcode = 'P0001'; end if;
end;
$function$;
revoke all on function public.rename_workspace_notes_with_links(uuid, integer, text, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.rename_workspace_notes_with_links(uuid, integer, text, jsonb, jsonb) to authenticated;


alter table public.workspace_note_folders enable row level security;
create policy workspace_note_folders_select on public.workspace_note_folders for select to authenticated using (public.workspace_note_can_read(owner_user_id, project_id));
create policy workspace_note_folders_insert on public.workspace_note_folders for insert to authenticated with check ((project_id is null and owner_user_id = auth.uid()) or (project_id is not null and public.can_edit_project(project_id)));
create policy workspace_note_folders_update on public.workspace_note_folders for update to authenticated using (public.workspace_note_can_edit(owner_user_id, project_id)) with check (public.workspace_note_can_edit(owner_user_id, project_id));
create policy workspace_note_folders_delete on public.workspace_note_folders for delete to authenticated using (public.workspace_note_can_edit(owner_user_id, project_id));

alter table public.workspace_note_preferences enable row level security;
create policy workspace_note_preferences_read on public.workspace_note_preferences for select to authenticated using (user_id = auth.uid() and exists (select 1 from public.workspace_notes n where n.id = note_id and public.workspace_note_can_read(n.owner_user_id, n.project_id)));
create policy workspace_note_preferences_insert on public.workspace_note_preferences for insert to authenticated with check (user_id = auth.uid() and exists (select 1 from public.workspace_notes n where n.id = note_id and public.workspace_note_can_read(n.owner_user_id, n.project_id)));
create policy workspace_note_preferences_delete on public.workspace_note_preferences for delete to authenticated using (user_id = auth.uid());
grant select, insert, update, delete on public.workspace_note_folders, public.workspace_note_preferences to authenticated;
revoke all on public.workspace_note_folders, public.workspace_note_preferences from public, anon;

create or replace function public.rehome_workspace_notes_before_project_delete()
returns trigger language plpgsql security definer set search_path = pg_catalog, public
as $$
begin
  if exists (select 1 from public.workspace_notes where project_id = old.id)
     or exists (select 1 from public.workspace_note_folders where project_id = old.id) then
    if old.owner_id is null then raise exception 'Cannot delete project with linked notes or folders and no owner'; end if;
    update public.workspace_notes set project_id = null, folder_id = null, owner_user_id = old.owner_id where project_id = old.id;
    update public.workspace_note_folders set project_id = null, parent_folder_id = null, owner_user_id = old.owner_id where project_id = old.id;
  end if;
  return old;
end $$;
create trigger workspace_notes_project_delete_rehome before delete on public.projects for each row execute function public.rehome_workspace_notes_before_project_delete();
revoke all on function public.rehome_workspace_notes_before_project_delete() from public, anon, authenticated;

commit;
