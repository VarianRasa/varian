begin;

create or replace function public.import_workspace_notes_batch(
  p_notes jsonb,
  p_folders jsonb,
  p_project_id text
)
returns setof public.workspace_notes
language plpgsql
security invoker
set search_path = pg_catalog, public, auth
as $function$
declare
  v_actor uuid := auth.uid();
  v_note_count integer;
  v_folder_count integer;
  v_note record;
  v_requested_path text;
  v_current_path text;
  v_segments text[];
  v_segment text;
  v_index integer;
  v_parent_id uuid;
  v_folder_id uuid;
  v_folder_map jsonb := '{}'::jsonb;
  v_inserted public.workspace_notes%rowtype;
begin
  if v_actor is null then
    raise exception 'workspace_notes_import_unavailable' using errcode = 'P0001';
  end if;
  if jsonb_typeof(p_notes) is distinct from 'array'
     or jsonb_typeof(p_folders) is distinct from 'array' then
    raise exception 'workspace_notes_import_invalid' using errcode = 'P0001';
  end if;

  v_note_count := jsonb_array_length(p_notes);
  v_folder_count := jsonb_array_length(p_folders);
  if v_note_count < 1 or v_note_count > 100 or v_folder_count > 100 then
    raise exception 'workspace_notes_import_invalid' using errcode = 'P0001';
  end if;
  if not public.workspace_note_can_edit(v_actor, p_project_id) then
    raise exception 'workspace_notes_import_forbidden' using errcode = '42501';
  end if;

  -- Match the lock order used by existing note writes: caller first, project second.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('workspace_notes:' || v_actor::text, 0)
  );
  if p_project_id is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('workspace_notes:project:' || p_project_id, 0)
    );
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_notes) as n(
      id text, title text, markdown_content text, folder_path text
    )
    where n.id is null
       or n.id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or n.title is null or length(btrim(n.title)) = 0
       or n.markdown_content is null
       or octet_length(n.markdown_content) > 10485760
       or (n.folder_path is not null and (
         n.folder_path = '' or length(n.folder_path) > 512
         or n.folder_path ~ '(^/|\\|:|//|(^|/)\.\.?(/|$))'
       ))
  ) or exists (
    select 1 from jsonb_to_recordset(p_notes) as n(
      id text, title text, markdown_content text, folder_path text
    ) group by n.id having count(*) > 1
  ) or exists (
    select 1 from jsonb_to_recordset(p_notes) as n(
      id text, title text, markdown_content text, folder_path text
    ) group by lower(btrim(n.title)) having count(*) > 1
  ) or exists (
    select 1
    from jsonb_array_elements(p_notes) as item(value)
    where item.value ?| array['owner_user_id', 'created_by', 'project_id', 'revision', 'deleted_at']
  ) then
    raise exception 'workspace_notes_import_invalid' using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_folders) as f(value)
    where jsonb_typeof(f.value) is distinct from 'string'
       or length(f.value #>> '{}') = 0
       or length(f.value #>> '{}') > 512
       or (f.value #>> '{}') ~ '(^/|\\|:|//|(^|/)\.\.?(/|$))'
  ) or exists (
    select lower(f.value #>> '{}')
    from jsonb_array_elements(p_folders) as f(value)
    group by lower(f.value #>> '{}') having count(*) > 1
  ) then
    raise exception 'workspace_notes_import_invalid' using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_notes) as n(
      id text, title text, markdown_content text, folder_path text
    )
    where n.folder_path is not null
      and not exists (
        select 1 from jsonb_array_elements_text(p_folders) as f(path)
        where lower(f.path) = lower(n.folder_path)
      )
  ) then
    raise exception 'workspace_notes_import_invalid' using errcode = 'P0001';
  end if;

  -- Fail if the preview's duplicate-title decision became stale before confirmation.
  if exists (
    select 1
    from jsonb_to_recordset(p_notes) as incoming(
      id text, title text, markdown_content text, folder_path text
    )
    join public.workspace_notes existing
      on lower(btrim(existing.title)) = lower(btrim(incoming.title))
     and existing.deleted_at is null
     and ((p_project_id is null and existing.project_id is null
           and existing.owner_user_id = v_actor)
       or (p_project_id is not null and existing.project_id = p_project_id))
  ) then
    raise exception 'workspace_notes_import_title_conflict' using errcode = 'P0001';
  end if;

  for v_requested_path in
    select f.value #>> '{}'
    from jsonb_array_elements(p_folders) as f(value)
    order by length(f.value #>> '{}'), lower(f.value #>> '{}')
  loop
    v_segments := string_to_array(v_requested_path, '/');
    v_parent_id := null;
    v_current_path := '';
    for v_index in 1..array_length(v_segments, 1) loop
      v_segment := v_segments[v_index];
      v_current_path := case when v_current_path = '' then v_segment
                             else v_current_path || '/' || v_segment end;
      select f.id into v_folder_id
      from public.workspace_note_folders f
      where f.project_id is not distinct from p_project_id
        and f.parent_folder_id is not distinct from v_parent_id
        and lower(f.name) = lower(v_segment)
        and (p_project_id is not null or f.owner_user_id = v_actor)
      limit 1;
      if v_folder_id is null then
        insert into public.workspace_note_folders (
          owner_user_id, project_id, parent_folder_id, name
        ) values (
          v_actor, p_project_id, v_parent_id, v_segment
        ) returning id into v_folder_id;
      end if;
      v_folder_map := v_folder_map || jsonb_build_object(lower(v_current_path), v_folder_id::text);
      v_parent_id := v_folder_id;
      v_folder_id := null;
    end loop;
  end loop;

  for v_note in
    select * from jsonb_to_recordset(p_notes) as n(
      id text, title text, markdown_content text, folder_path text
    ) order by n.id
  loop
    v_folder_id := case when v_note.folder_path is null then null
                        else (v_folder_map ->> lower(v_note.folder_path))::uuid end;
    insert into public.workspace_notes (
      id, owner_user_id, title, markdown_content, project_id, folder_id, created_by
    ) values (
      v_note.id::uuid, v_actor, btrim(v_note.title), v_note.markdown_content,
      p_project_id, v_folder_id, v_actor
    ) returning * into v_inserted;
    return next v_inserted;
  end loop;
  return;
end;
$function$;

revoke all on function public.import_workspace_notes_batch(jsonb, jsonb, text)
  from public, anon;
grant execute on function public.import_workspace_notes_batch(jsonb, jsonb, text)
  to authenticated;

commit;
