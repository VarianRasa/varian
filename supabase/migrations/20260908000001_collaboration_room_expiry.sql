alter table public.collaboration_rooms
  add column if not exists expires_at timestamptz;

create index if not exists collaboration_rooms_expiry_idx
  on public.collaboration_rooms (expires_at)
  where revoked_at is null;

drop function if exists public.create_collaboration_room(text, text);

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

  return jsonb_build_object(
    'id', created_room.id,
    'project_id', created_room.project_id,
    'project_name', created_room.project_name,
    'room_code', generated_code,
    'created_at', created_room.created_at,
    'expires_at', created_room.expires_at
  );
end;
$$;

grant execute on function public.create_collaboration_room(text, text, timestamptz)
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
    and (expires_at is null or expires_at > now())
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
    'id', room.id,
    'project_id', room.project_id,
    'project_name', room.project_name,
    'created_at', room.created_at,
    'expires_at', room.expires_at,
    'role', member_role
  );
end;
$$;

grant execute on function public.join_collaboration_room(text)
to authenticated;

revoke execute on function public.create_collaboration_room(text, text, timestamptz)
from public, anon;
revoke execute on function public.join_collaboration_room(text)
from public, anon;
