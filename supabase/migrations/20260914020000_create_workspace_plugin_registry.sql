create table if not exists public.workspace_plugin_registrations (
  project_id text not null references public.projects(id) on delete cascade,
  plugin_id text not null,
  manifest jsonb not null,
  state text not null default 'pendingReview'
    check (state in ('pendingReview', 'enabled', 'disabled', 'blocked')),
  approved_permissions jsonb not null default '[]'::jsonb,
  errors jsonb not null default '[]'::jsonb,
  installed_by uuid not null default auth.uid(),
  updated_by uuid not null default auth.uid(),
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (project_id, plugin_id)
);

create index if not exists workspace_plugin_registrations_project_state_idx
  on public.workspace_plugin_registrations (project_id, state, updated_at desc);

alter table public.workspace_plugin_registrations enable row level security;
revoke all on public.workspace_plugin_registrations from public, anon, authenticated;

create or replace function public.validate_workspace_plugin_manifest(p_manifest jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  plugin_id text := trim(coalesce(p_manifest ->> 'id', ''));
  plugin_name text := trim(coalesce(p_manifest ->> 'name', ''));
  plugin_version text := trim(coalesce(p_manifest ->> 'version', ''));
  api_version text := trim(coalesce(p_manifest ->> 'apiVersion', ''));
  errors jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(coalesce(p_manifest, '{}'::jsonb)) <> 'object' then
    return jsonb_build_array('Plugin manifest must be an object.');
  end if;
  if plugin_id !~ '^[a-z0-9][a-z0-9._-]{2,63}$' then
    errors := errors || jsonb_build_array('Plugin ID is invalid.');
  end if;
  if plugin_name = '' then
    errors := errors || jsonb_build_array('Plugin name is required.');
  end if;
  if plugin_version !~ '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$' then
    errors := errors || jsonb_build_array('Plugin version is invalid.');
  end if;
  if api_version !~ '^1\.\d+$' then
    errors := errors || jsonb_build_array('Plugin API version is incompatible.');
  end if;
  if jsonb_typeof(coalesce(p_manifest -> 'permissions', '[]'::jsonb)) <> 'array'
      or jsonb_typeof(coalesce(p_manifest -> 'capabilities', '[]'::jsonb)) <> 'array'
      or jsonb_typeof(coalesce(p_manifest -> 'sandboxLimits', '{}'::jsonb)) <> 'object' then
    errors := errors || jsonb_build_array('Plugin manifest collections are invalid.');
  end if;
  return errors;
end;
$$;

create or replace function public.list_workspace_plugin_registrations(p_project_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or public.project_role(p_project_id) is null then
    raise exception using errcode = '42501', message = 'Workspace plugin access denied';
  end if;
  return coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'manifest', registration.manifest,
          'state', registration.state,
          'approvedPermissions', registration.approved_permissions,
          'installedAt', registration.installed_at,
          'updatedAt', registration.updated_at,
          'errors', registration.errors
        ) order by registration.updated_at desc
      )
      from public.workspace_plugin_registrations registration
      where registration.project_id = p_project_id
    ),
    '[]'::jsonb
  );
end;
$$;

create or replace function public.upsert_workspace_plugin_registration(
  p_project_id text,
  p_manifest jsonb,
  p_state text default 'pendingReview',
  p_approved_permissions jsonb default '[]'::jsonb,
  p_errors jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  validation_errors jsonb;
  plugin_id text := trim(coalesce(p_manifest ->> 'id', ''));
  registration public.workspace_plugin_registrations;
begin
  if auth.uid() is null or not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can update plugin registrations';
  end if;
  validation_errors := public.validate_workspace_plugin_manifest(p_manifest);
  if jsonb_array_length(validation_errors) > 0 then
    raise exception using errcode = '22023', message = 'Invalid plugin manifest';
  end if;
  if p_state not in ('pendingReview', 'enabled', 'disabled', 'blocked')
      or jsonb_typeof(coalesce(p_approved_permissions, '[]'::jsonb)) <> 'array'
      or jsonb_typeof(coalesce(p_errors, '[]'::jsonb)) <> 'array'
      or (p_state = 'enabled' and (
        not (coalesce(p_approved_permissions, '[]'::jsonb) <@ coalesce(p_manifest -> 'permissions', '[]'::jsonb))
        or not (coalesce(p_manifest -> 'permissions', '[]'::jsonb) <@ coalesce(p_approved_permissions, '[]'::jsonb))
      )) then
    raise exception using errcode = '22023', message = 'Invalid plugin approval state';
  end if;
  insert into public.workspace_plugin_registrations (
    project_id, plugin_id, manifest, state, approved_permissions, errors,
    installed_by, updated_by, updated_at
  ) values (
    p_project_id, plugin_id, p_manifest, p_state, coalesce(p_approved_permissions, '[]'::jsonb),
    coalesce(p_errors, '[]'::jsonb), auth.uid(), auth.uid(), now()
  ) on conflict (project_id, plugin_id) do update set
    manifest = excluded.manifest,
    state = excluded.state,
    approved_permissions = excluded.approved_permissions,
    errors = excluded.errors,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at
  returning * into registration;
  insert into public.workspace_audit_events (project_id, action, metadata)
  values (
    p_project_id,
    'workspace.plugin.registration_updated',
    jsonb_build_object('pluginId', registration.plugin_id, 'state', registration.state)
  );
  return jsonb_build_object(
    'manifest', registration.manifest,
    'state', registration.state,
    'approvedPermissions', registration.approved_permissions,
    'installedAt', registration.installed_at,
    'updatedAt', registration.updated_at,
    'errors', registration.errors
  );
end;
$$;

create or replace function public.set_workspace_plugin_state(
  p_project_id text,
  p_plugin_id text,
  p_state text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  registration public.workspace_plugin_registrations;
begin
  if auth.uid() is null or not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can change plugin state';
  end if;
  if p_state not in ('enabled', 'disabled', 'blocked', 'pendingReview') then
    raise exception using errcode = '22023', message = 'Invalid plugin state';
  end if;
  select * into registration
  from public.workspace_plugin_registrations
  where project_id = p_project_id and plugin_id = trim(p_plugin_id);
  if registration.plugin_id is null then
    raise exception using errcode = '22023', message = 'Plugin registration not found';
  end if;
  if p_state = 'enabled'
      and (not (registration.approved_permissions <@ coalesce(registration.manifest -> 'permissions', '[]'::jsonb))
        or not (coalesce(registration.manifest -> 'permissions', '[]'::jsonb) <@ registration.approved_permissions)) then
    raise exception using errcode = '42501', message = 'Plugin requires exact permission approval';
  end if;
  update public.workspace_plugin_registrations
  set state = p_state, updated_by = auth.uid(), updated_at = now()
  where project_id = p_project_id and plugin_id = trim(p_plugin_id)
  returning * into registration;
  insert into public.workspace_audit_events (project_id, action, metadata)
  values (
    p_project_id,
    'workspace.plugin.state_changed',
    jsonb_build_object('pluginId', registration.plugin_id, 'state', registration.state)
  );
  return jsonb_build_object(
    'manifest', registration.manifest,
    'state', registration.state,
    'approvedPermissions', registration.approved_permissions,
    'installedAt', registration.installed_at,
    'updatedAt', registration.updated_at,
    'errors', registration.errors
  );
end;
$$;

create or replace function public.authorize_workspace_plugin_command(
  p_project_id text,
  p_plugin_id text,
  p_command_type text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  registration public.workspace_plugin_registrations;
  required_permission text;
begin
  if auth.uid() is null or public.project_role(p_project_id) not in ('owner', 'editor') then
    raise exception using errcode = '42501', message = 'Workspace plugin command access denied';
  end if;
  required_permission := case p_command_type
    when 'createNode' then 'writeNodes'
    when 'updateNode' then 'writeNodes'
    when 'deleteNode' then 'writeNodes'
    when 'exportDocument' then 'export'
    else null
  end;
  if required_permission is null then
    raise exception using errcode = '22023', message = 'Unsupported plugin command';
  end if;
  select * into registration
  from public.workspace_plugin_registrations
  where project_id = p_project_id and plugin_id = trim(p_plugin_id);
  if registration.plugin_id is null or registration.state <> 'enabled' then
    raise exception using errcode = '42501', message = 'Plugin is not enabled';
  end if;
  if not (registration.approved_permissions @> jsonb_build_array(required_permission)) then
    raise exception using errcode = '42501', message = 'Plugin command permission denied';
  end if;
  return jsonb_build_object(
    'allowed', true,
    'projectId', p_project_id,
    'pluginId', registration.plugin_id,
    'commandType', p_command_type,
    'permission', required_permission,
    'state', registration.state
  );
end;
$$;

grant execute on function public.validate_workspace_plugin_manifest(jsonb) to authenticated;
grant execute on function public.list_workspace_plugin_registrations(text) to authenticated;
grant execute on function public.upsert_workspace_plugin_registration(text, jsonb, text, jsonb, jsonb) to authenticated;
grant execute on function public.set_workspace_plugin_state(text, text, text) to authenticated;
grant execute on function public.authorize_workspace_plugin_command(text, text, text) to authenticated;

revoke execute on function public.validate_workspace_plugin_manifest(jsonb) from public, anon;
revoke execute on function public.list_workspace_plugin_registrations(text) from public, anon;
revoke execute on function public.upsert_workspace_plugin_registration(text, jsonb, text, jsonb, jsonb) from public, anon;
revoke execute on function public.set_workspace_plugin_state(text, text, text) from public, anon;
revoke execute on function public.authorize_workspace_plugin_command(text, text, text) from public, anon;
