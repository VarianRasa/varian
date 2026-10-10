-- Backend-enforced remote presenter sessions. Broadcasts remain ephemeral;
-- authorization and command idempotency are persisted here.

create extension if not exists pgcrypto;

create table if not exists public.presenter_remote_sessions (
  id uuid primary key default gen_random_uuid(),
  project_id text not null references public.projects(id) on delete cascade,
  created_by uuid not null default auth.uid(),
  presenter_id uuid not null,
  role text not null check (role in ('owner', 'presenter', 'viewer')),
  expires_at timestamptz not null,
  consent_granted boolean not null default false,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.presenter_remote_commands (
  session_id uuid not null references public.presenter_remote_sessions(id)
    on delete cascade,
  command_id text not null,
  actor_id uuid not null default auth.uid(),
  action text not null check (
    action in ('next', 'previous', 'jump', 'pause', 'resume', 'stop')
  ),
  frame_index integer,
  created_at timestamptz not null default now(),
  primary key (session_id, command_id)
);

create index if not exists presenter_remote_sessions_project_active_idx
  on public.presenter_remote_sessions (project_id, revoked_at, expires_at);
create index if not exists presenter_remote_commands_session_created_idx
  on public.presenter_remote_commands (session_id, created_at);

alter table public.presenter_remote_sessions enable row level security;
alter table public.presenter_remote_commands enable row level security;
revoke all on public.presenter_remote_sessions from public, anon, authenticated;
revoke all on public.presenter_remote_commands from public, anon, authenticated;

create or replace function public.create_presenter_remote_session(
  p_project_id text,
  p_presenter_id uuid,
  p_role text default 'presenter',
  p_expires_at timestamptz default (now() + interval '15 minutes')
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  created_session public.presenter_remote_sessions;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_presenter_id is null
      or p_role not in ('owner', 'presenter', 'viewer')
      or p_expires_at <= now() then
    raise exception using errcode = '22023', message = 'Invalid presenter remote session';
  end if;
  if public.project_role(p_project_id) not in ('owner', 'editor') then
    raise exception using errcode = '42501', message = 'Only project editors can create presenter remote sessions';
  end if;
  if p_role = 'owner' and not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can grant owner presenter control';
  end if;

  insert into public.presenter_remote_sessions (
    project_id,
    created_by,
    presenter_id,
    role,
    expires_at
  ) values (
    p_project_id,
    auth.uid(),
    p_presenter_id,
    p_role,
    p_expires_at
  )
  returning * into created_session;

  return jsonb_build_object(
    'sessionId', created_session.id,
    'projectId', created_session.project_id,
    'presenterId', created_session.presenter_id,
    'role', created_session.role,
    'expiresAt', created_session.expires_at,
    'consentGranted', created_session.consent_granted
  );
end;
$$;

create or replace function public.get_presenter_remote_session(
  p_session_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  remote_session public.presenter_remote_sessions;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  select * into remote_session
  from public.presenter_remote_sessions
  where id = p_session_id
    and (
      created_by = auth.uid()
      or presenter_id = auth.uid()
      or public.is_project_owner(project_id)
    );

  if remote_session.id is null then
    raise exception using errcode = '42501', message = 'Presenter remote session is unavailable';
  end if;

  return jsonb_build_object(
    'sessionId', remote_session.id,
    'projectId', remote_session.project_id,
    'presenterId', remote_session.presenter_id,
    'role', remote_session.role,
    'expiresAt', remote_session.expires_at,
    'consentGranted', remote_session.consent_granted,
    'revokedAt', remote_session.revoked_at
  );
end;
$$;

create or replace function public.grant_presenter_remote_consent(
  p_session_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  remote_session public.presenter_remote_sessions;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  update public.presenter_remote_sessions
  set consent_granted = true,
      updated_at = now()
  where id = p_session_id
    and presenter_id = auth.uid()
    and revoked_at is null
    and expires_at > now()
  returning * into remote_session;

  if remote_session.id is null then
    raise exception using errcode = '42501', message = 'Presenter remote consent is no longer available';
  end if;

  return jsonb_build_object(
    'sessionId', remote_session.id,
    'projectId', remote_session.project_id,
    'presenterId', remote_session.presenter_id,
    'role', remote_session.role,
    'expiresAt', remote_session.expires_at,
    'consentGranted', remote_session.consent_granted
  );
end;
$$;

create or replace function public.revoke_presenter_remote_session(
  p_session_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  remote_project_id text;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  select project_id into remote_project_id
  from public.presenter_remote_sessions
  where id = p_session_id;

  if remote_project_id is null then
    return;
  end if;
  if not public.is_project_owner(remote_project_id)
      and not exists (
        select 1
        from public.presenter_remote_sessions
        where id = p_session_id
          and created_by = auth.uid()
      ) then
    raise exception using errcode = '42501', message = 'Only the session owner can revoke presenter remote control';
  end if;

  update public.presenter_remote_sessions
  set revoked_at = coalesce(revoked_at, now()),
      consent_granted = false,
      updated_at = now()
  where id = p_session_id;
end;
$$;

create or replace function public.append_presenter_remote_command(
  p_session_id uuid,
  p_command_id text,
  p_action text,
  p_frame_index integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  remote_session public.presenter_remote_sessions;
  command_row public.presenter_remote_commands;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_command_id is null or length(trim(p_command_id)) < 8
      or p_action not in ('next', 'previous', 'jump', 'pause', 'resume', 'stop') then
    raise exception using errcode = '22023', message = 'Invalid presenter remote command';
  end if;
  if p_action = 'jump' and p_frame_index is null then
    raise exception using errcode = '22023', message = 'Jump command requires a frame index';
  end if;

  select * into remote_session
  from public.presenter_remote_sessions
  where id = p_session_id
  for update;

  if remote_session.id is null
      or remote_session.revoked_at is not null
      or remote_session.expires_at <= now()
      or not remote_session.consent_granted then
    raise exception using errcode = '42501', message = 'Presenter remote session is expired or revoked';
  end if;
  if auth.uid() <> remote_session.created_by
      and auth.uid() <> remote_session.presenter_id then
    raise exception using errcode = '42501', message = 'User is not a participant in this presenter remote session';
  end if;
  if p_action <> 'stop' and auth.uid() <> remote_session.created_by then
    raise exception using errcode = '42501', message = 'Only the remote controller can send this command';
  end if;

  insert into public.presenter_remote_commands (
    session_id,
    command_id,
    actor_id,
    action,
    frame_index
  ) values (
    remote_session.id,
    trim(p_command_id),
    auth.uid(),
    p_action,
    p_frame_index
  )
  on conflict (session_id, command_id) do nothing
  returning * into command_row;

  if command_row.command_id is null then
    select * into command_row
    from public.presenter_remote_commands
    where session_id = remote_session.id
      and command_id = trim(p_command_id);
  end if;

  if p_action = 'stop' then
    update public.presenter_remote_sessions
    set revoked_at = coalesce(revoked_at, now()),
        consent_granted = false,
        updated_at = now()
    where id = remote_session.id;
  end if;

  return jsonb_build_object(
    'commandId', command_row.command_id,
    'sessionId', command_row.session_id,
    'action', command_row.action,
    'frameIndex', command_row.frame_index,
    'createdAt', command_row.created_at,
    'actorId', command_row.actor_id,
    'projectId', remote_session.project_id
  );
end;
$$;

grant execute on function public.create_presenter_remote_session(text, uuid, text, timestamptz)
  to authenticated;
grant execute on function public.get_presenter_remote_session(uuid)
  to authenticated;
grant execute on function public.grant_presenter_remote_consent(uuid)
  to authenticated;
grant execute on function public.revoke_presenter_remote_session(uuid)
  to authenticated;
grant execute on function public.append_presenter_remote_command(uuid, text, text, integer)
  to authenticated;

revoke execute on function public.create_presenter_remote_session(text, uuid, text, timestamptz)
  from public, anon;
revoke execute on function public.get_presenter_remote_session(uuid)
  from public, anon;
revoke execute on function public.grant_presenter_remote_consent(uuid)
  from public, anon;
revoke execute on function public.revoke_presenter_remote_session(uuid)
  from public, anon;
revoke execute on function public.append_presenter_remote_command(uuid, text, text, integer)
  from public, anon;
