create or replace function public.lock_workspace_notes_owner_writes()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $function$
begin
  if auth.uid() is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('workspace_notes:' || auth.uid()::text, 0)
    );
  end if;
  return null;
end;
$function$;

revoke all on function public.lock_workspace_notes_owner_writes()
  from public, anon, authenticated;
grant execute on function public.lock_workspace_notes_owner_writes()
  to authenticated;

-- Apply this migration as the table owner; never grant TRIGGER to app roles.
create trigger workspace_notes_owner_write_lock
before insert or update or delete on public.workspace_notes
for each statement
execute function public.lock_workspace_notes_owner_writes();

create or replace function public.rename_workspace_notes_with_links(
  p_target_id uuid,
  p_expected_revision integer,
  p_title text,
  p_snapshot jsonb,
  p_source_updates jsonb
)
returns setof public.workspace_notes
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
declare
  v_owner uuid;
  v_active_count bigint;
  v_snapshot_count bigint;
  v_target_revision integer;
  v_updated_count bigint;
  v_expected_update_count bigint;
begin
  v_owner := auth.uid();
  if v_owner is null then
    raise exception 'workspace_notes_unavailable' using errcode = 'P0001';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('workspace_notes:' || v_owner::text, 0)
  );

  if p_target_id is null
    or p_expected_revision is null
    or p_expected_revision < 1
    or p_title is null
    or length(btrim(p_title)) = 0
    or jsonb_typeof(p_snapshot) is distinct from 'array'
    or jsonb_typeof(p_source_updates) is distinct from 'array' then
    raise exception 'workspace_notes_unavailable' using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_snapshot) as s(id text, revision integer)
    where s.id is null
      or s.id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or s.revision is null
      or s.revision < 1
  ) or exists (
    select 1
    from jsonb_to_recordset(p_source_updates)
      as s(id text, revision integer, markdown_content text)
    where s.id is null
      or s.id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or s.revision is null
      or s.revision < 1
      or s.markdown_content is null
  ) then
    raise exception 'workspace_notes_unavailable' using errcode = 'P0001';
  end if;

  if exists (
    select s.id
    from jsonb_to_recordset(p_snapshot) as s(id text, revision integer)
    group by s.id
    having count(*) > 1
  ) or exists (
    select s.id
    from jsonb_to_recordset(p_source_updates)
      as s(id text, revision integer, markdown_content text)
    group by s.id
    having count(*) > 1
  ) then
    raise exception 'workspace_notes_unavailable' using errcode = 'P0001';
  end if;

  perform n.id
  from public.workspace_notes as n
  where n.owner_user_id = v_owner
    and n.deleted_at is null
  order by n.id
  for update;

  select n.revision
  into v_target_revision
  from public.workspace_notes as n
  where n.id = p_target_id
    and n.owner_user_id = v_owner
    and n.deleted_at is null;

  if not found then
    raise exception 'workspace_notes_unavailable' using errcode = 'P0001';
  end if;
  if v_target_revision <> p_expected_revision then
    raise exception 'workspace_notes_conflict' using errcode = 'P0001';
  end if;

  select count(*)
  into v_active_count
  from public.workspace_notes as n
  where n.owner_user_id = v_owner
    and n.deleted_at is null;

  select count(*)
  into v_snapshot_count
  from jsonb_to_recordset(p_snapshot) as s(id text, revision integer);

  if v_snapshot_count <> v_active_count or exists (
    select 1
    from jsonb_to_recordset(p_snapshot) as s(id text, revision integer)
    left join public.workspace_notes as n
      on n.id = s.id::uuid
      and n.owner_user_id = v_owner
      and n.deleted_at is null
    where n.id is null or n.revision is distinct from s.revision
  ) then
    raise exception 'workspace_notes_conflict' using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(p_source_updates)
      as u(id text, revision integer, markdown_content text)
    left join jsonb_to_recordset(p_snapshot)
      as s(id text, revision integer)
      on s.id = u.id
    where s.id is null
  ) then
    raise exception 'workspace_notes_unavailable' using errcode = 'P0001';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_source_updates)
      as u(id text, revision integer, markdown_content text)
    join jsonb_to_recordset(p_snapshot)
      as s(id text, revision integer)
      on s.id = u.id
    where u.revision is distinct from s.revision
  ) then
    raise exception 'workspace_notes_conflict' using errcode = 'P0001';
  end if;

  select 1 + count(*)
  into v_expected_update_count
  from jsonb_to_recordset(p_source_updates)
    as u(id text, revision integer, markdown_content text)
  where u.id <> p_target_id::text;

  return query
  with source_updates as (
    select
      u.id::uuid as id,
      u.revision,
      u.markdown_content
    from jsonb_to_recordset(p_source_updates)
      as u(id text, revision integer, markdown_content text)
  ),
  changed_notes as (
    select
      n.id,
      n.revision,
      case when n.id = p_target_id then btrim(p_title) else n.title end as title,
      coalesce(s.markdown_content, n.markdown_content) as markdown_content
    from public.workspace_notes as n
    left join source_updates as s on s.id = n.id
    where n.id = p_target_id or s.id is not null
  ),
  updated as (
    update public.workspace_notes as n
    set title = c.title,
        markdown_content = c.markdown_content,
        revision = n.revision + 1,
        updated_at = now()
    from changed_notes as c
    where n.id = c.id
      and n.owner_user_id = v_owner
      and n.deleted_at is null
      and n.revision = c.revision
    returning n.*
  )
  select u.* from updated as u order by u.id;

  get diagnostics v_updated_count = row_count;
  if v_updated_count <> v_expected_update_count then
    raise exception 'workspace_notes_unavailable' using errcode = 'P0001';
  end if;
end;
$function$;

revoke all on function public.rename_workspace_notes_with_links(
  uuid, integer, text, jsonb, jsonb
) from public, anon, authenticated;
grant execute on function public.rename_workspace_notes_with_links(
  uuid, integer, text, jsonb, jsonb
) to authenticated;
