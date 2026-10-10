create table if not exists public.workspace_ai_provider_health (
  project_id text not null references public.projects(id) on delete cascade,
  provider text not null,
  status text not null check (status in ('healthy', 'degraded', 'unavailable', 'experimental')),
  message text,
  latency_ms integer,
  checked_at timestamptz not null default now(),
  quota_used bigint not null default 0 check (quota_used >= 0),
  quota_limit bigint not null default 0 check (quota_limit >= 0),
  quota_resets_at timestamptz,
  updated_by uuid not null default auth.uid(),
  updated_at timestamptz not null default now(),
  primary key (project_id, provider)
);

create table if not exists public.workspace_ai_job_authorizations (
  project_id text not null references public.projects(id) on delete cascade,
  job_id text not null,
  provider text not null,
  estimated_credits bigint not null check (estimated_credits > 0),
  authorized_by uuid not null default auth.uid(),
  authorized_at timestamptz not null default now(),
  primary key (project_id, job_id)
);

alter table public.workspace_ai_provider_health enable row level security;
alter table public.workspace_ai_job_authorizations enable row level security;
revoke all on public.workspace_ai_provider_health from public, anon, authenticated;
revoke all on public.workspace_ai_job_authorizations from public, anon, authenticated;

create or replace function public.upsert_workspace_ai_provider_health(
  p_project_id text,
  p_provider text,
  p_status text,
  p_message text default null,
  p_latency_ms integer default null,
  p_quota_used bigint default 0,
  p_quota_limit bigint default 0,
  p_quota_resets_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  health public.workspace_ai_provider_health;
begin
  if auth.uid() is null or not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can update AI provider health';
  end if;
  if length(trim(coalesce(p_provider, ''))) < 2
      or p_status not in ('healthy', 'degraded', 'unavailable', 'experimental')
      or coalesce(p_latency_ms, 0) < 0
      or coalesce(p_quota_used, 0) < 0
      or coalesce(p_quota_limit, 0) < 0
      or coalesce(p_quota_used, 0) > coalesce(p_quota_limit, 0) then
    raise exception using errcode = '22023', message = 'Invalid AI provider health payload';
  end if;
  insert into public.workspace_ai_provider_health (
    project_id, provider, status, message, latency_ms, checked_at,
    quota_used, quota_limit, quota_resets_at, updated_by, updated_at
  ) values (
    p_project_id, trim(p_provider), p_status, p_message, p_latency_ms, now(),
    coalesce(p_quota_used, 0), coalesce(p_quota_limit, 0), p_quota_resets_at,
    auth.uid(), now()
  ) on conflict (project_id, provider) do update set
    status = excluded.status,
    message = excluded.message,
    latency_ms = excluded.latency_ms,
    checked_at = excluded.checked_at,
    quota_used = excluded.quota_used,
    quota_limit = excluded.quota_limit,
    quota_resets_at = excluded.quota_resets_at,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at
  returning * into health;
  return jsonb_build_object(
    'projectId', health.project_id,
    'provider', health.provider,
    'status', health.status,
    'message', health.message,
    'latencyMs', health.latency_ms,
    'checkedAt', health.checked_at,
    'quotaUsed', health.quota_used,
    'quotaLimit', health.quota_limit,
    'quotaResetsAt', health.quota_resets_at
  );
end;
$$;

create or replace function public.get_workspace_ai_provider_health(
  p_project_id text,
  p_provider text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  health public.workspace_ai_provider_health;
begin
  if auth.uid() is null or public.project_role(p_project_id) is null then
    raise exception using errcode = '42501', message = 'AI provider health access denied';
  end if;
  select * into health
  from public.workspace_ai_provider_health
  where project_id = p_project_id and provider = trim(p_provider);
  if health.project_id is null then
    return jsonb_build_object(
      'projectId', p_project_id,
      'provider', trim(p_provider),
      'status', 'healthy',
      'quotaUsed', 0,
      'quotaLimit', (public.workspace_policy_for(p_project_id) -> 'quota' ->> 'aiCredits')::bigint,
      'checkedAt', now()
    );
  end if;
  return jsonb_build_object(
    'projectId', health.project_id,
    'provider', health.provider,
    'status', health.status,
    'message', health.message,
    'latencyMs', health.latency_ms,
    'checkedAt', health.checked_at,
    'quotaUsed', health.quota_used,
    'quotaLimit', health.quota_limit,
    'quotaResetsAt', health.quota_resets_at
  );
end;
$$;

create or replace function public.authorize_ai_job(
  p_project_id text,
  p_job_id text,
  p_provider text,
  p_estimated_credits bigint default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  policy jsonb;
  health public.workspace_ai_provider_health;
  job_auth public.workspace_ai_job_authorizations;
  provider_status text := 'healthy';
  provider_used bigint := 0;
  provider_limit bigint := 0;
  usage_result jsonb;
begin
  if auth.uid() is null or public.project_role(p_project_id) not in ('owner', 'editor') then
    raise exception using errcode = '42501', message = 'AI job authorization denied';
  end if;
  if length(trim(coalesce(p_job_id, ''))) < 8
      or length(trim(coalesce(p_provider, ''))) < 2
      or p_estimated_credits <= 0 then
    raise exception using errcode = '22023', message = 'Invalid AI job authorization';
  end if;
  select * into job_auth
  from public.workspace_ai_job_authorizations
  where project_id = p_project_id and job_id = trim(p_job_id);
  if job_auth.job_id is not null then
    return jsonb_build_object(
      'authorized', true,
      'duplicate', true,
      'provider', job_auth.provider,
      'estimatedCredits', job_auth.estimated_credits,
      'authorizedAt', job_auth.authorized_at
    );
  end if;
  policy := public.workspace_policy_for(p_project_id);
  if coalesce((policy ->> 'allowAiGeneration')::boolean, true) = false then
    raise exception using errcode = '42501', message = 'Workspace AI generation is disabled';
  end if;
  select * into health
  from public.workspace_ai_provider_health
  where project_id = p_project_id and provider = trim(p_provider);
  if health.project_id is not null then
    provider_status := health.status;
    provider_used := health.quota_used;
    provider_limit := health.quota_limit;
  else
    provider_limit := (policy -> 'quota' ->> 'aiCredits')::bigint;
  end if;
  if provider_status not in ('healthy', 'experimental') then
    raise exception using errcode = '50300', message = 'AI provider is not healthy';
  end if;
  if provider_used + p_estimated_credits > provider_limit then
    raise exception using errcode = '54000', message = 'AI provider quota exceeded';
  end if;
  usage_result := public.record_workspace_usage(
    p_project_id,
    'ai_credits',
    p_estimated_credits,
    trim(p_job_id),
    jsonb_build_object('provider', trim(p_provider), 'source', 'ai_job')
  );
  insert into public.workspace_ai_job_authorizations (
    project_id, job_id, provider, estimated_credits
  ) values (
    p_project_id, trim(p_job_id), trim(p_provider), p_estimated_credits
  ) returning * into job_auth;
  insert into public.workspace_audit_events (project_id, action, metadata)
  values (
    p_project_id,
    'ai.job.authorized',
    jsonb_build_object('jobId', job_auth.job_id, 'provider', job_auth.provider, 'usage', usage_result)
  );
  return jsonb_build_object(
    'authorized', true,
    'duplicate', false,
    'provider', job_auth.provider,
    'estimatedCredits', job_auth.estimated_credits,
    'authorizedAt', job_auth.authorized_at,
    'usage', usage_result -> 'usage'
  );
end;
$$;

grant execute on function public.upsert_workspace_ai_provider_health(text, text, text, text, integer, bigint, bigint, timestamptz) to authenticated;
grant execute on function public.get_workspace_ai_provider_health(text, text) to authenticated;
grant execute on function public.authorize_ai_job(text, text, text, bigint) to authenticated;
revoke execute on function public.upsert_workspace_ai_provider_health(text, text, text, text, integer, bigint, bigint, timestamptz) from public, anon;
revoke execute on function public.get_workspace_ai_provider_health(text, text) from public, anon;
revoke execute on function public.authorize_ai_job(text, text, text, bigint) from public, anon;
