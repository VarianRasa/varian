create table if not exists public.workspace_observability_events (
  id uuid primary key default gen_random_uuid(),
  project_id text not null references public.projects(id) on delete cascade,
  event_type text not null,
  severity text not null check (severity in ('info', 'warning', 'error')),
  correlation_id text not null,
  payload jsonb not null default '{}'::jsonb,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  unique (project_id, event_type, correlation_id)
);

create table if not exists public.workspace_support_bundles (
  id uuid primary key default gen_random_uuid(),
  project_id text not null references public.projects(id) on delete cascade,
  operation_id text not null,
  checksum text not null,
  bundle_json jsonb not null,
  status text not null default 'ready'
    check (status in ('ready', 'expired', 'failed')),
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  unique (project_id, operation_id)
);

create table if not exists public.workspace_release_policies (
  project_id text primary key references public.projects(id) on delete cascade,
  channel text not null check (channel in ('stable', 'beta', 'nightly')),
  version text not null,
  rollback_version text,
  released_at timestamptz not null default now(),
  rollback_until timestamptz,
  updated_by uuid not null default auth.uid(),
  updated_at timestamptz not null default now()
);

create index if not exists workspace_observability_project_created_idx
  on public.workspace_observability_events (project_id, created_at desc);
create index if not exists workspace_support_bundles_project_created_idx
  on public.workspace_support_bundles (project_id, created_at desc);

alter table public.workspace_observability_events enable row level security;
alter table public.workspace_support_bundles enable row level security;
alter table public.workspace_release_policies enable row level security;

revoke all on public.workspace_observability_events from public, anon, authenticated;
revoke all on public.workspace_support_bundles from public, anon, authenticated;
revoke all on public.workspace_release_policies from public, anon, authenticated;

create or replace function public.record_workspace_observability_event(
  p_project_id text,
  p_event_type text,
  p_severity text,
  p_correlation_id text,
  p_payload jsonb default '{}'::jsonb,
  p_recorded_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  event_row public.workspace_observability_events;
  normalized_payload jsonb;
  is_duplicate boolean := false;
begin
  if auth.uid() is null or public.project_role(p_project_id) is null then
    raise exception using errcode = '42501', message = 'Workspace observability access denied';
  end if;
  if length(trim(coalesce(p_event_type, ''))) < 2
      or length(trim(p_event_type)) > 128
      or p_severity not in ('info', 'warning', 'error')
      or length(trim(coalesce(p_correlation_id, ''))) < 8
      or length(trim(p_correlation_id)) > 128 then
    raise exception using errcode = '22023', message = 'Invalid workspace observability event';
  end if;
  if jsonb_typeof(coalesce(p_payload, '{}'::jsonb)) <> 'object'
      or octet_length((coalesce(p_payload, '{}'::jsonb))::text) > 65536 then
    raise exception using errcode = '22023', message = 'Workspace observability payload is too large';
  end if;
  normalized_payload := jsonb_strip_nulls(
    coalesce(p_payload, '{}'::jsonb) - array[
      'accessToken', 'access_token', 'refreshToken', 'refresh_token',
      'serviceRoleKey', 'service_role_key', 'apiKey', 'api_key',
      'password', 'privateKey', 'private_key', 'turnSecret', 'turn_secret'
    ]::text[]
  );
  insert into public.workspace_observability_events (
    project_id, event_type, severity, correlation_id, payload, created_at
  ) values (
    p_project_id,
    trim(p_event_type),
    p_severity,
    trim(p_correlation_id),
    normalized_payload,
    coalesce(p_recorded_at, now())
  ) on conflict (project_id, event_type, correlation_id) do nothing
  returning * into event_row;
  if event_row.id is null then
    is_duplicate := true;
    select * into event_row
    from public.workspace_observability_events
    where project_id = p_project_id
      and event_type = trim(p_event_type)
      and correlation_id = trim(p_correlation_id);
  end if;
  return jsonb_build_object(
    'id', event_row.id,
    'projectId', event_row.project_id,
    'eventType', event_row.event_type,
    'severity', event_row.severity,
    'correlationId', event_row.correlation_id,
    'duplicate', is_duplicate,
    'createdAt', event_row.created_at
  );
end;
$$;

create or replace function public.submit_workspace_support_bundle(
  p_project_id text,
  p_operation_id text,
  p_checksum text,
  p_bundle jsonb,
  p_expires_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bundle_row public.workspace_support_bundles;
  normalized_bundle jsonb;
  expiry timestamptz := coalesce(p_expires_at, now() + interval '7 days');
begin
  if auth.uid() is null or public.project_role(p_project_id) is null then
    raise exception using errcode = '42501', message = 'Workspace support bundle access denied';
  end if;
  if length(trim(coalesce(p_operation_id, ''))) < 8
      or length(trim(p_operation_id)) > 128
      or trim(coalesce(p_checksum, '')) !~ '^[0-9a-fA-F]{64}$' then
    raise exception using errcode = '22023', message = 'Invalid workspace support bundle identity';
  end if;
  if jsonb_typeof(coalesce(p_bundle, '{}'::jsonb)) <> 'object'
      or octet_length((coalesce(p_bundle, '{}'::jsonb))::text) > 2097152 then
    raise exception using errcode = '22023', message = 'Workspace support bundle is too large';
  end if;
  if expiry <= now() or expiry > now() + interval '30 days' then
    raise exception using errcode = '22023', message = 'Workspace support bundle expiry is invalid';
  end if;
  normalized_bundle := jsonb_strip_nulls(
    coalesce(p_bundle, '{}'::jsonb) - array[
      'accessToken', 'access_token', 'refreshToken', 'refresh_token',
      'serviceRoleKey', 'service_role_key', 'apiKey', 'api_key',
      'password', 'privateKey', 'private_key', 'turnSecret', 'turn_secret'
    ]::text[]
  );
  insert into public.workspace_support_bundles (
    project_id, operation_id, checksum, bundle_json, expires_at
  ) values (
    p_project_id,
    trim(p_operation_id),
    lower(trim(p_checksum)),
    normalized_bundle,
    expiry
  ) on conflict (project_id, operation_id) do update set
    checksum = public.workspace_support_bundles.checksum,
    bundle_json = public.workspace_support_bundles.bundle_json,
    expires_at = public.workspace_support_bundles.expires_at
  returning * into bundle_row;
  return jsonb_build_object(
    'id', bundle_row.id,
    'projectId', bundle_row.project_id,
    'operationId', bundle_row.operation_id,
    'status', case when bundle_row.expires_at <= now() then 'expired' else bundle_row.status end,
    'checksum', bundle_row.checksum,
    'createdAt', bundle_row.created_at,
    'expiresAt', bundle_row.expires_at,
    'artifactUri', null
  );
end;
$$;

create or replace function public.get_workspace_support_bundle(
  p_project_id text,
  p_operation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  bundle_row public.workspace_support_bundles;
begin
  if auth.uid() is null or not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can read support bundles';
  end if;
  select * into bundle_row
  from public.workspace_support_bundles
  where project_id = p_project_id and operation_id = trim(p_operation_id);
  if bundle_row.id is null then
    raise exception using errcode = '22023', message = 'Support bundle not found';
  end if;
  if bundle_row.expires_at <= now() then
    update public.workspace_support_bundles
    set status = 'expired'
    where id = bundle_row.id;
    raise exception using errcode = '41000', message = 'Support bundle expired';
  end if;
  return jsonb_build_object(
    'id', bundle_row.id,
    'projectId', bundle_row.project_id,
    'operationId', bundle_row.operation_id,
    'status', bundle_row.status,
    'checksum', bundle_row.checksum,
    'bundle', bundle_row.bundle_json,
    'createdAt', bundle_row.created_at,
    'expiresAt', bundle_row.expires_at
  );
end;
$$;

create or replace function public.get_workspace_release_policy(
  p_project_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  policy_row public.workspace_release_policies;
begin
  if auth.uid() is null or public.project_role(p_project_id) is null then
    raise exception using errcode = '42501', message = 'Workspace release policy access denied';
  end if;
  select * into policy_row
  from public.workspace_release_policies
  where project_id = p_project_id;
  if policy_row.project_id is null then
    return jsonb_build_object(
      'projectId', p_project_id,
      'channel', 'stable',
      'version', '0.0.0',
      'rollbackVersion', null,
      'releasedAt', now(),
      'rollbackUntil', null,
      'updatedAt', now()
    );
  end if;
  return jsonb_build_object(
    'projectId', policy_row.project_id,
    'channel', policy_row.channel,
    'version', policy_row.version,
    'rollbackVersion', policy_row.rollback_version,
    'releasedAt', policy_row.released_at,
    'rollbackUntil', policy_row.rollback_until,
    'updatedAt', policy_row.updated_at
  );
end;
$$;

create or replace function public.upsert_workspace_release_policy(
  p_project_id text,
  p_channel text,
  p_version text,
  p_rollback_version text default null,
  p_released_at timestamptz default now(),
  p_rollback_until timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  policy_row public.workspace_release_policies;
  released timestamptz := coalesce(p_released_at, now());
  rollback_until timestamptz := coalesce(p_rollback_until, released + interval '7 days');
begin
  if auth.uid() is null or not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can update release policy';
  end if;
  if p_channel not in ('stable', 'beta', 'nightly')
      or trim(coalesce(p_version, '')) !~ '^([0-9]+)\.([0-9]+)\.([0-9]+)([-+][0-9A-Za-z.-]+)?$'
      or (p_rollback_version is not null and trim(p_rollback_version) !~ '^([0-9]+)\.([0-9]+)\.([0-9]+)([-+][0-9A-Za-z.-]+)?$')
      or rollback_until < released then
    raise exception using errcode = '22023', message = 'Invalid workspace release policy';
  end if;
  insert into public.workspace_release_policies (
    project_id, channel, version, rollback_version, released_at, rollback_until,
    updated_by, updated_at
  ) values (
    p_project_id, p_channel, trim(p_version), nullif(trim(p_rollback_version), ''),
    released, rollback_until, auth.uid(), now()
  ) on conflict (project_id) do update set
    channel = excluded.channel,
    version = excluded.version,
    rollback_version = excluded.rollback_version,
    released_at = excluded.released_at,
    rollback_until = excluded.rollback_until,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at
  returning * into policy_row;
  insert into public.workspace_audit_events (project_id, action, metadata)
  values (
    p_project_id,
    'workspace.release_policy.updated',
    jsonb_build_object('channel', policy_row.channel, 'version', policy_row.version)
  );
  return jsonb_build_object(
    'projectId', policy_row.project_id,
    'channel', policy_row.channel,
    'version', policy_row.version,
    'rollbackVersion', policy_row.rollback_version,
    'releasedAt', policy_row.released_at,
    'rollbackUntil', policy_row.rollback_until,
    'updatedAt', policy_row.updated_at
  );
end;
$$;

create or replace function public.get_workspace_health(
  p_project_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  release_version text;
begin
  if auth.uid() is null or public.project_role(p_project_id) is null then
    raise exception using errcode = '42501', message = 'Workspace health access denied';
  end if;
  select version into release_version
  from public.workspace_release_policies
  where project_id = p_project_id;
  return jsonb_build_object(
    'status', 'healthy',
    'version', coalesce(release_version, '0.0.0'),
    'timestamp', now(),
    'checks', jsonb_build_array(
      jsonb_build_object('name', 'database', 'status', 'healthy', 'message', 'ok', 'latencyMs', 0),
      jsonb_build_object('name', 'workspace_access', 'status', 'healthy', 'message', 'ok', 'latencyMs', 0),
      jsonb_build_object('name', 'observability_ingest', 'status', 'healthy', 'message', 'ready', 'latencyMs', 0)
    )
  );
end;
$$;

grant execute on function public.record_workspace_observability_event(text, text, text, text, jsonb, timestamptz) to authenticated;
grant execute on function public.submit_workspace_support_bundle(text, text, text, jsonb, timestamptz) to authenticated;
grant execute on function public.get_workspace_support_bundle(text, text) to authenticated;
grant execute on function public.get_workspace_release_policy(text) to authenticated;
grant execute on function public.upsert_workspace_release_policy(text, text, text, text, timestamptz, timestamptz) to authenticated;
grant execute on function public.get_workspace_health(text) to authenticated;

revoke execute on function public.record_workspace_observability_event(text, text, text, text, jsonb, timestamptz) from public, anon;
revoke execute on function public.submit_workspace_support_bundle(text, text, text, jsonb, timestamptz) from public, anon;
revoke execute on function public.get_workspace_support_bundle(text, text) from public, anon;
revoke execute on function public.get_workspace_release_policy(text) from public, anon;
revoke execute on function public.upsert_workspace_release_policy(text, text, text, text, timestamptz, timestamptz) from public, anon;
revoke execute on function public.get_workspace_health(text) from public, anon;
