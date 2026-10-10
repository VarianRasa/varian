-- Persistent member metadata for collaboration roster and role management.
-- Realtime presence remains ephemeral; this table stores only safe profile data
-- and the last authenticated activity timestamp.

alter table public.workspace_members
  add column if not exists display_name text not null default 'Collaborator',
  add column if not exists avatar_url text,
  add column if not exists last_seen_at timestamptz;

create index if not exists workspace_members_project_last_seen_idx
  on public.workspace_members (project_id, last_seen_at desc);

create or replace function public.upsert_workspace_member_profile(
  p_project_id text,
  p_display_name text default 'Collaborator',
  p_avatar_url text default null
)
returns public.workspace_members
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.workspace_members;
  normalized_name text := coalesce(nullif(trim(p_display_name), ''), 'Collaborator');
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if public.project_role(p_project_id) is null then
    raise exception using errcode = '42501', message = 'Not authorized to access project';
  end if;

  insert into public.workspace_members (
    project_id,
    user_id,
    role,
    display_name,
    avatar_url,
    last_seen_at
  )
  values (
    p_project_id,
    auth.uid(),
    coalesce(public.project_role(p_project_id), 'viewer'),
    normalized_name,
    nullif(trim(coalesce(p_avatar_url, '')), ''),
    now()
  )
  on conflict (project_id, user_id) do update
    set display_name = excluded.display_name,
        avatar_url = excluded.avatar_url,
        last_seen_at = now(),
        updated_at = now()
  returning * into result;

  return result;
end;
$$;

grant execute on function public.upsert_workspace_member_profile(text, text, text)
to authenticated;
revoke execute on function public.upsert_workspace_member_profile(text, text, text)
from public, anon;

create or replace function public.touch_workspace_member(
  p_project_id text
)
returns public.workspace_members
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.workspace_members;
begin
  if auth.uid() is null or public.project_role(p_project_id) is null then
    raise exception using errcode = '42501', message = 'Not authorized to access project';
  end if;

  update public.workspace_members
  set last_seen_at = now(),
      updated_at = now()
  where project_id = p_project_id
    and user_id = auth.uid()
  returning * into result;

  if result.user_id is null then
    raise exception using errcode = '42501', message = 'Workspace member not found';
  end if;
  return result;
end;
$$;

grant execute on function public.touch_workspace_member(text)
to authenticated;
revoke execute on function public.touch_workspace_member(text)
from public, anon;

-- Keep the owner visible in the persistent roster when a room is created.
create or replace function public.create_collaboration_room(
  p_project_id text,
  p_project_name text default 'Untitled Project',
  p_expires_at timestamptz default null
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
  if p_expires_at is not null and p_expires_at <= now() then
    raise exception using errcode = '22023', message = 'Room expiration must be in the future';
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
        created_by,
        expires_at
      ) values (
        p_project_id,
        encode(extensions.digest(generated_code, 'sha256'), 'hex'),
        normalized_name,
        auth.uid(),
        p_expires_at
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

  insert into public.workspace_members (
    project_id,
    user_id,
    role,
    display_name,
    last_seen_at
  ) values (
    p_project_id,
    auth.uid(),
    'owner',
    'Host',
    now()
  )
  on conflict (project_id, user_id) do update
    set role = 'owner',
        last_seen_at = now(),
        updated_at = now();

  return jsonb_build_object(
    'id', created_room.id,
    'project_id', created_room.project_id,
    'project_name', created_room.project_name,
    'room_code', generated_code,
    'created_at', created_room.created_at,
    'expires_at', created_room.expires_at,
    'role', 'owner'
  );
end;
$$;

grant execute on function public.create_collaboration_room(text, text, timestamptz)
to authenticated;
revoke execute on function public.create_collaboration_room(text, text, timestamptz)
from public, anon;

create or replace function public.join_collaboration_room(
  p_room_code text,
  p_display_name text default 'Collaborator'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_code text := trim(coalesce(p_room_code, ''));
  normalized_name text := coalesce(nullif(trim(p_display_name), ''), 'Collaborator');
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
    and (expires_at is null or expires_at > now())
  limit 1;

  if room.id is null then
    raise exception using errcode = '42501', message = 'Invalid or expired collaboration room ID';
  end if;

  if public.project_role(room.project_id) = 'owner' then
    member_role := 'owner';
    insert into public.workspace_members (
      project_id, user_id, role, display_name, last_seen_at
    ) values (
      room.project_id, auth.uid(), 'owner', normalized_name, now()
    )
    on conflict (project_id, user_id) do update
      set role = 'owner',
          display_name = excluded.display_name,
          last_seen_at = now(),
          updated_at = now();
  else
    insert into public.workspace_members (
      project_id, user_id, role, display_name, last_seen_at
    ) values (
      room.project_id, auth.uid(), 'editor', normalized_name, now()
    )
    on conflict (project_id, user_id) do update
      set display_name = excluded.display_name,
          last_seen_at = now(),
          updated_at = now();

    select role into member_role
    from public.workspace_members
    where project_id = room.project_id
      and user_id = auth.uid();
  end if;

  update public.collaboration_rooms
  set last_joined_at = now()
  where id = room.id;

  return jsonb_build_object(
    'id', room.id,
    'project_id', room.project_id,
    'project_name', room.project_name,
    'created_at', room.created_at,
    'expires_at', room.expires_at,
    'role', coalesce(member_role, 'viewer')
  );
end;
$$;

grant execute on function public.join_collaboration_room(text, text)
to authenticated;
revoke execute on function public.join_collaboration_room(text, text)
from public, anon;

create or replace function public.join_collaboration_room(
  p_room_code text
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.join_collaboration_room(p_room_code, 'Collaborator');
$$;

grant execute on function public.join_collaboration_room(text)
to authenticated;
revoke execute on function public.join_collaboration_room(text)
from public, anon;
