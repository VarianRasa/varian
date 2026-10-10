alter table public.workspace_audit_events
  add column if not exists operation text,
  add column if not exists target_type text,
  add column if not exists target_id text,
  add column if not exists result text,
  add column if not exists correlation_id text;

update public.workspace_audit_events
set operation = coalesce(nullif(trim(operation), ''), action),
    target_type = coalesce(nullif(trim(target_type), ''), 'project'),
    target_id = coalesce(nullif(trim(target_id), ''), project_id),
    result = coalesce(nullif(trim(result), ''), 'success'),
    correlation_id = coalesce(nullif(trim(correlation_id), ''), id::text);

alter table public.workspace_audit_events
  alter column operation set not null,
  alter column target_type set not null,
  alter column target_id set not null,
  alter column result set not null,
  alter column correlation_id set not null;

create index if not exists workspace_audit_events_correlation_idx
  on public.workspace_audit_events (project_id, correlation_id);

create or replace function public.normalize_workspace_audit_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.operation := coalesce(nullif(trim(new.operation), ''), nullif(trim(new.action), ''), 'unknown');
  new.target_type := coalesce(nullif(trim(new.target_type), ''), 'project');
  new.target_id := coalesce(nullif(trim(new.target_id), ''), new.project_id);
  new.result := coalesce(nullif(trim(new.result), ''), 'success');
  new.correlation_id := coalesce(nullif(trim(new.correlation_id), ''), gen_random_uuid()::text);
  new.metadata := jsonb_strip_nulls(
    coalesce(new.metadata, '{}'::jsonb)
      - 'serviceRoleKey'
      - 'service_role_key'
      - 'accessToken'
      - 'access_token'
      - 'refreshToken'
      - 'refresh_token'
      - 'apiKey'
      - 'api_key'
      - 'turnSecret'
      - 'turn_secret'
  );
  return new;
end;
$$;

drop trigger if exists normalize_workspace_audit_event_trigger
  on public.workspace_audit_events;
create trigger normalize_workspace_audit_event_trigger
before insert or update on public.workspace_audit_events
for each row execute function public.normalize_workspace_audit_event();

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

grant execute on function public.list_workspace_audit_events(text, integer) to authenticated;
revoke execute on function public.list_workspace_audit_events(text, integer) from public, anon;
