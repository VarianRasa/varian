create or replace function public.delete_workspace_plugin_registration(
  p_project_id text,
  p_plugin_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  deleted_plugin_id text;
begin
  if auth.uid() is null or not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can delete plugin registrations';
  end if;

  delete from public.workspace_plugin_registrations
  where project_id = p_project_id and plugin_id = trim(p_plugin_id)
  returning plugin_id into deleted_plugin_id;

  if deleted_plugin_id is null then
    return false;
  end if;

  insert into public.workspace_audit_events (project_id, action, metadata)
  values (
    p_project_id,
    'workspace.plugin.registration_deleted',
    jsonb_build_object('pluginId', deleted_plugin_id)
  );
  return true;
end;
$$;

grant execute on function public.delete_workspace_plugin_registration(text, text) to authenticated;
revoke execute on function public.delete_workspace_plugin_registration(text, text) from public, anon;
