-- Video meeting lifecycle and authorization boundary.
-- Provider credentials and participant media remain outside this table.

create table public.meeting_sessions (
  id uuid primary key default gen_random_uuid(),
  project_id text not null references public.projects(id) on delete cascade,
  created_by uuid not null,
  provider text not null default 'livekit',
  provider_room_name text not null unique,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  ended_at timestamptz,
  ended_reason text check (ended_reason is null or ended_reason in ('host_ended', 'room_revoked', 'expired', 'admin_ended')),
  max_participants integer not null default 8,
  constraint meeting_sessions_provider_check check (provider = 'livekit'),
  constraint meeting_sessions_status_check check (status in ('active', 'ended')),
  constraint meeting_sessions_capacity_check check (max_participants between 2 and 8),
  constraint meeting_sessions_lifecycle_check check (
    (status = 'active' and ended_at is null and ended_reason is null)
    or (status = 'ended' and ended_at is not null and ended_reason is not null)
  )
);

create unique index meeting_sessions_one_active_per_project_idx
  on public.meeting_sessions (project_id)
  where status = 'active';

alter table public.meeting_sessions enable row level security;
revoke all on table public.meeting_sessions from public, anon, authenticated;
grant select on table public.meeting_sessions to authenticated;
create policy meeting_sessions_select_member
  on public.meeting_sessions
  for select
  to authenticated
  using (public.project_role(project_id) is not null);
do $meeting_realtime$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'meeting_sessions'
  ) then
    execute 'alter publication supabase_realtime add table public.meeting_sessions';
  end if;
end
$meeting_realtime$;
create or replace function public.create_meeting_session(
  p_project_id text,
  p_max_participants integer default 8
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  session_row public.meeting_sessions;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can create a meeting';
  end if;
  if p_max_participants is null or p_max_participants < 2 or p_max_participants > 8 then
    raise exception using errcode = '22023', message = 'Meeting capacity must be between 2 and 8';
  end if;

  select * into session_row
  from public.meeting_sessions
  where project_id = p_project_id
    and status = 'active'
  limit 1;
  if session_row.id is not null then
    return to_jsonb(session_row);
  end if;

  insert into public.meeting_sessions (
    id, project_id, created_by, provider, provider_room_name, status, max_participants
  )
  values (
    gen_random_uuid(), p_project_id, auth.uid(), 'livekit',
    'meeting-' || replace(gen_random_uuid()::text, '-', ''), 'active', p_max_participants
  )
  on conflict (project_id) where status = 'active' do nothing
  returning * into session_row;

  if session_row.id is null then
    select * into session_row
    from public.meeting_sessions
    where project_id = p_project_id
      and status = 'active'
    limit 1;
  end if;
  return to_jsonb(session_row);
end;
$function$;

create or replace function public.join_meeting_session(
  p_meeting_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  session_row public.meeting_sessions;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  select * into session_row
  from public.meeting_sessions
  where id = p_meeting_id;
  if session_row.id is null then
    raise exception using errcode = 'P0002', message = 'Meeting is unavailable';
  end if;
  if public.project_role(session_row.project_id) is null then
    raise exception using errcode = 'P0002', message = 'Meeting is unavailable';
  end if;
  if session_row.status = 'ended' then
    raise exception using errcode = 'P0003', message = 'Meeting has ended';
  end if;
  return to_jsonb(session_row);
end;
$function$;

create or replace function public.end_meeting_session(
  p_meeting_id uuid,
  p_reason text default 'host_ended'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  session_row public.meeting_sessions;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_reason is null or p_reason not in ('host_ended', 'room_revoked', 'expired', 'admin_ended') then
    raise exception using errcode = '22023', message = 'Invalid meeting termination reason';
  end if;

  select * into session_row
  from public.meeting_sessions
  where id = p_meeting_id;
  if session_row.id is null then
    raise exception using errcode = 'P0002', message = 'Meeting is unavailable';
  end if;
  if not (
    public.is_project_owner(session_row.project_id)
    or (
      session_row.created_by = auth.uid()
      and public.project_role(session_row.project_id) is not null
    )
  ) then
    raise exception using errcode = '42501', message = 'Only the meeting host can end it';
  end if;
  if session_row.status = 'ended' then
    return to_jsonb(session_row);
  end if;

  update public.meeting_sessions
  set status = 'ended',
      ended_at = now(),
      ended_reason = p_reason
  where id = p_meeting_id
  returning * into session_row;
  return to_jsonb(session_row);
end;
$function$;

revoke all on function public.create_meeting_session(text, integer) from public, anon, authenticated;
revoke all on function public.join_meeting_session(uuid) from public, anon, authenticated;
revoke all on function public.end_meeting_session(uuid, text) from public, anon, authenticated;
grant execute on function public.create_meeting_session(text, integer) to authenticated;
grant execute on function public.join_meeting_session(uuid) to authenticated;
grant execute on function public.end_meeting_session(uuid, text) to authenticated;
