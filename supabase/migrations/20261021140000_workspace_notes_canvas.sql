begin;

create or replace function public.workspace_note_canvas_state_valid(p_state jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, public
as $function$
declare
  v_card jsonb;
  v_edge jsonb;
  v_card_ids text[] := array[]::text[];
  v_edge_ids text[] := array[]::text[];
  v_id text;
  v_from text;
  v_to text;
  v_x numeric;
  v_y numeric;
  v_width numeric;
  v_height numeric;
begin
  if jsonb_typeof(p_state) is distinct from 'object'
     or p_state->>'schema_version' is distinct from '1'
     or jsonb_typeof(p_state->'cards') is distinct from 'array'
     or jsonb_typeof(p_state->'edges') is distinct from 'array'
     or octet_length(p_state::text) > 5242880
     or jsonb_array_length(p_state->'cards') > 500
     or jsonb_array_length(p_state->'edges') > 2000 then
    return false;
  end if;

  for v_card in select value from jsonb_array_elements(p_state->'cards') as card(value) loop
    if jsonb_typeof(v_card) is distinct from 'object'
       or coalesce(v_card->>'id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or jsonb_typeof(v_card->'x') is distinct from 'number'
       or jsonb_typeof(v_card->'y') is distinct from 'number'
       or jsonb_typeof(v_card->'width') is distinct from 'number'
       or jsonb_typeof(v_card->'height') is distinct from 'number'
       or (v_card ? 'tombstoned' and jsonb_typeof(v_card->'tombstoned') is distinct from 'boolean') then
      return false;
    end if;

    begin
      v_id := (v_card->>'id')::uuid::text;
      v_x := (v_card->>'x')::numeric;
      v_y := (v_card->>'y')::numeric;
      v_width := (v_card->>'width')::numeric;
      v_height := (v_card->>'height')::numeric;
    exception when others then
      return false;
    end;
    if v_id = any(v_card_ids)
       or abs(v_x) > 1000000
       or abs(v_y) > 1000000
       or v_width <= 0 or v_width > 10000
       or v_height <= 0 or v_height > 10000 then
      return false;
    end if;
    v_card_ids := array_append(v_card_ids, v_id);

    if v_card->>'type' = 'note' then
      if coalesce(v_card->>'note_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
        return false;
      end if;
    elsif v_card->>'type' = 'text' then
      if jsonb_typeof(v_card->'markdown') is distinct from 'string'
         or octet_length(v_card->>'markdown') > 102400 then
        return false;
      end if;
    else
      return false;
    end if;
  end loop;

  for v_edge in select value from jsonb_array_elements(p_state->'edges') as edge(value) loop
    if jsonb_typeof(v_edge) is distinct from 'object'
       or coalesce(v_edge->>'id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or coalesce(v_edge->>'from_card_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or coalesce(v_edge->>'to_card_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or (v_edge ? 'tombstoned' and jsonb_typeof(v_edge->'tombstoned') is distinct from 'boolean') then
      return false;
    end if;
    begin
      v_id := (v_edge->>'id')::uuid::text;
      v_from := (v_edge->>'from_card_id')::uuid::text;
      v_to := (v_edge->>'to_card_id')::uuid::text;
    exception when others then
      return false;
    end;
    if v_id = any(v_edge_ids)
       or not (v_from = any(v_card_ids))
       or not (v_to = any(v_card_ids)) then
      return false;
    end if;
    v_edge_ids := array_append(v_edge_ids, v_id);
  end loop;

  return true;
end;
$function$;

create or replace function public.workspace_note_canvas_snapshot_valid(
  p_board_id uuid,
  p_state jsonb,
  p_snapshot jsonb,
  p_version_vector jsonb
)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, public
as $function$
declare
  v_entry record;
begin
  if p_board_id is null
     or not public.workspace_note_canvas_state_valid(p_state)
     or jsonb_typeof(p_snapshot) is distinct from 'object'
     or octet_length(p_snapshot::text) > 20971520
     or jsonb_typeof(p_snapshot->'schema_version') is distinct from 'number'
     or p_snapshot->>'schema_version' is distinct from '2'
     or lower(coalesce(p_snapshot->>'board_id', '')) is distinct from p_board_id::text
     or p_snapshot->'materialized_state' is distinct from p_state
     or jsonb_typeof(p_snapshot->'base_state') is distinct from 'object'
     or not public.workspace_note_canvas_state_valid(p_snapshot->'base_state')
     or p_snapshot->'version_vector' is distinct from p_version_vector
     or jsonb_typeof(p_snapshot->'move_deltas') is distinct from 'object'
     or jsonb_typeof(p_snapshot->'text_sequences') is distinct from 'object'
     or jsonb_typeof(p_snapshot->'pending_operations') is distinct from 'array'
     or jsonb_array_length(p_snapshot->'pending_operations') <> 0
     or jsonb_typeof(p_version_vector) is distinct from 'object'
     or octet_length(p_version_vector::text) > 1048576 then
    return false;
  end if;

  for v_entry in select key, value from jsonb_each(p_version_vector) loop
    if v_entry.key = '' or length(v_entry.key) > 128
       or jsonb_typeof(v_entry.value) is distinct from 'number'
       or v_entry.value::text !~ '^(0|[1-9][0-9]{0,18})$' then
      return false;
    end if;
    begin
      if (v_entry.value::text)::numeric > 9223372036854775807 then
        return false;
      end if;
    exception when others then
      return false;
    end;
  end loop;
  return true;
end;
$function$;

create or replace function public.workspace_note_canvas_note_reference_readable(
  p_note_id uuid,
  p_owner_user_id uuid,
  p_project_id text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select exists (
    select 1
    from public.workspace_notes n
    where n.id = p_note_id
      and n.deleted_at is null
      and n.project_id is not distinct from p_project_id
      and (p_project_id is not null or n.owner_user_id = p_owner_user_id)
      and public.workspace_note_can_read(n.owner_user_id, n.project_id)
  );
$function$;

create or replace function public.workspace_note_canvas_references_readable(
  p_state jsonb,
  p_owner_user_id uuid,
  p_project_id text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  select not exists (
    select 1
    from jsonb_array_elements(p_state->'cards') as card(value)
    where card.value->>'type' = 'note'
      and not public.workspace_note_canvas_note_reference_readable(
        (card.value->>'note_id')::uuid,
        p_owner_user_id,
        p_project_id
      )
  );
$function$;

create table public.workspace_note_canvas_boards (
  id uuid primary key,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  project_id text references public.projects(id) on delete set null,
  title text not null default 'Untitled Canvas' check (length(btrim(title)) between 1 and 120),
  state_json jsonb not null check (
    public.workspace_note_canvas_state_valid(state_json)
    and octet_length(state_json::text) <= 5242880
  ),
  crdt_snapshot_json jsonb not null check (
    jsonb_typeof(crdt_snapshot_json) = 'object'
    and octet_length(crdt_snapshot_json::text) <= 20971520
  ),
  version_vector jsonb not null default '{}'::jsonb check (jsonb_typeof(version_vector) = 'object'),
  revision integer not null default 1 check (revision >= 1),
  snapshot_server_sequence bigint not null default 0 check (snapshot_server_sequence >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint workspace_note_canvas_snapshot_consistent check (
    public.workspace_note_canvas_snapshot_valid(
      id, state_json, crdt_snapshot_json, version_vector
    )
  )
);

create index workspace_note_canvas_boards_private_updated_idx
  on public.workspace_note_canvas_boards (owner_user_id, updated_at desc)
  where project_id is null;
create index workspace_note_canvas_boards_project_updated_idx
  on public.workspace_note_canvas_boards (project_id, updated_at desc)
  where project_id is not null;

create table public.workspace_note_canvas_operations (
  server_sequence bigint generated always as identity not null,
  board_id uuid not null references public.workspace_note_canvas_boards(id) on delete cascade,
  op_id uuid not null,
  replica_id text not null check (length(btrim(replica_id)) between 1 and 128),
  replica_counter bigint not null check (replica_counter > 0),
  dependencies jsonb not null default '{}'::jsonb check (jsonb_typeof(dependencies) = 'object'),
  operation_json jsonb not null check (jsonb_typeof(operation_json) = 'object'),
  auth_user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (board_id, server_sequence),
  unique (board_id, op_id),
  unique (board_id, replica_id, replica_counter)
);
create index workspace_note_canvas_operations_sequence_idx
  on public.workspace_note_canvas_operations (board_id, server_sequence);
create index workspace_note_canvas_operations_replica_idx
  on public.workspace_note_canvas_operations (board_id, replica_id, replica_counter);

create or replace function public.workspace_note_canvas_board_guard()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
begin
  if new.created_by is distinct from old.created_by then
    raise exception 'created_by is immutable';
  end if;
  if new.revision is distinct from old.revision + 1 then
    raise exception 'workspace_note_canvas_revision_invalid' using errcode = '22023';
  end if;
  if new.snapshot_server_sequence < old.snapshot_server_sequence then
    raise exception 'workspace_note_canvas_sequence_regressed' using errcode = '22023';
  end if;
  if new.project_id is distinct from old.project_id then
    if old.project_id is null
       or new.project_id is not null
       or not public.is_project_owner(old.project_id)
       or new.owner_user_id is distinct from (
         select p.owner_id from public.projects p where p.id = old.project_id
       ) then
      raise exception 'workspace_note_canvas_scope_immutable' using errcode = '42501';
    end if;
  elsif new.owner_user_id is distinct from old.owner_user_id then
    raise exception 'owner_user_id is immutable';
  end if;
  return new;
end;
$function$;
create trigger workspace_note_canvas_board_guard
before update on public.workspace_note_canvas_boards
for each row execute function public.workspace_note_canvas_board_guard();

alter table public.workspace_note_canvas_boards enable row level security;
alter table public.workspace_note_canvas_operations enable row level security;
create policy workspace_note_canvas_boards_read
  on public.workspace_note_canvas_boards for select to authenticated
  using (public.workspace_note_can_read(owner_user_id, project_id));
create policy workspace_note_canvas_operations_read
  on public.workspace_note_canvas_operations for select to authenticated
  using (exists (
    select 1 from public.workspace_note_canvas_boards b
    where b.id = board_id
      and public.workspace_note_can_read(b.owner_user_id, b.project_id)
  ));
revoke all on public.workspace_note_canvas_boards,
  public.workspace_note_canvas_operations from public, anon, authenticated;
grant select on public.workspace_note_canvas_boards,
  public.workspace_note_canvas_operations to authenticated;
revoke all on function public.workspace_note_canvas_state_valid(jsonb) from public, anon, authenticated;
revoke all on function public.workspace_note_canvas_snapshot_valid(uuid,jsonb,jsonb,jsonb) from public, anon, authenticated;
revoke all on function public.workspace_note_canvas_note_reference_readable(uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.workspace_note_canvas_references_readable(jsonb,uuid,text) from public, anon, authenticated;
revoke all on function public.workspace_note_canvas_board_guard() from public, anon, authenticated;

create or replace function public.workspace_note_canvas_operation_valid(
  p_board_id uuid,
  p_operation jsonb
)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, public
as $function$
declare
  v_type text;
  v_replica text;
  v_counter bigint;
  v_entry record;
  v_delta numeric;
  v_card jsonb;
  v_edge jsonb;
begin
  if jsonb_typeof(p_operation) is distinct from 'object'
     or octet_length(p_operation::text) > 262144
     or p_operation->>'board_id' is distinct from p_board_id::text
     or coalesce(p_operation->>'op_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or coalesce(p_operation->>'replica_id', '') = ''
     or length(p_operation->>'replica_id') > 128
     or coalesce(p_operation->>'replica_counter', '') !~ '^[1-9][0-9]{0,18}$'
     or jsonb_typeof(p_operation->'dependencies') is distinct from 'object' then
    return false;
  end if;
  begin
    v_counter := (p_operation->>'replica_counter')::bigint;
  exception when others then
    return false;
  end;
  v_replica := p_operation->>'replica_id';
  for v_entry in select key, value from jsonb_each(p_operation->'dependencies') loop
    if v_entry.key = '' or length(v_entry.key) > 128
       or jsonb_typeof(v_entry.value) is distinct from 'number'
       or v_entry.value::text !~ '^[0-9]{1,18}$' then
      return false;
    end if;
    begin
      if (v_entry.value::text)::bigint < 0 then return false; end if;
    exception when others then
      return false;
    end;
  end loop;
  if coalesce((p_operation->'dependencies'->>v_replica)::bigint, 0) <> v_counter - 1 then
    return false;
  end if;

  v_type := p_operation->>'type';
  if v_type = 'card_create' then
    v_card := p_operation->'card';
    return v_card is not null
      and public.workspace_note_canvas_state_valid(jsonb_build_object(
        'schema_version', 1,
        'cards', jsonb_build_array(v_card),
        'edges', '[]'::jsonb
      ))
      and coalesce(v_card->>'tombstoned', 'false') = 'false'
      and (v_card->>'type' is distinct from 'text'
           or coalesce(v_card->>'markdown', '') = '');
  elsif v_type = 'card_tombstone' or v_type = 'card_move' then
    if coalesce(p_operation->>'card_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      return false;
    end if;
    if v_type = 'card_tombstone' then return true; end if;
    if jsonb_typeof(p_operation->'dx') is distinct from 'number'
       or jsonb_typeof(p_operation->'dy') is distinct from 'number' then
      return false;
    end if;
    begin
      v_delta := (p_operation->>'dx')::numeric;
      if abs(v_delta) > 2000000 then return false; end if;
      v_delta := (p_operation->>'dy')::numeric;
      if abs(v_delta) > 2000000 then return false; end if;
    exception when others then
      return false;
    end;
    return true;
  elsif v_type = 'text_insert' then
    if coalesce(p_operation->>'card_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or jsonb_typeof(p_operation->'text') is distinct from 'string'
       or octet_length(p_operation->>'text') = 0
       or octet_length(p_operation->>'text') > 262144 then
      return false;
    end if;
    if p_operation->'after' is not null and jsonb_typeof(p_operation->'after') is distinct from 'null' then
      if jsonb_typeof(p_operation->'after') is distinct from 'object'
         or coalesce(p_operation->'after'->>'actorId', '') = ''
         or length(p_operation->'after'->>'actorId') > 128
         or coalesce(p_operation->'after'->>'counter', '') !~ '^[1-9][0-9]{0,18}$' then
        return false;
      end if;
    end if;
    return true;
  elsif v_type = 'text_delete' then
    return coalesce(p_operation->>'card_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and jsonb_typeof(p_operation->'target') = 'object'
      and coalesce(p_operation->'target'->>'actorId', '') <> ''
      and coalesce(p_operation->'target'->>'counter', '') ~ '^[1-9][0-9]{0,18}$';
  elsif v_type = 'edge_create' then
    v_edge := p_operation->'edge';
    return jsonb_typeof(v_edge) = 'object'
      and coalesce(v_edge->>'id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and coalesce(v_edge->>'from_card_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and coalesce(v_edge->>'to_card_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and coalesce(v_edge->>'tombstoned', 'false') = 'false';
  elsif v_type = 'edge_tombstone' then
    return coalesce(p_operation->>'edge_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';
  end if;
  return false;
end;
$function$;
create or replace function public.workspace_note_canvas_card_type(
  p_board_id uuid,
  p_card_id uuid,
  p_dependencies jsonb
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_type text;
  v_replica_id text;
  v_counter bigint;
begin
  select o.replica_id, o.replica_counter,
         o.operation_json->'card'->>'type'
  into v_replica_id, v_counter, v_type
  from public.workspace_note_canvas_operations o
  where o.board_id = p_board_id
    and o.operation_json->>'type' = 'card_create'
    and lower(o.operation_json->'card'->>'id') = p_card_id::text
  order by o.server_sequence
  limit 1;
  if found then
    if coalesce((p_dependencies->>v_replica_id)::bigint, 0) < v_counter then
      return null;
    end if;
    return v_type;
  end if;

  select card.value->>'type' into v_type
  from public.workspace_note_canvas_boards b
  cross join lateral jsonb_array_elements(
    b.crdt_snapshot_json->'base_state'->'cards'
  ) as card(value)
  where b.id = p_board_id
    and lower(card.value->>'id') = p_card_id::text;
  if found then return v_type; end if;
  return null;
end;
$function$;

create or replace function public.workspace_note_canvas_edge_available(
  p_board_id uuid,
  p_edge_id uuid,
  p_dependencies jsonb
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_replica_id text;
  v_counter bigint;
begin
  select o.replica_id, o.replica_counter
  into v_replica_id, v_counter
  from public.workspace_note_canvas_operations o
  where o.board_id = p_board_id
    and o.operation_json->>'type' = 'edge_create'
    and lower(o.operation_json->'edge'->>'id') = p_edge_id::text
  order by o.server_sequence
  limit 1;
  if found then
    return coalesce((p_dependencies->>v_replica_id)::bigint, 0) >= v_counter;
  end if;
  return exists (
    select 1
    from public.workspace_note_canvas_boards b
    cross join lateral jsonb_array_elements(
      b.crdt_snapshot_json->'base_state'->'edges'
    ) as edge(value)
    where b.id = p_board_id
      and lower(edge.value->>'id') = p_edge_id::text
  );
end;
$function$;

create or replace function public.workspace_note_canvas_operation_targets_valid(
  p_board_id uuid,
  p_operation jsonb
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_board public.workspace_note_canvas_boards%rowtype;
  v_type text := p_operation->>'type';
  v_card_id uuid;
  v_edge_id uuid;
  v_from_card_id uuid;
  v_to_card_id uuid;
  v_card_type text;
  v_target_actor text;
  v_target_counter bigint;
  v_count integer;
  v_exists boolean;
begin
  select * into v_board
  from public.workspace_note_canvas_boards b
  where b.id = p_board_id;
  if not found then return false; end if;

  if v_type = 'card_create' then
    v_card_id := (p_operation->'card'->>'id')::uuid;
    if exists (
      select 1
      from jsonb_array_elements(
        v_board.crdt_snapshot_json->'base_state'->'cards'
      ) as card(value)
      where lower(card.value->>'id') = v_card_id::text
    ) or exists (
      select 1 from public.workspace_note_canvas_operations o
      where o.board_id = p_board_id
        and o.operation_json->>'type' = 'card_create'
        and lower(o.operation_json->'card'->>'id') = v_card_id::text
    ) then
      return false;
    end if;
    select count(*) into v_count from (
      select lower(card.value->>'id') as entity_id
      from jsonb_array_elements(
        v_board.crdt_snapshot_json->'base_state'->'cards'
      ) as card(value)
      union
      select lower(o.operation_json->'card'->>'id')
      from public.workspace_note_canvas_operations o
      where o.board_id = p_board_id
        and o.operation_json->>'type' = 'card_create'
    ) as cards;
    return v_count < 500;
  elsif v_type = 'edge_create' then
    v_edge_id := (p_operation->'edge'->>'id')::uuid;
    if exists (
      select 1
      from jsonb_array_elements(
        v_board.crdt_snapshot_json->'base_state'->'edges'
      ) as edge(value)
      where lower(edge.value->>'id') = v_edge_id::text
    ) or exists (
      select 1 from public.workspace_note_canvas_operations o
      where o.board_id = p_board_id
        and o.operation_json->>'type' = 'edge_create'
        and lower(o.operation_json->'edge'->>'id') = v_edge_id::text
    ) then
      return false;
    end if;
    select count(*) into v_count from (
      select lower(edge.value->>'id') as entity_id
      from jsonb_array_elements(
        v_board.crdt_snapshot_json->'base_state'->'edges'
      ) as edge(value)
      union
      select lower(o.operation_json->'edge'->>'id')
      from public.workspace_note_canvas_operations o
      where o.board_id = p_board_id
        and o.operation_json->>'type' = 'edge_create'
    ) as edges;
    if v_count >= 2000 then return false; end if;
    v_from_card_id := (p_operation->'edge'->>'from_card_id')::uuid;
    v_to_card_id := (p_operation->'edge'->>'to_card_id')::uuid;
    return public.workspace_note_canvas_card_type(
        p_board_id, v_from_card_id, p_operation->'dependencies'
      ) is not null
      and public.workspace_note_canvas_card_type(
        p_board_id, v_to_card_id, p_operation->'dependencies'
      ) is not null;
  elsif v_type in ('card_tombstone', 'card_move', 'text_insert', 'text_delete') then
    v_card_id := (p_operation->>'card_id')::uuid;
    v_card_type := public.workspace_note_canvas_card_type(
      p_board_id, v_card_id, p_operation->'dependencies'
    );
    if v_card_type is null
       or (v_type in ('text_insert', 'text_delete') and v_card_type <> 'text') then
      return false;
    end if;
    if v_type not in ('text_insert', 'text_delete') then return true; end if;
    if v_type = 'text_insert' and p_operation->'after' = 'null'::jsonb then
      return true;
    end if;
    if v_type = 'text_insert' then
      v_target_actor := p_operation->'after'->>'actorId';
      v_target_counter := (p_operation->'after'->>'counter')::bigint;
    else
      v_target_actor := p_operation->'target'->>'actorId';
      v_target_counter := (p_operation->'target'->>'counter')::bigint;
    end if;
    select exists (
      select 1 from public.workspace_note_canvas_operations o
      where o.board_id = p_board_id
        and o.operation_json->>'type' = 'text_insert'
        and lower(o.operation_json->>'card_id') = v_card_id::text
        and o.replica_id = v_target_actor
        and o.replica_counter = v_target_counter
    ) into v_exists;
    if v_exists then
      return coalesce(
        (p_operation->'dependencies'->>v_target_actor)::bigint, 0
      ) >= v_target_counter;
    end if;
    return exists (
      select 1
      from jsonb_array_elements(coalesce(
        v_board.crdt_snapshot_json->'text_sequences'->(v_card_id::text)->'atoms',
        '[]'::jsonb
      )) as atom(value)
      where atom.value->'id'->>'actorId' = v_target_actor
        and atom.value->'id'->>'counter' = v_target_counter::text
    );
  elsif v_type = 'edge_tombstone' then
    v_edge_id := (p_operation->>'edge_id')::uuid;
    return public.workspace_note_canvas_edge_available(
      p_board_id, v_edge_id, p_operation->'dependencies'
    );
  end if;
  return false;
end;
$function$;

revoke all on function public.workspace_note_canvas_operation_valid(uuid,jsonb) from public, anon, authenticated;
revoke all on function public.workspace_note_canvas_card_type(uuid,uuid,jsonb) from public, anon, authenticated;
revoke all on function public.workspace_note_canvas_edge_available(uuid,uuid,jsonb) from public, anon, authenticated;
revoke all on function public.workspace_note_canvas_operation_targets_valid(uuid,jsonb) from public, anon, authenticated;

create or replace function public.create_workspace_note_canvas_board(
  p_board_id uuid,
  p_title text,
  p_project_id text,
  p_state_json jsonb,
  p_crdt_snapshot_json jsonb,
  p_version_vector jsonb
)
returns public.workspace_note_canvas_boards
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_actor uuid := auth.uid();
  v_board public.workspace_note_canvas_boards%rowtype;
begin
  if v_actor is null or p_board_id is null
     or p_title is null or length(btrim(p_title)) not between 1 and 120
     or not public.workspace_note_canvas_snapshot_valid(
       p_board_id, p_state_json, p_crdt_snapshot_json, p_version_vector
     ) then
    raise exception 'workspace_note_canvas_create_invalid' using errcode = '22023';
  end if;
  if not public.workspace_note_can_edit(v_actor, p_project_id) then
    raise exception 'workspace_note_canvas_create_forbidden' using errcode = '42501';
  end if;
  if not public.workspace_note_canvas_references_readable(p_state_json, v_actor, p_project_id) then
    raise exception 'workspace_note_canvas_reference_forbidden' using errcode = '42501';
  end if;

  insert into public.workspace_note_canvas_boards (
    id, owner_user_id, created_by, project_id, title, state_json,
    crdt_snapshot_json, version_vector, revision, snapshot_server_sequence
  ) values (
    p_board_id, v_actor, v_actor, p_project_id, btrim(p_title), p_state_json,
    p_crdt_snapshot_json, p_version_vector, 1, 0
  ) on conflict (id) do nothing returning * into v_board;
  if found then return v_board; end if;

  select * into v_board
  from public.workspace_note_canvas_boards
  where id = p_board_id
  for update;
  if not found
     or v_board.owner_user_id <> v_actor
     or v_board.project_id is distinct from p_project_id
     or v_board.created_by is distinct from v_actor
     or v_board.title is distinct from btrim(p_title)
     or v_board.state_json is distinct from p_state_json
     or v_board.crdt_snapshot_json is distinct from p_crdt_snapshot_json
     or v_board.version_vector is distinct from p_version_vector then
    raise exception 'workspace_note_canvas_create_conflict' using errcode = '23505';
  end if;
  return v_board;
end;
$function$;

create or replace function public.append_workspace_note_canvas_operation(
  p_board_id uuid,
  p_operation jsonb
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_actor uuid := auth.uid();
  v_board public.workspace_note_canvas_boards%rowtype;
  v_operation_id uuid;
  v_replica_id text;
  v_counter bigint;
  v_sequence bigint;
  v_existing jsonb;
  v_inserted integer;
  v_note_id uuid;
  v_dependency record;
  v_known_counter bigint;
begin
  if v_actor is null or not public.workspace_note_canvas_operation_valid(p_board_id, p_operation) then
    raise exception 'workspace_note_canvas_operation_invalid' using errcode = '22023';
  end if;
  select * into v_board
  from public.workspace_note_canvas_boards
  where id = p_board_id
  for update;
  if not found or not public.workspace_note_can_edit(v_board.owner_user_id, v_board.project_id)
     or (v_board.project_id is null and v_board.owner_user_id <> v_actor) then
    raise exception 'workspace_note_canvas_operation_forbidden' using errcode = '42501';
  end if;

  v_operation_id := (p_operation->>'op_id')::uuid;
  v_replica_id := p_operation->>'replica_id';
  v_counter := (p_operation->>'replica_counter')::bigint;
  select server_sequence, operation_json into v_sequence, v_existing
  from public.workspace_note_canvas_operations
  where board_id = p_board_id and op_id = v_operation_id;
  if found then
    if v_existing is distinct from p_operation then
      raise exception 'workspace_note_canvas_operation_id_conflict' using errcode = '23505';
    end if;
    return v_sequence;
  end if;

  select greatest(
    coalesce((v_board.version_vector->>v_replica_id)::bigint, 0),
    coalesce((
      select max(o.replica_counter)
      from public.workspace_note_canvas_operations o
      where o.board_id = p_board_id and o.replica_id = v_replica_id
    ), 0)
  ) into v_known_counter;
  if v_counter <> v_known_counter + 1 then
    raise exception 'workspace_note_canvas_replica_counter_unavailable' using errcode = '40001';
  end if;

  for v_dependency in
    select key, value from jsonb_each(p_operation->'dependencies')
  loop
    select greatest(
      coalesce((v_board.version_vector->>v_dependency.key)::bigint, 0),
      coalesce((
        select max(o.replica_counter)
        from public.workspace_note_canvas_operations o
        where o.board_id = p_board_id and o.replica_id = v_dependency.key
      ), 0)
    ) into v_known_counter;
    if (v_dependency.value::text)::bigint > v_known_counter then
      raise exception 'workspace_note_canvas_dependency_unavailable' using errcode = '40001';
    end if;
  end loop;

  if not public.workspace_note_canvas_operation_targets_valid(p_board_id, p_operation) then
    raise exception 'workspace_note_canvas_target_unavailable' using errcode = '40001';
  end if;

  if p_operation->>'type' = 'card_create'
     and p_operation->'card'->>'type' = 'note' then
    begin
      v_note_id := (p_operation->'card'->>'note_id')::uuid;
    exception when others then
      raise exception 'workspace_note_canvas_reference_forbidden' using errcode = '42501';
    end;
    if not public.workspace_note_canvas_note_reference_readable(
      v_note_id, v_board.owner_user_id, v_board.project_id
    ) then
      raise exception 'workspace_note_canvas_reference_forbidden' using errcode = '42501';
    end if;
  end if;

  insert into public.workspace_note_canvas_operations (
    board_id, op_id, replica_id, replica_counter, dependencies,
    operation_json, auth_user_id
  ) values (
    p_board_id, v_operation_id, v_replica_id, v_counter,
    p_operation->'dependencies', p_operation, v_actor
  ) on conflict (board_id, op_id) do nothing returning server_sequence into v_sequence;
  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    select server_sequence, operation_json into v_sequence, v_existing
    from public.workspace_note_canvas_operations
    where board_id = p_board_id and op_id = v_operation_id;
    if v_existing is distinct from p_operation then
      raise exception 'workspace_note_canvas_operation_id_conflict' using errcode = '23505';
    end if;
  end if;
  return v_sequence;
exception when unique_violation then
  raise exception 'workspace_note_canvas_replica_counter_conflict' using errcode = '23505';
end;
$function$;

create or replace function public.get_workspace_note_canvas_delta(
  p_board_id uuid,
  p_after_sequence bigint default 0,
  p_limit integer default 500
)
returns table(server_sequence bigint, operation_json jsonb)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_board public.workspace_note_canvas_boards%rowtype;
begin
  if auth.uid() is null or p_after_sequence is null or p_after_sequence < 0
     or p_limit is null or p_limit < 1 or p_limit > 1000 then
    raise exception 'workspace_note_canvas_delta_invalid' using errcode = '22023';
  end if;
  select * into v_board from public.workspace_note_canvas_boards where id = p_board_id;
  if not found or not public.workspace_note_can_read(v_board.owner_user_id, v_board.project_id) then
    raise exception 'workspace_note_canvas_delta_forbidden' using errcode = '42501';
  end if;
  return query
    select o.server_sequence, o.operation_json
    from public.workspace_note_canvas_operations o
    where o.board_id = p_board_id
      and o.server_sequence > p_after_sequence
    order by o.server_sequence
    limit p_limit;
end;
$function$;

create or replace function public.materialize_workspace_note_canvas(
  p_board_id uuid,
  p_expected_revision integer,
  p_state_json jsonb,
  p_crdt_snapshot_json jsonb,
  p_version_vector jsonb,
  p_snapshot_server_sequence bigint
)
returns public.workspace_note_canvas_boards
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_actor uuid := auth.uid();
  v_board public.workspace_note_canvas_boards%rowtype;
  v_last_sequence bigint;
  v_expected_vector jsonb;
  v_entry record;
begin
  if v_actor is null or p_expected_revision is null or p_expected_revision < 1
     or p_snapshot_server_sequence is null or p_snapshot_server_sequence < 0
     or not public.workspace_note_canvas_snapshot_valid(
       p_board_id, p_state_json, p_crdt_snapshot_json, p_version_vector
     ) then
    raise exception 'workspace_note_canvas_materialize_invalid' using errcode = '22023';
  end if;
  select * into v_board
  from public.workspace_note_canvas_boards
  where id = p_board_id
  for update;
  if not found or not public.workspace_note_can_edit(v_board.owner_user_id, v_board.project_id)
     or (v_board.project_id is null and v_board.owner_user_id <> v_actor) then
    raise exception 'workspace_note_canvas_materialize_forbidden' using errcode = '42501';
  end if;
  if v_board.revision <> p_expected_revision then
    raise exception 'workspace_note_canvas_revision_conflict' using errcode = '40001';
  end if;
  select coalesce(max(o.server_sequence), 0) into v_last_sequence
  from public.workspace_note_canvas_operations o
  where o.board_id = p_board_id;
  if p_snapshot_server_sequence < v_board.snapshot_server_sequence
     or p_snapshot_server_sequence > v_last_sequence then
    raise exception 'workspace_note_canvas_sequence_invalid' using errcode = '22023';
  end if;
  v_expected_vector := v_board.version_vector;
  for v_entry in
    select o.replica_id, max(o.replica_counter) as replica_counter
    from public.workspace_note_canvas_operations o
    where o.board_id = p_board_id
      and o.server_sequence > v_board.snapshot_server_sequence
      and o.server_sequence <= p_snapshot_server_sequence
    group by o.replica_id
  loop
    v_expected_vector := jsonb_set(
      v_expected_vector,
      array[v_entry.replica_id],
      to_jsonb(greatest(
        coalesce((v_expected_vector->>v_entry.replica_id)::bigint, 0),
        v_entry.replica_counter
      )),
      true
    );
  end loop;
  if p_version_vector is distinct from v_expected_vector then
    raise exception 'workspace_note_canvas_version_vector_invalid' using errcode = '22023';
  end if;
  if not public.workspace_note_canvas_references_readable(
    p_state_json, v_board.owner_user_id, v_board.project_id
  ) then
    raise exception 'workspace_note_canvas_reference_forbidden' using errcode = '42501';
  end if;

  update public.workspace_note_canvas_boards
  set state_json = p_state_json,
      crdt_snapshot_json = p_crdt_snapshot_json,
      version_vector = p_version_vector,
      snapshot_server_sequence = p_snapshot_server_sequence,
      revision = revision + 1,
      updated_at = now()
  where id = p_board_id
  returning * into v_board;
  return v_board;
end;
$function$;

create or replace function public.delete_workspace_note_canvas_board(p_board_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_board public.workspace_note_canvas_boards%rowtype;
begin
  if auth.uid() is null then return false; end if;
  select * into v_board
  from public.workspace_note_canvas_boards
  where id = p_board_id
  for update;
  if not found or not public.workspace_note_can_edit(v_board.owner_user_id, v_board.project_id)
     or (v_board.project_id is null and v_board.owner_user_id <> auth.uid()) then
    return false;
  end if;
  delete from public.workspace_note_canvas_boards where id = p_board_id;
  return true;
end;
$function$;

create or replace function public.workspace_note_canvas_realtime_topic_can_read()
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_topic text;
  v_board_id uuid;
  v_board public.workspace_note_canvas_boards%rowtype;
begin
  v_topic := realtime.topic();
  if v_topic !~ '^notes-canvas:[0-9a-fA-F-]{36}$' then return false; end if;
  begin
    v_board_id := substring(v_topic from 14)::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  select * into v_board from public.workspace_note_canvas_boards where id = v_board_id;
  return found and public.workspace_note_can_read(v_board.owner_user_id, v_board.project_id);
end;
$function$;
revoke all on function public.workspace_note_canvas_realtime_topic_can_read() from public, anon;
grant execute on function public.workspace_note_canvas_realtime_topic_can_read() to authenticated;

do $realtime_policies$
begin
  if to_regclass('realtime.messages') is not null
     and to_regprocedure('realtime.topic()') is not null then
    execute 'create policy workspace_note_canvas_realtime_read on realtime.messages for select to authenticated using (extension = ''broadcast'' and public.workspace_note_canvas_realtime_topic_can_read())';
    execute 'create policy workspace_note_canvas_realtime_send on realtime.messages for insert to authenticated with check (extension = ''broadcast'' and public.workspace_note_canvas_realtime_topic_can_read())';
  end if;
end;
$realtime_policies$;

create or replace function public.rehome_workspace_notes_before_project_delete()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if exists (select 1 from public.workspace_notes where project_id = old.id)
     or exists (select 1 from public.workspace_note_folders where project_id = old.id)
     or exists (select 1 from public.workspace_note_templates where project_id = old.id)
     or exists (select 1 from public.workspace_note_canvas_boards where project_id = old.id) then
    if old.owner_id is null then
      raise exception 'Cannot delete project with linked Notes or Canvas records and no owner';
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
    set project_id = null, owner_user_id = old.owner_id,
        revision = revision + 1, updated_at = now()
    where project_id = old.id;
    update public.workspace_note_canvas_boards
    set project_id = null, owner_user_id = old.owner_id,
        revision = revision + 1, updated_at = now()
    where project_id = old.id;
  end if;
  return old;
end;
$function$;

revoke all on function public.create_workspace_note_canvas_board(uuid,text,text,jsonb,jsonb,jsonb) from public, anon;
revoke all on function public.append_workspace_note_canvas_operation(uuid,jsonb) from public, anon;
revoke all on function public.get_workspace_note_canvas_delta(uuid,bigint,integer) from public, anon;
revoke all on function public.materialize_workspace_note_canvas(uuid,integer,jsonb,jsonb,jsonb,bigint) from public, anon;
revoke all on function public.delete_workspace_note_canvas_board(uuid) from public, anon;
grant execute on function public.create_workspace_note_canvas_board(uuid,text,text,jsonb,jsonb,jsonb) to authenticated;
grant execute on function public.append_workspace_note_canvas_operation(uuid,jsonb) to authenticated;
grant execute on function public.get_workspace_note_canvas_delta(uuid,bigint,integer) to authenticated;
grant execute on function public.materialize_workspace_note_canvas(uuid,integer,jsonb,jsonb,jsonb,bigint) to authenticated;
grant execute on function public.delete_workspace_note_canvas_board(uuid) to authenticated;

commit;
