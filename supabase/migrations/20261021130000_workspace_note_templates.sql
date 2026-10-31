begin;

create table public.workspace_note_templates (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  project_id text references public.projects(id) on delete set null,
  title text not null check (length(btrim(title)) > 0),
  markdown_content text not null,
  revision integer not null default 1 check (revision >= 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index workspace_note_templates_private_updated_idx
  on public.workspace_note_templates (owner_user_id, updated_at desc)
  where project_id is null;
create index workspace_note_templates_project_updated_idx
  on public.workspace_note_templates (project_id, updated_at desc)
  where project_id is not null;

create or replace function public.workspace_note_templates_guard()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, auth
as $$
begin
  if tg_op = 'UPDATE' then
    if new.created_by is distinct from old.created_by then
      raise exception 'created_by is immutable';
    end if;
    if new.revision is distinct from old.revision + 1 then
      raise exception 'workspace_note_template_revision_invalid' using errcode = '22023';
    end if;
    if new.project_id is distinct from old.project_id then
      if old.project_id is null
         or new.project_id is not null
         or not public.is_project_owner(old.project_id)
         or new.owner_user_id is distinct from (
           select p.owner_id from public.projects p where p.id = old.project_id
         ) then
        raise exception 'workspace_note_template_scope_immutable' using errcode = '42501';
      end if;
    elsif new.owner_user_id is distinct from old.owner_user_id then
      raise exception 'owner_user_id is immutable';
    end if;
  end if;
  return new;
end;
$$;

create trigger workspace_note_templates_guard
before update on public.workspace_note_templates
for each row execute function public.workspace_note_templates_guard();

alter table public.workspace_note_templates enable row level security;
create policy workspace_note_templates_read
  on public.workspace_note_templates for select to authenticated
  using (public.workspace_note_can_read(owner_user_id, project_id));
create policy workspace_note_templates_insert
  on public.workspace_note_templates for insert to authenticated
  with check (
    created_by = auth.uid()
    and (
      (project_id is null and owner_user_id = auth.uid())
      or (project_id is not null and owner_user_id = auth.uid()
          and public.can_edit_project(project_id))
    )
  );
create policy workspace_note_templates_update
  on public.workspace_note_templates for update to authenticated
  using (public.workspace_note_can_edit(owner_user_id, project_id))
  with check (public.workspace_note_can_edit(owner_user_id, project_id));
create policy workspace_note_templates_delete
  on public.workspace_note_templates for delete to authenticated
  using (public.workspace_note_can_edit(owner_user_id, project_id));

revoke all on public.workspace_note_templates from public, anon, authenticated;
grant select, insert, delete on public.workspace_note_templates to authenticated;
grant update (title, markdown_content, revision, updated_at)
  on public.workspace_note_templates to authenticated;
revoke all on function public.workspace_note_templates_guard()
  from public, anon, authenticated;

create or replace function public.rehome_workspace_notes_before_project_delete()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if exists (select 1 from public.workspace_notes where project_id = old.id)
     or exists (select 1 from public.workspace_note_folders where project_id = old.id)
     or exists (select 1 from public.workspace_note_templates where project_id = old.id) then
    if old.owner_id is null then
      raise exception 'Cannot delete project with linked notes, folders, or templates and no owner';
    end if;

    update public.workspace_notes project_daily
    set deleted_at = now(), updated_at = now()
    where project_daily.project_id = old.id
      and project_daily.daily_note_date is not null
      and project_daily.deleted_at is null
      and exists (
        select 1
        from public.workspace_notes private_daily
        where private_daily.project_id is null
          and private_daily.owner_user_id = old.owner_id
          and private_daily.daily_note_date = project_daily.daily_note_date
          and private_daily.deleted_at is null
      );

    update public.workspace_notes
    set project_id = null, folder_id = null, owner_user_id = old.owner_id
    where project_id = old.id;
    update public.workspace_note_folders
    set project_id = null, parent_folder_id = null, owner_user_id = old.owner_id
    where project_id = old.id;
    update public.workspace_note_templates
    set project_id = null,
        owner_user_id = old.owner_id,
        revision = revision + 1,
        updated_at = now()
    where project_id = old.id;
  end if;
  return old;
end $$;

commit;
