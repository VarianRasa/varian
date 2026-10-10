-- Numeric collaboration room IDs replace anonymous read-only share links for
-- live workspace access. The raw six-digit code is never stored.

create extension if not exists pgcrypto;

create table if not exists public.collaboration_rooms (
  id uuid primary key default gen_random_uuid(),
  project_id text not null references public.projects(id) on delete cascade,
  room_code_hash text not null unique,
  project_name text not null default 'Untitled Project',
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  last_joined_at timestamptz,
  revoked_at timestamptz
);

create unique index if not exists collaboration_rooms_active_project_idx
  on public.collaboration_rooms (project_id)
  where revoked_at is null;

create index if not exists collaboration_rooms_active_code_idx
  on public.collaboration_rooms (room_code_hash)
  where revoked_at is null;

alter table public.collaboration_rooms enable row level security;

drop policy if exists collaboration_rooms_owner_read
  on public.collaboration_rooms;
create policy collaboration_rooms_owner_read on public.collaboration_rooms
  for select
  using (public.is_project_owner(project_id));

revoke all on public.collaboration_rooms from anon;
revoke all on public.collaboration_rooms from authenticated;

create or replace function public.create_collaboration_room(
  p_project_id text,
  p_project_name text default 'Untitled Project'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  generated_code text;
  created_room public.collaboration_rooms;
  attempt_count integer := 0;
  normalized_name text := coalesce(nullif(trim(p_project_name), ''), 'Untitled Project');
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can create a collaboration room';
  end if;

  update public.collaboration_rooms
  set revoked_at = now()
  where project_id = p_project_id
    and revoked_at is null;

  loop
    generated_code := floor(random() * 900000 + 100000)::bigint::text;
    begin
      insert into public.collaboration_rooms (
        project_id,
        room_code_hash,
        project_name,
        created_by
      ) values (
        p_project_id,
        encode(extensions.digest(generated_code, 'sha256'), 'hex'),
        normalized_name,
        auth.uid()
      )
      returning * into created_room;
      exit;
    exception
      when unique_violation then
        attempt_count := attempt_count + 1;
        if attempt_count >= 10 then
          raise exception using errcode = '55000', message = 'Could not generate a unique collaboration room ID';
        end if;
    end;
  end loop;

  return jsonb_build_object(
    'id', created_room.id,
    'project_id', created_room.project_id,
    'project_name', created_room.project_name,
    'room_code', generated_code,
    'created_at', created_room.created_at
  );
end;
$$;

grant execute on function public.create_collaboration_room(text, text)
to authenticated;

create or replace function public.join_collaboration_room(
  p_room_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_code text := trim(coalesce(p_room_code, ''));
  room public.collaboration_rooms;
  member_role text;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if normalized_code !~ '^[0-9]{6}$' then
    raise exception using errcode = '22023', message = 'Room ID must contain six digits';
  end if;

  select * into room
  from public.collaboration_rooms
  where room_code_hash = encode(extensions.digest(normalized_code, 'sha256'), 'hex')
    and revoked_at is null
  limit 1;

  if room.id is null then
    raise exception using errcode = '42501', message = 'Invalid or expired collaboration room ID';
  end if;

  if public.project_role(room.project_id) = 'owner' then
    member_role := 'owner';
  else
    insert into public.workspace_members (project_id, user_id, role)
    values (room.project_id, auth.uid(), 'editor')
    on conflict (project_id, user_id) do update
      set role = case
        when workspace_members.role = 'owner' then 'owner'
        else 'editor'
      end,
      updated_at = now();
    member_role := 'editor';
  end if;

  update public.collaboration_rooms
  set last_joined_at = now()
  where id = room.id;

  return jsonb_build_object(
    'project_id', room.project_id,
    'project_name', room.project_name,
    'role', member_role
  );
end;
$$;

grant execute on function public.join_collaboration_room(text)
to authenticated;

create or replace function public.revoke_collaboration_room(
  p_project_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can revoke a collaboration room';
  end if;

  update public.collaboration_rooms
  set revoked_at = now()
  where project_id = p_project_id
    and revoked_at is null;
end;
$$;

grant execute on function public.revoke_collaboration_room(text)
to authenticated;

revoke execute on function public.create_collaboration_room(text, text)
from public, anon;
revoke execute on function public.join_collaboration_room(text)
from public, anon;
revoke execute on function public.revoke_collaboration_room(text)
from public, anon;
revoke execute on function public.get_canvas_crdt_delta(text, jsonb)
from public, anon;

-- Existing projects may have a legacy canvas snapshot before the first CRDT
-- compaction. Serve that snapshot as the initial collaboration state so a
-- guest joining immediately after room creation sees the host document.
create or replace function public.get_canvas_crdt_delta(
  p_project_id text,
  p_version_vector jsonb default '{}'::jsonb
)
returns table (
  snapshot jsonb,
  operation jsonb
)
language sql
security invoker
set search_path = public
as $$
  with current_snapshot as (
    select jsonb_build_object(
      'projectId', s.project_id,
      'state', s.state_json,
      'version', s.version_vector,
      'updatedAt', s.updated_at
    ) as snapshot
    from public.canvas_crdt_snapshots s
    where s.project_id = p_project_id
      and public.can_read_project(p_project_id)
  ),
  legacy_snapshot as (
    select jsonb_build_object(
      'projectId', s.project_id,
      'state', jsonb_build_object(
        'document', s.document_data,
        'crdt', '{}'::jsonb,
        'comments', coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'id', comment.id,
                'feedbackThreadId', comment.feedback_thread_id,
                'nodeId', comment.node_id,
                'authorId', comment.author_id,
                'authorName', comment.author_name,
                'text', comment.text,
                'x', comment.x,
                'y', comment.y,
                'resolved', comment.resolved,
                'createdAt', comment.created_at,
                'editedAt', comment.edited_at,
                'replies', comment.replies,
                'mentions', comment.mentions,
                'reactions', comment.reactions
              ) order by comment.created_at
            )
            from public.comments comment
            where comment.project_id = s.project_id
          ),
          '[]'::jsonb
        )
      ),
      'version', '{}'::jsonb,
      'updatedAt', s.updated_at
    ) as snapshot
    from public.canvas_snapshots s
    where s.project_id = p_project_id
      and public.can_read_project(p_project_id)
      and not exists (
        select 1
        from public.canvas_crdt_snapshots current_state
        where current_state.project_id = p_project_id
      )
  )
  select delta.snapshot, delta.operation
  from (
    select current_snapshot.snapshot, null::jsonb as operation, 0 as sort_order
    from current_snapshot
    union all
    select legacy_snapshot.snapshot, null::jsonb as operation, 0 as sort_order
    from legacy_snapshot
    union all
    select null::jsonb as snapshot, o.operation_json as operation, 1 as sort_order
    from public.canvas_crdt_operations o
    where o.project_id = p_project_id
      and public.can_read_project(p_project_id)
      and coalesce((p_version_vector ->> o.actor_id)::bigint, 0) < o.actor_counter
  ) as delta
  order by delta.sort_order, delta.operation;
$$;

grant execute on function public.get_canvas_crdt_delta(text, jsonb)
to authenticated;
