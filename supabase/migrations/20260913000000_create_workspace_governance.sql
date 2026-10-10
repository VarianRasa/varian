alter table public.projects
  add column if not exists deletion_requested_at timestamptz,
  add column if not exists deletion_requested_by uuid,
  add column if not exists archived_at timestamptz;

create table if not exists public.workspace_policies (
  project_id text primary key references public.projects(id) on delete cascade,
  policy jsonb not null,
  updated_by uuid not null default auth.uid(),
  updated_at timestamptz not null default now()
);

create table if not exists public.workspace_usage_ledger (
  id bigint generated always as identity primary key,
  project_id text not null references public.projects(id) on delete cascade,
  category text not null check (category in ('storage', 'assets', 'ai_credits', 'projects')),
  delta bigint not null check (delta <> 0),
  operation_id text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  unique (project_id, category, operation_id)
);

create table if not exists public.workspace_audit_events (
  id uuid primary key default gen_random_uuid(),
  project_id text not null references public.projects(id) on delete cascade,
  actor_id uuid not null default auth.uid(),
  action text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.workspace_data_export_requests (
  id uuid primary key default gen_random_uuid(),
  project_id text not null references public.projects(id) on delete cascade,
  requested_by uuid not null default auth.uid(),
  operation_id text not null,
  status text not null default 'pending' check (status in ('pending', 'processing', 'ready', 'failed', 'expired')),
  artifact_uri text,
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (project_id, operation_id)
);

create table if not exists public.workspace_billing_events (
  id uuid primary key default gen_random_uuid(),
  project_id text not null references public.projects(id) on delete cascade,
  event_type text not null,
  idempotency_key text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (status in ('queued', 'sent', 'failed')),
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  unique (project_id, idempotency_key)
);

create index if not exists workspace_usage_ledger_project_category_idx
  on public.workspace_usage_ledger (project_id, category, created_at);
create index if not exists workspace_audit_events_project_created_idx
  on public.workspace_audit_events (project_id, created_at desc);
create index if not exists workspace_export_requests_project_status_idx
  on public.workspace_data_export_requests (project_id, status, requested_at);

alter table public.workspace_policies enable row level security;
alter table public.workspace_usage_ledger enable row level security;
alter table public.workspace_audit_events enable row level security;
alter table public.workspace_data_export_requests enable row level security;
alter table public.workspace_billing_events enable row level security;

revoke all on public.workspace_policies from public, anon, authenticated;
revoke all on public.workspace_usage_ledger from public, anon, authenticated;
revoke all on public.workspace_audit_events from public, anon, authenticated;
revoke all on public.workspace_data_export_requests from public, anon, authenticated;
revoke all on public.workspace_billing_events from public, anon, authenticated;

create or replace function public.default_workspace_policy()
returns jsonb
language sql
immutable
as $$
  select '{
    "quota": {
      "storageBytes": 67108864,
      "assetBytes": 536870912,
      "aiCredits": 1000,
      "projectCount": 1
    },
    "retention": {
      "auditLogRetentionDays": 365,
      "trashRetentionDays": 30,
      "allowUserExport": true
    },
    "allowPublicSharing": true,
    "allowEmbeds": true,
    "allowAiGeneration": true,
    "requireAuditLog": true,
    "allowDataExport": true,
    "billingPlan": "free"
  }'::jsonb;
$$;

create or replace function public.workspace_policy_for(text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select policy from public.workspace_policies where project_id = $1),
    public.default_workspace_policy()
  );
$$;

create or replace function public.workspace_usage_for(text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'storageBytes', coalesce(sum(delta) filter (where category = 'storage'), 0),
    'assetBytes', coalesce(sum(delta) filter (where category = 'assets'), 0),
    'aiCredits', coalesce(sum(delta) filter (where category = 'ai_credits'), 0),
    'projectCount', coalesce(sum(delta) filter (where category = 'projects'), 0)
  )
  from public.workspace_usage_ledger
  where project_id = $1;
$$;

create or replace function public.get_workspace_governance(p_project_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  policy jsonb;
  usage jsonb;
  project_row public.projects;
begin
  if auth.uid() is null or public.project_role(p_project_id) is null then
    raise exception using errcode = '42501', message = 'Workspace access denied';
  end if;
  select * into project_row from public.projects where id = p_project_id;
  if project_row.id is null then
    raise exception using errcode = '22023', message = 'Project not found';
  end if;
  policy := public.workspace_policy_for(p_project_id);
  usage := public.workspace_usage_for(p_project_id);
  return jsonb_build_object(
    'projectId', p_project_id,
    'policy', policy,
    'usage', usage,
    'deletionRequestedAt', project_row.deletion_requested_at,
    'archivedAt', project_row.archived_at
  );
end;
$$;

create or replace function public.upsert_workspace_policy(
  p_project_id text,
  p_policy jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized jsonb := coalesce(p_policy, public.default_workspace_policy());
  quota jsonb := coalesce(normalized -> 'quota', '{}'::jsonb);
  retention jsonb := coalesce(normalized -> 'retention', '{}'::jsonb);
  result jsonb;
begin
  if auth.uid() is null or not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can update workspace policy';
  end if;
  if jsonb_typeof(normalized) <> 'object'
      or (quota ->> 'storageBytes')::bigint < 0
      or (quota ->> 'assetBytes')::bigint < 0
      or (quota ->> 'aiCredits')::bigint < 0
      or (quota ->> 'projectCount')::bigint < 0
      or (retention ->> 'auditLogRetentionDays')::integer < 0
      or (retention ->> 'trashRetentionDays')::integer < 0 then
    raise exception using errcode = '22023', message = 'Workspace policy contains invalid limits';
  end if;
  insert into public.workspace_policies (project_id, policy, updated_by, updated_at)
  values (p_project_id, normalized, auth.uid(), now())
  on conflict (project_id) do update set
    policy = excluded.policy,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at
  returning policy into result;
  insert into public.workspace_audit_events (project_id, action, metadata)
  values (p_project_id, 'workspace.policy.updated', jsonb_build_object('policy', result));
  return result;
end;
$$;

create or replace function public.record_workspace_usage(
  p_project_id text,
  p_category text,
  p_delta bigint,
  p_operation_id text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_row public.workspace_usage_ledger;
  current_usage jsonb;
  policy jsonb;
  current_value bigint;
  limit_value bigint;
  next_value bigint;
begin
  if auth.uid() is null or public.project_role(p_project_id) not in ('owner', 'editor') then
    raise exception using errcode = '42501', message = 'Workspace usage access denied';
  end if;
  if p_category not in ('storage', 'assets', 'ai_credits', 'projects')
      or p_delta = 0
      or length(trim(coalesce(p_operation_id, ''))) < 8 then
    raise exception using errcode = '22023', message = 'Invalid workspace usage entry';
  end if;
  select * into existing_row
  from public.workspace_usage_ledger
  where project_id = p_project_id
    and category = p_category
    and operation_id = trim(p_operation_id);
  if existing_row.id is not null then
    return jsonb_build_object(
      'accepted', true,
      'duplicate', true,
      'category', existing_row.category,
      'delta', existing_row.delta,
      'operationId', existing_row.operation_id,
      'usage', public.workspace_usage_for(p_project_id)
    );
  end if;
  policy := public.workspace_policy_for(p_project_id);
  current_usage := public.workspace_usage_for(p_project_id);
  current_value := case p_category
    when 'storage' then (current_usage ->> 'storageBytes')::bigint
    when 'assets' then (current_usage ->> 'assetBytes')::bigint
    when 'ai_credits' then (current_usage ->> 'aiCredits')::bigint
    else (current_usage ->> 'projectCount')::bigint
  end;
  limit_value := case p_category
    when 'storage' then (policy -> 'quota' ->> 'storageBytes')::bigint
    when 'assets' then (policy -> 'quota' ->> 'assetBytes')::bigint
    when 'ai_credits' then (policy -> 'quota' ->> 'aiCredits')::bigint
    else (policy -> 'quota' ->> 'projectCount')::bigint
  end;
  next_value := current_value + p_delta;
  if next_value < 0 or next_value > limit_value then
    raise exception using errcode = '54000', message = 'Workspace quota exceeded';
  end if;
  insert into public.workspace_usage_ledger (
    project_id, category, delta, operation_id, metadata
  ) values (
    p_project_id, p_category, p_delta, trim(p_operation_id), coalesce(p_metadata, '{}'::jsonb)
  );
  insert into public.workspace_audit_events (project_id, action, metadata)
  values (
    p_project_id,
    'workspace.usage.recorded',
    jsonb_build_object('category', p_category, 'delta', p_delta, 'operationId', trim(p_operation_id))
  );
  return jsonb_build_object(
    'accepted', true,
    'duplicate', false,
    'category', p_category,
    'delta', p_delta,
    'operationId', trim(p_operation_id),
    'usage', public.workspace_usage_for(p_project_id)
  );
end;
$$;

create or replace function public.request_workspace_data_export(
  p_project_id text,
  p_operation_id text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  policy jsonb;
  request_row public.workspace_data_export_requests;
begin
  if auth.uid() is null or public.project_role(p_project_id) is null then
    raise exception using errcode = '42501', message = 'Workspace export access denied';
  end if;
  if length(trim(coalesce(p_operation_id, ''))) < 8 then
    raise exception using errcode = '22023', message = 'Invalid export operation ID';
  end if;
  policy := public.workspace_policy_for(p_project_id);
  if coalesce((policy ->> 'allowDataExport')::boolean, true) = false
      or coalesce((policy -> 'retention' ->> 'allowUserExport')::boolean, true) = false then
    raise exception using errcode = '42501', message = 'Workspace data export is disabled';
  end if;
  insert into public.workspace_data_export_requests (project_id, operation_id)
  values (p_project_id, trim(p_operation_id))
  on conflict (project_id, operation_id) do update set operation_id = excluded.operation_id
  returning * into request_row;
  insert into public.workspace_audit_events (project_id, action, metadata)
  values (p_project_id, 'workspace.export.requested', jsonb_build_object('requestId', request_row.id));
  return jsonb_build_object(
    'requestId', request_row.id,
    'projectId', request_row.project_id,
    'operationId', request_row.operation_id,
    'status', request_row.status,
    'requestedAt', request_row.requested_at
  );
end;
$$;

create or replace function public.request_project_deletion(p_project_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  project_row public.projects;
begin
  if auth.uid() is null or not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can request deletion';
  end if;
  update public.projects
  set deletion_requested_at = coalesce(deletion_requested_at, now()),
      deletion_requested_by = auth.uid(),
      updated_at = now()
  where id = p_project_id
  returning * into project_row;
  insert into public.workspace_audit_events (project_id, action)
  values (p_project_id, 'workspace.project.deletion_requested');
  return jsonb_build_object(
    'projectId', project_row.id,
    'deletionRequestedAt', project_row.deletion_requested_at
  );
end;
$$;

create or replace function public.cancel_project_deletion(p_project_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can cancel deletion';
  end if;
  update public.projects
  set deletion_requested_at = null,
      deletion_requested_by = null,
      updated_at = now()
  where id = p_project_id;
  insert into public.workspace_audit_events (project_id, action)
  values (p_project_id, 'workspace.project.deletion_cancelled');
end;
$$;

create or replace function public.purge_workspace_retention(p_project_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  policy jsonb := public.workspace_policy_for(p_project_id);
  audit_cutoff timestamptz := now() - make_interval(days => (policy -> 'retention' ->> 'auditLogRetentionDays')::integer);
  export_cutoff timestamptz := now() - make_interval(days => (policy -> 'retention' ->> 'trashRetentionDays')::integer);
  audit_deleted integer := 0;
  export_deleted integer := 0;
begin
  if auth.uid() is null or not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can purge retention data';
  end if;
  delete from public.workspace_audit_events
  where project_id = p_project_id and created_at < audit_cutoff;
  get diagnostics audit_deleted = row_count;
  delete from public.workspace_data_export_requests
  where project_id = p_project_id
    and status in ('ready', 'failed', 'expired')
    and coalesce(completed_at, requested_at) < export_cutoff;
  get diagnostics export_deleted = row_count;
  return jsonb_build_object('auditDeleted', audit_deleted, 'exportDeleted', export_deleted);
end;
$$;

create or replace function public.enqueue_workspace_billing_event(
  p_project_id text,
  p_event_type text,
  p_idempotency_key text,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  event_row public.workspace_billing_events;
begin
  if auth.uid() is null or not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can enqueue billing events';
  end if;
  if length(trim(coalesce(p_event_type, ''))) < 2
      or length(trim(coalesce(p_idempotency_key, ''))) < 8 then
    raise exception using errcode = '22023', message = 'Invalid billing event';
  end if;
  insert into public.workspace_billing_events (
    project_id, event_type, idempotency_key, payload
  ) values (
    p_project_id, trim(p_event_type), trim(p_idempotency_key), coalesce(p_payload, '{}'::jsonb)
  ) on conflict (project_id, idempotency_key) do update set
    payload = public.workspace_billing_events.payload
  returning * into event_row;
  insert into public.workspace_audit_events (project_id, action, metadata)
  values (p_project_id, 'workspace.billing.event_queued', jsonb_build_object('eventId', event_row.id, 'eventType', event_row.event_type));
  return jsonb_build_object(
    'eventId', event_row.id,
    'projectId', event_row.project_id,
    'eventType', event_row.event_type,
    'idempotencyKey', event_row.idempotency_key,
    'status', event_row.status,
    'createdAt', event_row.created_at
  );
end;
$$;

create or replace function public.list_workspace_audit_events(
  p_project_id text,
  p_limit integer default 100
)
returns setof public.workspace_audit_events
language sql
security definer
set search_path = public
as $$
  select *
  from public.workspace_audit_events
  where public.project_role(p_project_id) is not null
    and project_id = p_project_id
  order by created_at desc
  limit least(greatest(coalesce(p_limit, 100), 1), 500);
$$;

grant execute on function public.default_workspace_policy() to authenticated;
grant execute on function public.get_workspace_governance(text) to authenticated;
grant execute on function public.upsert_workspace_policy(text, jsonb) to authenticated;
grant execute on function public.record_workspace_usage(text, text, bigint, text, jsonb) to authenticated;
grant execute on function public.request_workspace_data_export(text, text) to authenticated;
grant execute on function public.request_project_deletion(text) to authenticated;
grant execute on function public.cancel_project_deletion(text) to authenticated;
grant execute on function public.purge_workspace_retention(text) to authenticated;
grant execute on function public.enqueue_workspace_billing_event(text, text, text, jsonb) to authenticated;
grant execute on function public.list_workspace_audit_events(text, integer) to authenticated;

revoke execute on function public.default_workspace_policy() from public, anon;
revoke execute on function public.get_workspace_governance(text) from public, anon;
revoke execute on function public.upsert_workspace_policy(text, jsonb) from public, anon;
revoke execute on function public.record_workspace_usage(text, text, bigint, text, jsonb) from public, anon;
revoke execute on function public.request_workspace_data_export(text, text) from public, anon;
revoke execute on function public.request_project_deletion(text) from public, anon;
revoke execute on function public.cancel_project_deletion(text) from public, anon;
revoke execute on function public.purge_workspace_retention(text) from public, anon;
revoke execute on function public.enqueue_workspace_billing_event(text, text, text, jsonb) from public, anon;
revoke execute on function public.list_workspace_audit_events(text, integer) from public, anon;
