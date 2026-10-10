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
  raw_name text := coalesce(p_display_name, '');
  normalized_name text;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if public.project_role(p_project_id) is null then
    raise exception using errcode = '42501', message = 'Not authorized to access project';
  end if;
  if raw_name ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'Display name contains invalid characters';
  end if;

  normalized_name := regexp_replace(trim(raw_name), '[[:space:]]+', ' ', 'g');
  if char_length(normalized_name) < 2 or char_length(normalized_name) > 32 then
    raise exception using errcode = '22023', message = 'Display name must contain 2 to 32 characters';
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
  raw_name text := coalesce(p_display_name, '');
  normalized_name text;
  room public.collaboration_rooms;
  member_role text;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if normalized_code !~ '^[0-9]{6}$' then
    raise exception using errcode = '22023', message = 'Room ID must contain six digits';
  end if;
  if raw_name ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'Display name contains invalid characters';
  end if;

  normalized_name := regexp_replace(trim(raw_name), '[[:space:]]+', ' ', 'g');
  if char_length(normalized_name) < 2 or char_length(normalized_name) > 32 then
    raise exception using errcode = '22023', message = 'Display name must contain 2 to 32 characters';
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

  if exists (
    select 1
    from public.collaboration_room_blocks block
    where block.room_id = room.id
      and block.user_id = auth.uid()
  ) then
    raise exception using errcode = '42501', message = 'You were removed from this collaboration room';
  end if;

  if public.is_project_owner(room.project_id) then
    member_role := 'owner';
    insert into public.workspace_members (
      project_id, user_id, role, display_name, last_seen_at
    ) values (
      room.project_id, auth.uid(), 'owner', normalized_name, now()
    )
    on conflict (project_id, user_id) do update
      set role = 'owner',
          display_name = case
            when workspace_members.display_name is null
              or lower(trim(workspace_members.display_name)) in
                ('', 'architect', 'collaborator', 'guest', 'host', 'user')
            then excluded.display_name
            else workspace_members.display_name
          end,
          last_seen_at = now(),
          updated_at = now();
  else
    insert into public.workspace_members (
      project_id, user_id, role, display_name, last_seen_at
    ) values (
      room.project_id, auth.uid(), 'editor', normalized_name, now()
    )
    on conflict (project_id, user_id) do update
      set display_name = case
            when workspace_members.display_name is null
              or lower(trim(workspace_members.display_name)) in
                ('', 'architect', 'collaborator', 'guest', 'host', 'user')
            then excluded.display_name
            else workspace_members.display_name
          end,
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
