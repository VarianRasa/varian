create or replace function public.run_workspace_retention_maintenance(p_project_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  policy jsonb := public.workspace_policy_for(trim(coalesce(p_project_id, '')));
  audit_cutoff timestamptz;
  export_cutoff timestamptz;
  audit_deleted integer := 0;
  export_deleted integer := 0;
  project_id text := trim(coalesce(p_project_id, ''));
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Retention maintenance requires service role';
  end if;
  if project_id = '' then
    raise exception using errcode = '22023', message = 'Project ID is required';
  end if;

  audit_cutoff := now() - make_interval(days => greatest(1, (policy -> 'retention' ->> 'auditLogRetentionDays')::integer));
  export_cutoff := now() - make_interval(days => greatest(1, (policy -> 'retention' ->> 'trashRetentionDays')::integer));

  delete from public.workspace_audit_events
  where workspace_audit_events.project_id = project_id
    and workspace_audit_events.created_at < audit_cutoff;
  get diagnostics audit_deleted = row_count;

  delete from public.workspace_data_export_requests
  where workspace_data_export_requests.project_id = project_id
    and workspace_data_export_requests.status in ('ready', 'failed', 'expired')
    and coalesce(workspace_data_export_requests.completed_at, workspace_data_export_requests.requested_at) < export_cutoff;
  get diagnostics export_deleted = row_count;

  insert into public.workspace_audit_events (project_id, action, metadata)
  values (
    project_id,
    'workspace.retention.maintenance_completed',
    jsonb_build_object(
      'auditDeleted', audit_deleted,
      'exportDeleted', export_deleted,
      'auditCutoff', audit_cutoff,
      'exportCutoff', export_cutoff
    )
  );

  return jsonb_build_object(
    'projectId', project_id,
    'auditDeleted', audit_deleted,
    'exportDeleted', export_deleted,
    'auditCutoff', audit_cutoff,
    'exportCutoff', export_cutoff
  );
end;
$$;

revoke all on function public.run_workspace_retention_maintenance(text) from public, anon, authenticated;
grant execute on function public.run_workspace_retention_maintenance(text) to service_role;
