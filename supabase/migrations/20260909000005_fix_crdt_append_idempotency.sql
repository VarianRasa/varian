create or replace function public.append_canvas_crdt_operation(
  p_project_id text,
  p_operation jsonb
)
returns public.canvas_crdt_operations
language plpgsql
security invoker
set search_path = public
as $$
declare
  result public.canvas_crdt_operations;
  actor text;
  counter bigint;
  operation_id text;
  dependencies jsonb;
begin
  if not public.can_edit_project(p_project_id) then
    raise exception using errcode = '42501', message = 'Not authorized to edit project';
  end if;

  actor := p_operation #>> '{dot,actorId}';
  counter := nullif(p_operation #>> '{dot,counter}', '')::bigint;
  operation_id := p_operation ->> 'opId';
  dependencies := coalesce(p_operation -> 'dependencies', '{}'::jsonb);

  if actor is null or counter is null or counter <= 0 or operation_id is null then
    raise exception using errcode = '22023', message = 'Invalid CRDT operation envelope';
  end if;

  insert into public.canvas_crdt_operations (
    project_id,
    op_id,
    actor_id,
    actor_counter,
    dependencies,
    operation_json,
    auth_user_id
  ) values (
    p_project_id,
    operation_id,
    actor,
    counter,
    dependencies,
    p_operation,
    auth.uid()
  )
  on conflict (project_id, op_id) do nothing
  returning * into result;

  if result.op_id is null then
    select * into result
    from public.canvas_crdt_operations
    where project_id = p_project_id
      and op_id = operation_id;
  end if;

  return result;
end;
$$;

grant execute on function public.append_canvas_crdt_operation(text, jsonb)
to authenticated;
revoke execute on function public.append_canvas_crdt_operation(text, jsonb)
from public, anon;
