-- Keep workspace usage authoritative for asset reservations on deployments
-- where the billing migration has already been applied. Asset catalog triggers
-- also run as service-role work, so the shared usage function must authorize
-- both project editors and the service role while serializing reservations.
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
  if p_project_id is null
      or p_project_id <> btrim(p_project_id)
      or length(trim(coalesce(p_project_id, ''))) < 1
      or length(trim(coalesce(p_project_id, ''))) > 256
      or p_project_id ~ '[[:cntrl:]]'
      or p_category not in ('storage', 'assets', 'ai_credits', 'projects')
      or p_delta is null
      or p_delta <= 0
      or p_operation_id is null
      or p_operation_id <> btrim(p_operation_id)
      or length(trim(coalesce(p_operation_id, ''))) < 8
      or length(trim(coalesce(p_operation_id, ''))) > 200
      or p_operation_id ~ '[[:cntrl:]]'
      or jsonb_typeof(coalesce(p_metadata, '{}'::jsonb)) <> 'object'
      or octet_length((coalesce(p_metadata, '{}'::jsonb))::text) > 32768 then
    raise exception using errcode = '22023', message = 'Invalid workspace usage entry';
  end if;

  -- Serialize quota reservations/releases per project. Without a row lock,
  -- concurrent asset uploads can both observe the same usage and exceed the
  -- authoritative limit before either ledger row is committed.
  perform 1 from public.projects where id = p_project_id for update;
  if not found then
    raise exception using errcode = '22023', message = 'Project not found';
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
  current_value := coalesce(case p_category
    when 'storage' then (current_usage ->> 'storageBytes')::bigint
    when 'assets' then (current_usage ->> 'assetBytes')::bigint
    when 'ai_credits' then (current_usage ->> 'aiCredits')::bigint
    else (current_usage ->> 'projectCount')::bigint
  end, 0);
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
