create table if not exists public.workspace_ai_provider_policies (
  project_id text not null references public.projects(id) on delete cascade,
  provider text not null,
  enabled boolean not null default true,
  allowed_models jsonb not null default '[]'::jsonb,
  allow_experimental boolean not null default false,
  max_credits_per_job bigint,
  rate_limit_count integer,
  rate_limit_window_seconds integer,
  updated_by uuid not null default auth.uid(),
  updated_at timestamptz not null default now(),
  primary key (project_id, provider),
  check (jsonb_typeof(allowed_models) = 'array'),
  check (max_credits_per_job is null or max_credits_per_job > 0),
  check (rate_limit_count is null or rate_limit_count > 0),
  check (rate_limit_window_seconds is null or rate_limit_window_seconds > 0)
);

alter table public.workspace_ai_provider_policies enable row level security;
revoke all on public.workspace_ai_provider_policies from public, anon, authenticated;

alter table public.workspace_ai_job_authorizations
  add column if not exists model text,
  add column if not exists used_fallback boolean not null default false,
  add column if not exists budget_alert boolean not null default false,
  add column if not exists policy_version integer not null default 1;

create index if not exists workspace_ai_job_authorizations_provider_time_idx
  on public.workspace_ai_job_authorizations (project_id, provider, authorized_at desc);

create or replace function public.upsert_workspace_ai_provider_policy(
  p_project_id text,
  p_policy jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  policy_row public.workspace_ai_provider_policies;
  provider_name text := trim(coalesce(p_policy ->> 'provider', ''));
  allowed_models jsonb := coalesce(p_policy -> 'allowedModels', '[]'::jsonb);
begin
  if auth.uid() is null or not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can update AI provider policy';
  end if;
  if length(provider_name) < 2
      or jsonb_typeof(allowed_models) <> 'array'
      or coalesce((p_policy ->> 'maxCreditsPerJob')::bigint, 1) <= 0
      or coalesce((p_policy ->> 'rateLimitCount')::integer, 1) <= 0
      or coalesce((p_policy ->> 'rateLimitWindowSeconds')::integer, 1) <= 0 then
    raise exception using errcode = '22023', message = 'Invalid AI provider policy payload';
  end if;
  insert into public.workspace_ai_provider_policies (
    project_id, provider, enabled, allowed_models, allow_experimental,
    max_credits_per_job, rate_limit_count, rate_limit_window_seconds,
    updated_by, updated_at
  ) values (
    p_project_id,
    provider_name,
    coalesce((p_policy ->> 'enabled')::boolean, true),
    allowed_models,
    coalesce((p_policy ->> 'allowExperimental')::boolean, false),
    (p_policy ->> 'maxCreditsPerJob')::bigint,
    (p_policy ->> 'rateLimitCount')::integer,
    (p_policy ->> 'rateLimitWindowSeconds')::integer,
    auth.uid(),
    now()
  ) on conflict (project_id, provider) do update set
    enabled = excluded.enabled,
    allowed_models = excluded.allowed_models,
    allow_experimental = excluded.allow_experimental,
    max_credits_per_job = excluded.max_credits_per_job,
    rate_limit_count = excluded.rate_limit_count,
    rate_limit_window_seconds = excluded.rate_limit_window_seconds,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at
  returning * into policy_row;
  return jsonb_build_object(
    'projectId', policy_row.project_id,
    'provider', policy_row.provider,
    'enabled', policy_row.enabled,
    'allowedModels', policy_row.allowed_models,
    'allowExperimental', policy_row.allow_experimental,
    'maxCreditsPerJob', policy_row.max_credits_per_job,
    'rateLimitCount', policy_row.rate_limit_count,
    'rateLimitWindowSeconds', policy_row.rate_limit_window_seconds,
    'updatedAt', policy_row.updated_at
  );
end;
$$;

create or replace function public.get_workspace_ai_governance(p_project_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or public.project_role(p_project_id) is null then
    raise exception using errcode = '42501', message = 'AI governance access denied';
  end if;
  return jsonb_build_object(
    'projectId', p_project_id,
    'policy', public.workspace_policy_for(p_project_id),
    'providerPolicies', coalesce((
      select jsonb_object_agg(
        provider,
        jsonb_build_object(
          'provider', provider,
          'enabled', enabled,
          'allowedModels', allowed_models,
          'allowExperimental', allow_experimental,
          'maxCreditsPerJob', max_credits_per_job,
          'rateLimitCount', rate_limit_count,
          'rateLimitWindowSeconds', rate_limit_window_seconds,
          'updatedAt', updated_at
        )
      )
      from public.workspace_ai_provider_policies
      where project_id = p_project_id
    ), '{}'::jsonb),
    'usage', public.workspace_usage_for(p_project_id)
  );
end;
$$;

create or replace function public.authorize_ai_job_v2(
  p_project_id text,
  p_job_id text,
  p_provider text,
  p_model text default null,
  p_estimated_credits bigint default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  workspace_policy jsonb;
  ai_policy jsonb;
  provider_name text;
  model_name text := nullif(trim(coalesce(p_model, '')), '');
  candidate jsonb;
  candidate_provider text;
  provider_policy public.workspace_ai_provider_policies;
  health public.workspace_ai_provider_health;
  job_auth public.workspace_ai_job_authorizations;
  selected_provider text;
  selected_fallback boolean := false;
  provider_status text;
  request_count integer;
  request_limit integer;
  request_window integer;
  max_job_credits bigint;
  usage_result jsonb;
  current_usage jsonb;
  ai_limit bigint;
  next_ai_credits bigint;
  budget_threshold numeric;
  budget_alert boolean := false;
  candidate_index integer := 0;
begin
  if auth.uid() is null or public.project_role(p_project_id) not in ('owner', 'editor') then
    raise exception using errcode = '42501', message = 'AI job authorization denied';
  end if;
  if length(trim(coalesce(p_job_id, ''))) < 8
      or length(trim(coalesce(p_provider, ''))) < 2
      or p_estimated_credits <= 0 then
    raise exception using errcode = '22023', message = 'Invalid AI job authorization';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(trim(p_project_id) || ':' || trim(p_job_id), 0)
  );
  select * into job_auth
  from public.workspace_ai_job_authorizations
  where project_id = p_project_id and job_id = trim(p_job_id);
  if job_auth.job_id is not null then
    return jsonb_build_object(
      'authorized', true,
      'duplicate', true,
      'provider', job_auth.provider,
      'model', job_auth.model,
      'estimatedCredits', job_auth.estimated_credits,
      'usedFallback', job_auth.used_fallback,
      'budgetAlert', job_auth.budget_alert,
      'authorizedAt', job_auth.authorized_at
    );
  end if;

  workspace_policy := public.workspace_policy_for(p_project_id);
  if coalesce((workspace_policy ->> 'allowAiGeneration')::boolean, true) = false then
    raise exception using errcode = '42501', message = 'Workspace AI generation is disabled';
  end if;
  ai_policy := coalesce(workspace_policy -> 'aiGovernance', '{}'::jsonb);
  ai_limit := coalesce((workspace_policy -> 'quota' ->> 'aiCredits')::bigint, 0);
  max_job_credits := coalesce((ai_policy ->> 'maxCreditsPerJob')::bigint, ai_limit);
  if p_estimated_credits > max_job_credits then
    raise exception using errcode = '54000', message = 'AI job credit limit exceeded';
  end if;

  for candidate in
    select value
    from jsonb_array_elements(
      jsonb_build_array(trim(p_provider)) ||
      case
        when jsonb_typeof(ai_policy -> 'fallbackProviders') = 'array'
          then ai_policy -> 'fallbackProviders'
        else '[]'::jsonb
      end
    )
  loop
    candidate_provider := trim(candidate #>> '{}');
    if candidate_provider is null or length(candidate_provider) < 2 then
      continue;
    end if;
    candidate_index := candidate_index + 1;
    select * into provider_policy
    from public.workspace_ai_provider_policies
    where project_id = p_project_id and provider = candidate_provider;
    if provider_policy.provider is null then
      if coalesce((ai_policy ->> 'allowUnknownProviders')::boolean, true) = false then
        continue;
      end if;
      request_limit := coalesce((ai_policy ->> 'rateLimitCount')::integer, 20);
      request_window := coalesce((ai_policy ->> 'rateLimitWindowSeconds')::integer, 60);
      max_job_credits := coalesce((ai_policy ->> 'maxCreditsPerJob')::bigint, ai_limit);
    else
      if not provider_policy.enabled then continue; end if;
      if jsonb_array_length(provider_policy.allowed_models) > 0
          and (model_name is null or not (provider_policy.allowed_models ? model_name)) then
        continue;
      end if;
      request_limit := coalesce(provider_policy.rate_limit_count, 20);
      request_window := coalesce(provider_policy.rate_limit_window_seconds, 60);
      max_job_credits := coalesce(provider_policy.max_credits_per_job, ai_limit);
    end if;
    if p_estimated_credits > max_job_credits then continue; end if;

    select * into health
    from public.workspace_ai_provider_health
    where project_id = p_project_id and provider = candidate_provider;
    provider_status := coalesce(health.status, 'healthy');
    if provider_status not in ('healthy', 'experimental') then continue; end if;
    if provider_status = 'experimental'
        and coalesce(provider_policy.allow_experimental, false) = false then
      continue;
    end if;
    if health.project_id is not null and health.quota_limit > 0
        and health.quota_used + p_estimated_credits > health.quota_limit then
      continue;
    end if;

    select count(*) into request_count
    from public.workspace_ai_job_authorizations
    where project_id = p_project_id
      and provider = candidate_provider
      and authorized_at >= now() - (request_window || ' seconds')::interval;
    if request_count >= request_limit then continue; end if;

    selected_provider := candidate_provider;
    selected_fallback := candidate_index > 1;
    exit;
  end loop;

  if selected_provider is null then
    raise exception using errcode = '50300', message = 'No allowed and healthy AI provider is available';
  end if;

  current_usage := public.workspace_usage_for(p_project_id);
  next_ai_credits := coalesce((current_usage ->> 'aiCredits')::bigint, 0) + p_estimated_credits;
  if next_ai_credits > ai_limit then
    raise exception using errcode = '54000', message = 'Workspace AI quota exceeded';
  end if;
  budget_threshold := greatest(0, least(1, coalesce((ai_policy ->> 'budgetAlertThreshold')::numeric, 0.8)));
  budget_alert := ai_limit > 0 and next_ai_credits::numeric / ai_limit >= budget_threshold;
  usage_result := public.record_workspace_usage(
    p_project_id,
    'ai_credits',
    p_estimated_credits,
    trim(p_job_id),
    jsonb_build_object(
      'provider', selected_provider,
      'model', model_name,
      'source', 'ai_job_v2',
      'usedFallback', selected_fallback
    )
  );
  insert into public.workspace_ai_job_authorizations (
    project_id, job_id, provider, model, estimated_credits,
    used_fallback, budget_alert, policy_version
  ) values (
    p_project_id, trim(p_job_id), selected_provider, model_name, p_estimated_credits,
    selected_fallback, budget_alert, 2
  ) returning * into job_auth;
  insert into public.workspace_audit_events (project_id, action, metadata)
  values (
    p_project_id,
    'ai.job.authorized',
    jsonb_build_object(
      'jobId', job_auth.job_id,
      'provider', job_auth.provider,
      'model', job_auth.model,
      'usedFallback', job_auth.used_fallback,
      'budgetAlert', job_auth.budget_alert,
      'usage', usage_result
    )
  );
  return jsonb_build_object(
    'authorized', true,
    'duplicate', false,
    'provider', job_auth.provider,
    'model', job_auth.model,
    'estimatedCredits', job_auth.estimated_credits,
    'usedFallback', job_auth.used_fallback,
    'budgetAlert', job_auth.budget_alert,
    'authorizedAt', job_auth.authorized_at,
    'usage', usage_result -> 'usage'
  );
end;
$$;

grant execute on function public.upsert_workspace_ai_provider_policy(text, jsonb) to authenticated;
grant execute on function public.get_workspace_ai_governance(text) to authenticated;
grant execute on function public.authorize_ai_job_v2(text, text, text, text, bigint) to authenticated;
revoke execute on function public.upsert_workspace_ai_provider_policy(text, jsonb) from public, anon;
revoke execute on function public.get_workspace_ai_governance(text) from public, anon;
revoke execute on function public.authorize_ai_job_v2(text, text, text, text, bigint) from public, anon;
