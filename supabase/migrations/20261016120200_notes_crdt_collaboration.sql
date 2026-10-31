begin;

create table public.workspace_note_crdt_snapshots (
  note_id uuid primary key references public.workspace_notes(id) on delete cascade,
  state_json jsonb not null check (jsonb_typeof(state_json) = 'object'),
  version_vector jsonb not null default '{}'::jsonb check (jsonb_typeof(version_vector) = 'object'),
  materialized_revision integer not null check (materialized_revision >= 1),
  updated_at timestamptz not null default now(),
  updated_by uuid not null default auth.uid()
);

create table public.workspace_note_crdt_operations (
  note_id uuid not null references public.workspace_notes(id) on delete cascade,
  op_id text not null,
  replica_id text not null check (length(replica_id) between 1 and 128),
  replica_counter bigint not null check (replica_counter > 0),
  dependencies jsonb not null default '{}'::jsonb check (jsonb_typeof(dependencies) = 'object'),
  operation_json jsonb not null check (jsonb_typeof(operation_json) = 'object'),
  auth_user_id uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (note_id, op_id),
  unique (note_id, replica_id, replica_counter)
);
create index workspace_note_crdt_operations_order_idx
  on public.workspace_note_crdt_operations(note_id, created_at, op_id);
create index workspace_note_crdt_operations_replica_idx
  on public.workspace_note_crdt_operations(note_id, replica_id, replica_counter);

alter table public.workspace_note_crdt_snapshots enable row level security;
alter table public.workspace_note_crdt_operations enable row level security;
create policy workspace_note_crdt_snapshots_read on public.workspace_note_crdt_snapshots
  for select to authenticated using (
    exists (select 1 from public.workspace_notes n
      where n.id = note_id
        and public.workspace_note_can_read(n.owner_user_id, n.project_id))
  );
create policy workspace_note_crdt_operations_read on public.workspace_note_crdt_operations
  for select to authenticated using (
    exists (select 1 from public.workspace_notes n
      where n.id = note_id
        and public.workspace_note_can_read(n.owner_user_id, n.project_id))
  );
revoke all on public.workspace_note_crdt_snapshots,
  public.workspace_note_crdt_operations from public, anon, authenticated;
grant select on public.workspace_note_crdt_snapshots,
  public.workspace_note_crdt_operations to authenticated;

create or replace function public.workspace_note_realtime_topic_can_read()
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_topic text;
  v_note_id uuid;
  v_note public.workspace_notes%rowtype;
begin
  v_topic := realtime.topic();
  if v_topic !~ '^notes:[0-9a-fA-F-]{36}$' then return false; end if;
  begin
    v_note_id := substring(v_topic from 7)::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  select * into v_note from public.workspace_notes where id = v_note_id;
  return found and public.workspace_note_can_read(v_note.owner_user_id, v_note.project_id);
end;
$function$;
revoke all on function public.workspace_note_realtime_topic_can_read() from public, anon;
grant execute on function public.workspace_note_realtime_topic_can_read() to authenticated;

do $realtime_policies$
begin
  if to_regclass('realtime.messages') is not null
     and to_regprocedure('realtime.topic()') is not null then
    execute 'drop policy if exists workspace_note_realtime_read on realtime.messages';
    execute 'create policy workspace_note_realtime_read on realtime.messages for select to authenticated using (extension = ''broadcast'' and public.workspace_note_realtime_topic_can_read())';
    execute 'drop policy if exists workspace_note_realtime_send on realtime.messages';
    execute 'create policy workspace_note_realtime_send on realtime.messages for insert to authenticated with check (extension = ''broadcast'' and public.workspace_note_realtime_topic_can_read())';
  end if;
end;
$realtime_policies$;

create or replace function public.create_workspace_note_from_sync(
  p_note_id uuid,
  p_title text,
  p_markdown_content text,
  p_project_id text,
  p_state_json jsonb,
  p_version_vector jsonb
)
returns public.workspace_notes
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_actor uuid := auth.uid();
  v_note public.workspace_notes%rowtype;
begin
  if v_actor is null or p_note_id is null
     or p_title is null or length(btrim(p_title)) = 0
     or p_markdown_content is null
     or octet_length(p_markdown_content) > 10485760
     or jsonb_typeof(p_state_json) is distinct from 'object'
     or octet_length(p_state_json::text) > 10485760
     or jsonb_typeof(p_version_vector) is distinct from 'object'
     or octet_length(p_version_vector::text) > 1048576 then
    raise exception 'workspace_note_sync_create_invalid' using errcode = '22023';
  end if;
  if not public.workspace_note_can_edit(v_actor, p_project_id) then
    raise exception 'workspace_note_sync_create_forbidden' using errcode = '42501';
  end if;

  insert into public.workspace_notes (
    id, owner_user_id, created_by, title, markdown_content, project_id, revision
  ) values (
    p_note_id, v_actor, v_actor, btrim(p_title), p_markdown_content, p_project_id, 1
  ) on conflict (id) do nothing returning * into v_note;

  if found then
    insert into public.workspace_note_crdt_snapshots (
      note_id, state_json, version_vector, materialized_revision, updated_by
    ) values (
      p_note_id, p_state_json, p_version_vector, v_note.revision, v_actor
    );
    return v_note;
  end if;

  select * into v_note from public.workspace_notes where id = p_note_id for update;
  if not found or v_note.owner_user_id <> v_actor
     or v_note.project_id is distinct from p_project_id
     or v_note.title is distinct from btrim(p_title)
     or v_note.markdown_content is distinct from p_markdown_content then
    raise exception 'workspace_note_sync_create_conflict' using errcode = '23505';
  end if;
  insert into public.workspace_note_crdt_snapshots (
    note_id, state_json, version_vector, materialized_revision, updated_by
  ) values (
    p_note_id, p_state_json, p_version_vector, v_note.revision, v_actor
  ) on conflict (note_id) do nothing;
  return v_note;
end;
$function$;

create or replace function public.append_workspace_note_crdt_operation(
  p_note_id uuid,
  p_operation jsonb
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_actor uuid := auth.uid();
  v_note public.workspace_notes%rowtype;
  v_op_id text;
  v_note_id text;
  v_replica_id text;
  v_dot jsonb;
  v_counter bigint;
  v_existing jsonb;
  v_inserted integer;
begin
  if v_actor is null or jsonb_typeof(p_operation) is distinct from 'object'
     or octet_length(p_operation::text) > 262144 then
    raise exception 'workspace_note_crdt_operation_invalid' using errcode = '22023';
  end if;
  select * into v_note from public.workspace_notes where id = p_note_id for update;
  if not found or not public.workspace_note_can_edit(v_actor, v_note.project_id)
     or (v_note.project_id is null and v_note.owner_user_id <> v_actor) then
    raise exception 'workspace_note_crdt_operation_forbidden' using errcode = '42501';
  end if;

  v_note_id := p_operation->>'noteId';
  v_replica_id := p_operation->>'replicaId';
  v_op_id := p_operation->>'opId';
  v_dot := p_operation->'dot';
  if v_note_id is distinct from p_note_id::text
     or v_replica_id is null or length(v_replica_id) not between 1 and 128
     or jsonb_typeof(v_dot) is distinct from 'object'
     or v_dot->>'actorId' is distinct from v_replica_id
     or v_dot->>'counter' is null
     or (v_dot->>'counter') !~ '^[1-9][0-9]{0,17}$'
     or v_op_id is distinct from (p_note_id::text || ':' || v_replica_id || ':' || (v_dot->>'counter'))
     or jsonb_typeof(p_operation->'dependencies') is distinct from 'object'
     or jsonb_typeof(p_operation->'insertions') is distinct from 'array'
     or jsonb_typeof(p_operation->'deletions') is distinct from 'array' then
    raise exception 'workspace_note_crdt_operation_invalid' using errcode = '22023';
  end if;
  v_counter := (v_dot->>'counter')::bigint;
  if v_counter > 9223372036854770000 then
    raise exception 'workspace_note_crdt_operation_invalid' using errcode = '22023';
  end if;

  insert into public.workspace_note_crdt_operations (
    note_id, op_id, replica_id, replica_counter, dependencies, operation_json, auth_user_id
  ) values (
    p_note_id, v_op_id, v_replica_id, v_counter, p_operation->'dependencies', p_operation, v_actor
  ) on conflict (note_id, op_id) do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    select operation_json into v_existing
    from public.workspace_note_crdt_operations
    where note_id = p_note_id and op_id = v_op_id;
    if v_existing is distinct from p_operation then
      raise exception 'workspace_note_crdt_operation_id_conflict' using errcode = '23505';
    end if;
  end if;
  return v_inserted > 0;
end;
$function$;

create or replace function public.get_workspace_note_crdt_delta(
  p_note_id uuid,
  p_since jsonb,
  p_limit integer default 500
)
returns setof jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_actor uuid := auth.uid();
  v_note public.workspace_notes%rowtype;
begin
  if v_actor is null or jsonb_typeof(p_since) is distinct from 'object'
     or p_limit is null or p_limit < 1 or p_limit > 1000 then
    raise exception 'workspace_note_crdt_delta_invalid' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_each(p_since) entry
    where entry.key = '' or jsonb_typeof(entry.value) is distinct from 'number'
      or entry.value::text !~ '^[0-9]{1,18}$'
  ) then
    raise exception 'workspace_note_crdt_delta_invalid' using errcode = '22023';
  end if;
  select * into v_note from public.workspace_notes where id = p_note_id;
  if not found or not public.workspace_note_can_read(v_note.owner_user_id, v_note.project_id) then
    raise exception 'workspace_note_crdt_delta_forbidden' using errcode = '42501';
  end if;
  return query
    select operation_json
    from public.workspace_note_crdt_operations o
    where o.note_id = p_note_id
      and o.replica_counter > coalesce((p_since->>o.replica_id)::bigint, 0)
    order by o.created_at, o.op_id
    limit p_limit;
end;
$function$;

create or replace function public.materialize_workspace_note_crdt(
  p_note_id uuid,
  p_expected_revision integer,
  p_markdown_content text,
  p_state_json jsonb,
  p_version_vector jsonb
)
returns public.workspace_notes
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_actor uuid := auth.uid();
  v_note public.workspace_notes%rowtype;
begin
  if v_actor is null or p_markdown_content is null
     or octet_length(p_markdown_content) > 10485760
     or jsonb_typeof(p_state_json) is distinct from 'object'
     or octet_length(p_state_json::text) > 10485760
     or jsonb_typeof(p_version_vector) is distinct from 'object'
     or octet_length(p_version_vector::text) > 1048576 then
    raise exception 'workspace_note_crdt_materialize_invalid' using errcode = '22023';
  end if;
  select * into v_note from public.workspace_notes where id = p_note_id for update;
  if not found or not public.workspace_note_can_edit(v_actor, v_note.project_id)
     or (v_note.project_id is null and v_note.owner_user_id <> v_actor) then
    raise exception 'workspace_note_crdt_materialize_forbidden' using errcode = '42501';
  end if;
  if v_note.revision <> p_expected_revision then
    raise exception 'workspace_note_revision_conflict' using errcode = '40001';
  end if;

  if v_note.markdown_content is distinct from p_markdown_content then
    update public.workspace_notes
    set markdown_content = p_markdown_content,
        revision = revision + 1,
        updated_at = now()
    where id = p_note_id
    returning * into v_note;
  end if;

  insert into public.workspace_note_crdt_snapshots (
    note_id, state_json, version_vector, materialized_revision, updated_by, updated_at
  ) values (
    p_note_id, p_state_json, p_version_vector, v_note.revision, v_actor, now()
  ) on conflict (note_id) do update set
    state_json = excluded.state_json,
    version_vector = excluded.version_vector,
    materialized_revision = excluded.materialized_revision,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at;
  return v_note;
end;
$function$;

revoke all on function public.create_workspace_note_from_sync(uuid,text,text,text,jsonb,jsonb) from public, anon;
revoke all on function public.append_workspace_note_crdt_operation(uuid,jsonb) from public, anon;
revoke all on function public.get_workspace_note_crdt_delta(uuid,jsonb,integer) from public, anon;
revoke all on function public.materialize_workspace_note_crdt(uuid,integer,text,jsonb,jsonb) from public, anon;
grant execute on function public.create_workspace_note_from_sync(uuid,text,text,text,jsonb,jsonb) to authenticated;
grant execute on function public.append_workspace_note_crdt_operation(uuid,jsonb) to authenticated;
grant execute on function public.get_workspace_note_crdt_delta(uuid,jsonb,integer) to authenticated;
grant execute on function public.materialize_workspace_note_crdt(uuid,integer,text,jsonb,jsonb) to authenticated;

commit;
