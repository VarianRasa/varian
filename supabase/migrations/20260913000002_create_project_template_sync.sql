create table if not exists public.project_templates (
  workspace_id text not null,
  template_id text not null,
  scope text not null check (scope in ('personal', 'team')),
  template_json jsonb not null,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_by uuid not null default auth.uid(),
  updated_at timestamptz not null default now(),
  primary key (workspace_id, template_id)
);

alter table public.project_templates enable row level security;
revoke all on public.project_templates from public, anon, authenticated;

create or replace function public.list_project_templates(p_workspace_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or public.project_role(p_workspace_id) is null then
    raise exception using errcode = '42501', message = 'Template access denied';
  end if;
  return coalesce(
    (
      select jsonb_agg(
        template_json || jsonb_build_object(
          'id', template_id,
          'scope', scope,
          'createdAt', created_at,
          'updatedAt', updated_at
        )
        order by updated_at desc
      )
      from public.project_templates
      where workspace_id = p_workspace_id
        and (scope = 'team' or created_by = auth.uid())
    ),
    '[]'::jsonb
  );
end;
$$;

create or replace function public.upsert_project_template(
  p_workspace_id text,
  p_template_id text,
  p_scope text,
  p_template_json jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  template_row public.project_templates;
begin
  if auth.uid() is null or public.project_role(p_workspace_id) not in ('owner', 'editor') then
    raise exception using errcode = '42501', message = 'Only project editors can sync templates';
  end if;
  if length(trim(coalesce(p_template_id, ''))) < 8
      or p_scope not in ('personal', 'team')
      or jsonb_typeof(p_template_json) <> 'object' then
    raise exception using errcode = '22023', message = 'Invalid project template';
  end if;
  insert into public.project_templates (
    workspace_id, template_id, scope, template_json, created_by, updated_by, updated_at
  ) values (
    p_workspace_id, trim(p_template_id), p_scope, p_template_json, auth.uid(), auth.uid(), now()
  ) on conflict (workspace_id, template_id) do update set
    scope = excluded.scope,
    template_json = excluded.template_json,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at
  where public.project_templates.scope = 'team'
     or public.project_templates.created_by = auth.uid()
  returning * into template_row;
  if template_row.template_id is null then
    raise exception using errcode = '42501', message = 'Template update is not allowed';
  end if;
  insert into public.workspace_audit_events (project_id, action, metadata)
  values (
    p_workspace_id,
    'template.synced',
    jsonb_build_object('templateId', template_row.template_id, 'scope', template_row.scope)
  );
  return template_row.template_json || jsonb_build_object(
    'id', template_row.template_id,
    'scope', template_row.scope,
    'createdAt', template_row.created_at,
    'updatedAt', template_row.updated_at
  );
end;
$$;

create or replace function public.delete_project_template(
  p_workspace_id text,
  p_template_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or public.project_role(p_workspace_id) not in ('owner', 'editor') then
    raise exception using errcode = '42501', message = 'Only project editors can delete templates';
  end if;
  delete from public.project_templates
  where workspace_id = p_workspace_id
    and template_id = trim(p_template_id)
    and (scope = 'team' or created_by = auth.uid());
  insert into public.workspace_audit_events (project_id, action, metadata)
  values (
    p_workspace_id,
    'template.deleted',
    jsonb_build_object('templateId', trim(p_template_id))
  );
end;
$$;

grant execute on function public.list_project_templates(text) to authenticated;
grant execute on function public.upsert_project_template(text, text, text, jsonb) to authenticated;
grant execute on function public.delete_project_template(text, text) to authenticated;
revoke execute on function public.list_project_templates(text) from public, anon;
revoke execute on function public.upsert_project_template(text, text, text, jsonb) from public, anon;
revoke execute on function public.delete_project_template(text, text) from public, anon;
