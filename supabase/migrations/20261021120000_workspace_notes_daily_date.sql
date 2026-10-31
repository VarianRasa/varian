begin;

alter table public.workspace_notes
  add column if not exists daily_note_date date;

create unique index if not exists workspace_notes_private_daily_date_key
  on public.workspace_notes (owner_user_id, daily_note_date)
  where project_id is null
    and daily_note_date is not null
    and deleted_at is null;

create unique index if not exists workspace_notes_project_daily_date_key
  on public.workspace_notes (project_id, daily_note_date)
  where project_id is not null
    and daily_note_date is not null
    and deleted_at is null;

create or replace function public.get_or_create_workspace_daily_note(
  p_daily_note_date date,
  p_project_id text default null
)
returns public.workspace_notes
language plpgsql
security invoker
set search_path = pg_catalog, public, auth
as $function$
declare
  v_actor uuid := auth.uid();
  v_note public.workspace_notes;
begin
  if v_actor is null or p_daily_note_date is null then
    raise exception 'workspace_notes_unavailable' using errcode = 'P0001';
  end if;

  if p_project_id is null then
    insert into public.workspace_notes (
      owner_user_id,
      created_by,
      project_id,
      daily_note_date,
      title,
      markdown_content
    ) values (
      v_actor,
      v_actor,
      null,
      p_daily_note_date,
      pg_catalog.to_char(p_daily_note_date, 'YYYY-MM-DD'),
      ''
    )
    on conflict (owner_user_id, daily_note_date)
      where project_id is null
        and daily_note_date is not null
        and deleted_at is null
      do nothing
    returning * into v_note;

    if not found then
      select n.* into v_note
      from public.workspace_notes n
      where n.owner_user_id = v_actor
        and n.project_id is null
        and n.daily_note_date = p_daily_note_date
        and n.deleted_at is null
      for update;
    end if;
  else
    if not public.can_read_project(p_project_id) then
      raise exception 'workspace_notes_unavailable' using errcode = 'P0001';
    end if;

    select n.* into v_note
    from public.workspace_notes n
    where n.project_id = p_project_id
      and n.daily_note_date = p_daily_note_date
      and n.deleted_at is null
    for update;

    if found then
      return v_note;
    end if;

    if not public.can_edit_project(p_project_id) then
      raise exception 'workspace_notes_unavailable' using errcode = 'P0001';
    end if;

    insert into public.workspace_notes (
      owner_user_id,
      created_by,
      project_id,
      daily_note_date,
      title,
      markdown_content
    ) values (
      v_actor,
      v_actor,
      p_project_id,
      p_daily_note_date,
      pg_catalog.to_char(p_daily_note_date, 'YYYY-MM-DD'),
      ''
    )
    on conflict (project_id, daily_note_date)
      where project_id is not null
        and daily_note_date is not null
        and deleted_at is null
      do nothing
    returning * into v_note;

    if not found then
      select n.* into v_note
      from public.workspace_notes n
      where n.project_id = p_project_id
        and n.daily_note_date = p_daily_note_date
        and n.deleted_at is null
      for update;
    end if;
  end if;

  if v_note.id is null then
    raise exception 'workspace_notes_unavailable' using errcode = 'P0001';
  end if;
  return v_note;
end;
$function$;

revoke all on function public.get_or_create_workspace_daily_note(date, text)
  from public, anon, authenticated;
grant execute on function public.get_or_create_workspace_daily_note(date, text)
  to authenticated;

-- Rehoming two active daily notes for the same owner/date must not violate the
-- active-key constraint. Keep the displaced project copy in Trash, not deleted.
create or replace function public.rehome_workspace_notes_before_project_delete()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if exists (select 1 from public.workspace_notes where project_id = old.id)
     or exists (select 1 from public.workspace_note_folders where project_id = old.id) then
    if old.owner_id is null then
      raise exception 'Cannot delete project with linked notes or folders and no owner';
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
  end if;
  return old;
end $$;

commit;
