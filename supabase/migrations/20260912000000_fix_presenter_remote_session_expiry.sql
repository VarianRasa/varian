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
  effective_expires_at timestamptz := coalesce(
    p_expires_at,
    now() + interval '15 minutes'
  );
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_presenter_id is null
      or p_role not in ('owner', 'presenter', 'viewer')
      or effective_expires_at <= now() then
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
    effective_expires_at
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

revoke all on function public.create_presenter_remote_session(text, uuid, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.create_presenter_remote_session(text, uuid, text, timestamptz)
  to authenticated;
