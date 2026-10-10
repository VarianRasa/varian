create or replace function public.upsert_workspace_ai_governance(
  p_project_id text,
  p_ai_policy jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_policy jsonb;
  normalized_policy jsonb;
  normalized_ai_policy jsonb := coalesce(p_ai_policy, '{}'::jsonb);
  providers jsonb;
  provider_name text;
  provider_payload jsonb;
  provider_policies jsonb;
  quota_value numeric;
  max_credits integer;
  rate_limit_count integer;
  rate_limit_window integer;
  threshold numeric;
begin
  if auth.uid() is null or not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501',
      message = 'Only the project owner can update AI governance policy';
  end if;
  if jsonb_typeof(normalized_ai_policy) <> 'object' then
    raise exception using errcode = '22023',
      message = 'AI governance policy must be an object';
  end if;

  current_policy := public.workspace_policy_for(p_project_id);
  quota_value := coalesce(
    (normalized_ai_policy ->> 'quotaCredits')::numeric,
    (current_policy -> 'quota' ->> 'aiCredits')::numeric,
    1000
  );
  max_credits := coalesce(
    (normalized_ai_policy ->> 'maxCreditsPerJob')::integer,
    100
  );
  rate_limit_count := coalesce(
    (normalized_ai_policy ->> 'rateLimitCount')::integer,
    20
  );
  rate_limit_window := coalesce(
    (normalized_ai_policy ->> 'rateLimitWindowSeconds')::integer,
    60
  );
  threshold := coalesce(
    (normalized_ai_policy ->> 'budgetAlertThreshold')::numeric,
    0.8
  );
  if quota_value < 0 or quota_value <> trunc(quota_value)
      or max_credits <= 0
      or rate_limit_count <= 0
      or rate_limit_window <= 0
      or threshold < 0
      or threshold > 1 then
    raise exception using errcode = '22023',
      message = 'Invalid AI governance policy limits';
  end if;

  providers := coalesce(normalized_ai_policy -> 'providers', '{}'::jsonb);
  if jsonb_typeof(providers) <> 'object' then
    raise exception using errcode = '22023',
      message = 'AI provider policies must be an object';
  end if;

  normalized_policy := jsonb_set(
    jsonb_set(
      jsonb_set(
        current_policy,
        '{allowAiGeneration}',
        to_jsonb(coalesce((normalized_ai_policy ->> 'allowGeneration')::boolean, true)),
        true
      ),
      '{quota,aiCredits}',
      to_jsonb(quota_value::bigint),
      true
    ),
    '{aiGovernance}',
    normalized_ai_policy,
    true
  );

  insert into public.workspace_policies (project_id, policy, updated_by, updated_at)
  values (p_project_id, normalized_policy, auth.uid(), now())
  on conflict (project_id) do update set
    policy = excluded.policy,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at;

  delete from public.workspace_ai_provider_policies
  where project_id = p_project_id
    and not exists (
      select 1
      from jsonb_object_keys(providers) as requested(provider)
      where requested.provider = workspace_ai_provider_policies.provider
    );

  for provider_name, provider_payload in
    select key, value from jsonb_each(providers)
  loop
    if length(trim(provider_name)) < 2
        or jsonb_typeof(provider_payload) <> 'object' then
      raise exception using errcode = '22023',
        message = 'Invalid AI provider policy payload';
    end if;
    provider_payload := provider_payload || jsonb_build_object('provider', provider_name);
    perform public.upsert_workspace_ai_provider_policy(
      p_project_id,
      provider_payload
    );
  end loop;

  select jsonb_object_agg(
    provider_policy.provider,
    jsonb_build_object(
      'provider', provider_policy.provider,
      'enabled', provider_policy.enabled,
      'allowedModels', provider_policy.allowed_models,
      'allowExperimental', provider_policy.allow_experimental,
      'maxCreditsPerJob', provider_policy.max_credits_per_job,
      'rateLimitCount', provider_policy.rate_limit_count,
      'rateLimitWindowSeconds', provider_policy.rate_limit_window_seconds,
      'updatedAt', provider_policy.updated_at
    )
  )
  into provider_policies
  from public.workspace_ai_provider_policies as provider_policy
  where provider_policy.project_id = p_project_id;

  insert into public.workspace_audit_events (project_id, action, metadata)
  values (
    p_project_id,
    'workspace.ai_governance.updated',
    jsonb_build_object(
      'allowGeneration', normalized_ai_policy -> 'allowGeneration',
      'providerCount', (select count(*) from jsonb_object_keys(providers)),
      'quotaCredits', quota_value::bigint
    )
  );

  return jsonb_build_object(
    'projectId', p_project_id,
    'policy', normalized_policy,
    'aiGovernance', normalized_ai_policy,
    'providerPolicies', coalesce(provider_policies, '{}'::jsonb),
    'usage', public.workspace_usage_for(p_project_id)
  );
end;
$$;

grant execute on function public.upsert_workspace_ai_governance(text, jsonb)
to authenticated;

revoke execute on function public.upsert_workspace_ai_governance(text, jsonb)
from public, anon;
