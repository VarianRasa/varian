create table if not exists public.workspace_entitlements (
  project_id text primary key references public.projects(id) on delete cascade,
  provider text not null default 'manual',
  plan_id text not null default 'free',
  status text not null default 'active'
    check (status in ('active', 'trialing', 'past_due', 'canceled', 'paused')),
  revision bigint not null default 0 check (revision >= 0),
  limits jsonb not null default '{}'::jsonb,
  overage_policy text not null default 'block'
    check (overage_policy in ('block', 'grace', 'allow')),
  grace_until timestamptz,
  external_customer_id text,
  external_subscription_id text,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

create table if not exists public.workspace_billing_webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  event_id text not null,
  event_type text not null,
  project_id text not null references public.projects(id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  signature_hash text,
  status text not null default 'received'
    check (status in ('received', 'processed', 'failed')),
  error_code text,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (provider, event_id)
);

create index if not exists workspace_billing_webhook_events_project_received_idx
  on public.workspace_billing_webhook_events (project_id, received_at desc);
create index if not exists workspace_entitlements_provider_subscription_idx
  on public.workspace_entitlements (provider, external_subscription_id)
  where external_subscription_id is not null;

alter table public.workspace_entitlements enable row level security;
alter table public.workspace_billing_webhook_events enable row level security;

revoke all on public.workspace_entitlements from public, anon, authenticated;
revoke all on public.workspace_billing_webhook_events from public, anon, authenticated;

create or replace function public.get_workspace_entitlement(p_project_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  entitlement_row public.workspace_entitlements;
  policy jsonb;
  quota jsonb;
begin
  if auth.uid() is null or public.project_role(p_project_id) is null then
    raise exception using errcode = '42501', message = 'Workspace entitlement access denied';
  end if;

  select * into entitlement_row
  from public.workspace_entitlements
  where project_id = p_project_id;

  if entitlement_row.project_id is not null then
    return jsonb_build_object(
      'projectId', entitlement_row.project_id,
      'provider', entitlement_row.provider,
      'planId', entitlement_row.plan_id,
      'status', entitlement_row.status,
      'revision', entitlement_row.revision,
      'limits', entitlement_row.limits,
      'overagePolicy', entitlement_row.overage_policy,
      'graceUntil', entitlement_row.grace_until,
      'externalCustomerId', entitlement_row.external_customer_id,
      'externalSubscriptionId', entitlement_row.external_subscription_id,
      'metadata', entitlement_row.metadata,
      'fetchedAt', now(),
      'updatedAt', entitlement_row.updated_at
    );
  end if;

  policy := public.workspace_policy_for(p_project_id);
  quota := coalesce(policy -> 'quota', '{}'::jsonb);
  return jsonb_build_object(
    'projectId', p_project_id,
    'provider', 'manual',
    'planId', coalesce(policy ->> 'billingPlan', 'free'),
    'status', 'active',
    'revision', 0,
    'limits', jsonb_build_object(
      'storageBytes', coalesce(quota -> 'storageBytes', '0'::jsonb),
      'assetBytes', coalesce(quota -> 'assetBytes', quota -> 'storageBytes', '0'::jsonb),
      'transferBytes', coalesce(quota -> 'transferBytes', '0'::jsonb),
      'aiCredits', coalesce(quota -> 'aiCredits', '0'::jsonb),
      'renderSeconds', coalesce(quota -> 'renderSeconds', '0'::jsonb),
      'seats', coalesce(quota -> 'seats', quota -> 'projectCount', '1'::jsonb)
    ),
    'overagePolicy', 'block',
    'graceUntil', null,
    'externalCustomerId', null,
    'externalSubscriptionId', null,
    'metadata', '{}'::jsonb,
    'fetchedAt', now(),
    'updatedAt', null
  );
end;
$$;

create or replace function public.apply_workspace_billing_webhook(
  p_provider text,
  p_event_id text,
  p_event_type text,
  p_project_id text,
  p_plan_id text,
  p_status text,
  p_revision bigint default 0,
  p_limits jsonb default '{}'::jsonb,
  p_overage_policy text default 'block',
  p_grace_until timestamptz default null,
  p_external_customer_id text default null,
  p_external_subscription_id text default null,
  p_payload jsonb default '{}'::jsonb,
  p_signature_hash text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  webhook_row public.workspace_billing_webhook_events;
  entitlement_row public.workspace_entitlements;
  existing_entitlement public.workspace_entitlements;
  limit_key text;
  limit_value jsonb;
  applied boolean := false;
  stale boolean := false;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Billing webhook service access denied';
  end if;
  if length(trim(coalesce(p_provider, ''))) < 2
      or length(trim(p_provider)) > 64
      or trim(p_provider) !~ '^[a-z0-9._-]+$'
      or length(trim(coalesce(p_event_id, ''))) < 8
      or length(trim(p_event_id)) > 200
      or length(trim(coalesce(p_event_type, ''))) < 2
      or length(trim(p_event_type)) > 128
      or length(trim(coalesce(p_project_id, ''))) < 1
      or length(trim(p_project_id)) > 128
      or length(trim(coalesce(p_plan_id, ''))) < 1
      or length(trim(p_plan_id)) > 80
      or p_status not in ('active', 'trialing', 'past_due', 'canceled', 'paused')
      or coalesce(p_revision, 0) < 0
      or p_overage_policy not in ('block', 'grace', 'allow')
      or jsonb_typeof(coalesce(p_limits, '{}'::jsonb)) <> 'object'
      or jsonb_typeof(coalesce(p_payload, '{}'::jsonb)) <> 'object'
      or octet_length((coalesce(p_payload, '{}'::jsonb))::text) > 262144 then
    raise exception using errcode = '22023', message = 'Invalid billing webhook payload';
  end if;

  for limit_key, limit_value in
    select key, value from jsonb_each(coalesce(p_limits, '{}'::jsonb))
  loop
    if limit_key not in ('storageBytes', 'assetBytes', 'transferBytes', 'aiCredits', 'renderSeconds', 'projectCount', 'seats')
        or jsonb_typeof(limit_value) <> 'number'
        or (limit_value::text)::numeric < 0 then
      raise exception using errcode = '22023', message = 'Invalid entitlement limit';
    end if;
  end loop;

  insert into public.workspace_billing_webhook_events (
    provider, event_id, event_type, project_id, payload, signature_hash
  ) values (
    trim(p_provider), trim(p_event_id), trim(p_event_type), trim(p_project_id),
    coalesce(p_payload, '{}'::jsonb), nullif(trim(p_signature_hash), '')
  ) on conflict (provider, event_id) do nothing
  returning * into webhook_row;

  if webhook_row.id is null then
    select * into webhook_row
    from public.workspace_billing_webhook_events
    where provider = trim(p_provider) and event_id = trim(p_event_id);
    return jsonb_build_object(
      'accepted', true,
      'duplicate', true,
      'applied', false,
      'eventId', webhook_row.event_id,
      'eventType', webhook_row.event_type,
      'status', webhook_row.status
    );
  end if;

  select * into existing_entitlement
  from public.workspace_entitlements
  where project_id = trim(p_project_id);

  insert into public.workspace_entitlements (
    project_id, provider, plan_id, status, revision, limits, overage_policy,
    grace_until, external_customer_id, external_subscription_id, metadata,
    updated_at, updated_by
  ) values (
    trim(p_project_id), trim(p_provider), trim(p_plan_id), p_status,
    coalesce(p_revision, 0), coalesce(p_limits, '{}'::jsonb), p_overage_policy,
    p_grace_until, nullif(trim(p_external_customer_id), ''),
    nullif(trim(p_external_subscription_id), ''), '{}'::jsonb, now(), null
  ) on conflict (project_id) do update set
    provider = excluded.provider,
    plan_id = excluded.plan_id,
    status = excluded.status,
    revision = excluded.revision,
    limits = excluded.limits,
    overage_policy = excluded.overage_policy,
    grace_until = excluded.grace_until,
    external_customer_id = excluded.external_customer_id,
    external_subscription_id = excluded.external_subscription_id,
    updated_at = excluded.updated_at,
    updated_by = excluded.updated_by
  where excluded.revision >= public.workspace_entitlements.revision
  returning * into entitlement_row;

  if entitlement_row.project_id is null then
    stale := true;
    entitlement_row := existing_entitlement;
  else
    applied := true;
  end if;

  update public.workspace_billing_webhook_events
  set status = 'processed', processed_at = now()
  where id = webhook_row.id;

  return jsonb_build_object(
    'accepted', true,
    'duplicate', false,
    'applied', applied,
    'stale', stale,
    'eventId', webhook_row.event_id,
    'eventType', webhook_row.event_type,
    'status', 'processed',
    'entitlement', jsonb_build_object(
      'projectId', entitlement_row.project_id,
      'provider', entitlement_row.provider,
      'planId', entitlement_row.plan_id,
      'status', entitlement_row.status,
      'revision', entitlement_row.revision,
      'limits', entitlement_row.limits,
      'overagePolicy', entitlement_row.overage_policy,
      'graceUntil', entitlement_row.grace_until,
      'externalCustomerId', entitlement_row.external_customer_id,
      'externalSubscriptionId', entitlement_row.external_subscription_id,
      'fetchedAt', now(),
      'updatedAt', entitlement_row.updated_at
    )
  );
end;
$$;

grant execute on function public.get_workspace_entitlement(text) to authenticated;
grant execute on function public.apply_workspace_billing_webhook(text, text, text, text, text, text, bigint, jsonb, text, timestamptz, text, text, jsonb, text) to service_role;

revoke execute on function public.get_workspace_entitlement(text) from public, anon;
revoke execute on function public.apply_workspace_billing_webhook(text, text, text, text, text, text, bigint, jsonb, text, timestamptz, text, text, jsonb, text) from public, anon, authenticated;

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
  entitlement_row public.workspace_entitlements;
  current_usage jsonb;
  policy jsonb;
  current_value bigint;
  limit_value bigint;
  next_value bigint;
  effective_overage_policy text := 'block';
  effective_grace_until timestamptz;
  overage boolean := false;
begin
  if coalesce(auth.role(), '') <> 'service_role'
      and (
        auth.uid() is null
        or public.project_role(p_project_id) not in ('owner', 'editor')
      ) then
    raise exception using errcode = '42501', message = 'Workspace usage access denied';
  end if;
  -- Serialize quota reservations/releases per project. Without a row lock,
  -- concurrent asset uploads can both observe the same usage and exceed the
  -- authoritative limit before either ledger row is committed.
  perform 1 from public.projects where id = p_project_id for update;
  if not found then
    raise exception using errcode = '22023', message = 'Project not found';
  end if;
  if p_category not in ('storage', 'assets', 'ai_credits', 'projects')
      or p_delta <= 0
      or length(trim(coalesce(p_operation_id, ''))) < 8
      or length(trim(coalesce(p_operation_id, ''))) > 200
      or p_operation_id ~ '[[:cntrl:]]'
      or jsonb_typeof(coalesce(p_metadata, '{}'::jsonb)) <> 'object'
      or octet_length((coalesce(p_metadata, '{}'::jsonb))::text) > 32768 then
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
      'overage', false,
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
  limit_value := coalesce(case p_category
    when 'storage' then coalesce(
      (select (limits ->> 'storageBytes')::bigint from public.workspace_entitlements where project_id = p_project_id),
      (policy -> 'quota' ->> 'storageBytes')::bigint
    )
    when 'assets' then coalesce(
      (select (limits ->> 'assetBytes')::bigint from public.workspace_entitlements where project_id = p_project_id),
      (select (limits ->> 'storageBytes')::bigint from public.workspace_entitlements where project_id = p_project_id),
      (policy -> 'quota' ->> 'assetBytes')::bigint
    )
    when 'ai_credits' then coalesce(
      (select (limits ->> 'aiCredits')::bigint from public.workspace_entitlements where project_id = p_project_id),
      (policy -> 'quota' ->> 'aiCredits')::bigint
    )
    else coalesce(
      (select coalesce((limits ->> 'projectCount')::bigint, (limits ->> 'seats')::bigint) from public.workspace_entitlements where project_id = p_project_id),
      (policy -> 'quota' ->> 'projectCount')::bigint
    )
  end, 0);
  select overage_policy, grace_until into effective_overage_policy, effective_grace_until
  from public.workspace_entitlements
  where project_id = p_project_id;
  effective_overage_policy := coalesce(effective_overage_policy, 'block');

  next_value := current_value + p_delta;
  if next_value < 0 then
    raise exception using errcode = '54000', message = 'Workspace usage cannot be negative';
  end if;
  if next_value > limit_value then
    overage := true;
    if effective_overage_policy = 'grace'
        and effective_grace_until is not null
        and effective_grace_until > now() then
      null;
    elsif effective_overage_policy = 'allow' then
      null;
    else
      raise exception using errcode = '54000', message = 'Workspace quota exceeded';
    end if;
  end if;
  insert into public.workspace_usage_ledger (
    project_id, category, delta, operation_id, metadata, created_by
  ) values (
    p_project_id,
    p_category,
    p_delta,
    trim(p_operation_id),
    coalesce(p_metadata, '{}'::jsonb),
    coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
  );
  insert into public.workspace_audit_events (
    project_id, actor_id, action, metadata
  )
  values (
    p_project_id,
    coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid),
    'workspace.usage.recorded',
    jsonb_build_object(
      'category', p_category,
      'delta', p_delta,
      'operationId', trim(p_operation_id),
      'overage', overage
    )
  );
  return jsonb_build_object(
    'accepted', true,
    'duplicate', false,
    'overage', overage,
    'category', p_category,
    'delta', p_delta,
    'operationId', trim(p_operation_id),
    'usage', public.workspace_usage_for(p_project_id)
  );
end;
$$;

grant execute on function public.record_workspace_usage(text, text, bigint, text, jsonb) to authenticated;
revoke execute on function public.record_workspace_usage(text, text, bigint, text, jsonb) from public, anon;
