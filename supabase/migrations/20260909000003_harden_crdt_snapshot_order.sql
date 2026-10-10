create or replace function public.crdt_version_dominates(
  p_candidate jsonb,
  p_current jsonb
)
returns boolean
language plpgsql
immutable
security definer
set search_path = public
as $$
declare
  entry record;
  candidate_counter bigint;
  current_counter bigint;
begin
  if jsonb_typeof(coalesce(p_candidate, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_current, '{}'::jsonb)) <> 'object' then
    return false;
  end if;

  for entry in
    select key, value
    from jsonb_each(coalesce(p_current, '{}'::jsonb))
  loop
    begin
      current_counter := coalesce(entry.value #>> '{}', '0')::bigint;
      candidate_counter := coalesce(p_candidate ->> entry.key, '0')::bigint;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        return false;
    end;
    if candidate_counter < current_counter then
      return false;
    end if;
  end loop;

  return true;
end;
$$;

revoke execute on function public.crdt_version_dominates(jsonb, jsonb)
from public, anon, authenticated;

create or replace function public.save_canvas_crdt_snapshot(
  p_project_id text,
  p_state_json jsonb,
  p_version_vector jsonb
)
returns public.canvas_crdt_snapshots
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.canvas_crdt_snapshots;
  current_snapshot public.canvas_crdt_snapshots;
begin
  if not public.can_edit_project(p_project_id) then
    raise exception using errcode = '42501', message = 'Not authorized to compact project';
  end if;
  if jsonb_typeof(coalesce(p_state_json, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_version_vector, '{}'::jsonb)) <> 'object' then
    raise exception using errcode = '22023', message = 'Invalid CRDT snapshot envelope';
  end if;

  select * into current_snapshot
  from public.canvas_crdt_snapshots
  where project_id = p_project_id
  for update;

  if current_snapshot.project_id is not null
     and not public.crdt_version_dominates(
       p_version_vector,
       current_snapshot.version_vector
     ) then
    return current_snapshot;
  end if;

  insert into public.canvas_crdt_snapshots (
    project_id,
    state_json,
    version_vector,
    updated_by
  ) values (
    p_project_id,
    p_state_json,
    p_version_vector,
    auth.uid()
  )
  on conflict (project_id) do update set
    state_json = excluded.state_json,
    version_vector = excluded.version_vector,
    updated_at = now(),
    updated_by = auth.uid()
  returning * into result;

  update public.canvas_collaboration_checkpoints
  set version_vector = p_version_vector,
      updated_at = now()
  where project_id = p_project_id
    and user_id = auth.uid();

  delete from public.canvas_crdt_operations operation_row
  where operation_row.project_id = p_project_id
    and exists (
      select 1
      from public.canvas_collaboration_checkpoints checkpoint
      where checkpoint.project_id = p_project_id
        and checkpoint.updated_at > now() - interval '30 days'
    )
    and not exists (
      select 1
      from public.canvas_collaboration_checkpoints checkpoint
      where checkpoint.project_id = p_project_id
        and checkpoint.updated_at > now() - interval '30 days'
        and coalesce(
          (checkpoint.version_vector ->> operation_row.actor_id)::bigint,
          0
        ) < operation_row.actor_counter
    );

  return result;
end;
$$;

grant execute on function public.save_canvas_crdt_snapshot(text, jsonb, jsonb)
to authenticated;
revoke execute on function public.save_canvas_crdt_snapshot(text, jsonb, jsonb)
from public, anon;
