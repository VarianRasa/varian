-- Keep project authorization explicit inside security-definer collaboration RPCs.
-- A removed member is blocked only from the active room that removed them; a
-- newly-created room can invite the same user again.

create or replace function public.can_read_project(p_project_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.projects p
      where p.id = p_project_id
        and (
          p.owner_id = auth.uid()
          or exists (
            select 1
            from public.workspace_members wm
            where wm.project_id = p.id
              and wm.user_id = auth.uid()
          )
        )
    );
$$;

create or replace function public.can_comment_project(p_project_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.projects p
      where p.id = p_project_id
        and (
          p.owner_id = auth.uid()
          or exists (
            select 1
            from public.workspace_members wm
            where wm.project_id = p.id
              and wm.user_id = auth.uid()
              and wm.role in ('owner', 'editor', 'commenter')
          )
        )
    );
$$;

create or replace function public.can_edit_project(p_project_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.projects p
      where p.id = p_project_id
        and (
          p.owner_id = auth.uid()
          or exists (
            select 1
            from public.workspace_members wm
            where wm.project_id = p.id
              and wm.user_id = auth.uid()
              and wm.role in ('owner', 'editor')
          )
        )
    );
$$;

create or replace function public.is_project_owner(p_project_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
    and exists (
      select 1
      from public.projects p
      where p.id = p_project_id
        and p.owner_id = auth.uid()
    );
$$;

create table if not exists public.collaboration_room_blocks (
  room_id uuid not null references public.collaboration_rooms(id) on delete cascade,
  user_id uuid not null,
  blocked_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

create index if not exists collaboration_room_blocks_user_idx
  on public.collaboration_room_blocks (user_id, created_at desc);

alter table public.collaboration_room_blocks enable row level security;
revoke all on public.collaboration_room_blocks from public, anon, authenticated;

create or replace function public.remove_canvas_member(
  p_project_id text,
  p_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  active_room_id uuid;
begin
  if not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can manage members';
  end if;
  if p_user_id is null or p_user_id = auth.uid() then
    raise exception using errcode = '22023', message = 'Invalid member to remove';
  end if;

  select id into active_room_id
  from public.collaboration_rooms
  where project_id = p_project_id
    and revoked_at is null
  order by created_at desc
  limit 1;

  delete from public.workspace_members
  where project_id = p_project_id
    and user_id = p_user_id;

  if active_room_id is not null then
    insert into public.collaboration_room_blocks (room_id, user_id, blocked_by)
    values (active_room_id, p_user_id, auth.uid())
    on conflict (room_id, user_id) do update
      set blocked_by = excluded.blocked_by,
          created_at = now();
  end if;
end;
$$;

grant execute on function public.remove_canvas_member(text, uuid)
to authenticated;
revoke execute on function public.remove_canvas_member(text, uuid)
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
