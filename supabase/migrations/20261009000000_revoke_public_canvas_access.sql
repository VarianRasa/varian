-- Core project data must never retain prototype-wide client access.
-- Preserve authenticated access for policies scoped to project membership.
drop policy if exists projects_public_access on public.projects;
drop policy if exists canvas_snapshots_public_access on public.canvas_snapshots;
drop policy if exists comments_public_access on public.comments;

revoke all on public.projects from public, anon;
revoke all on public.canvas_snapshots from public, anon;
revoke all on public.comments from public, anon;

grant select, insert, update, delete
  on public.projects, public.canvas_snapshots, public.comments
  to authenticated;

do $$
begin
  if has_table_privilege('anon', 'public.projects', 'SELECT')
    or has_table_privilege('anon', 'public.projects', 'INSERT')
    or has_table_privilege('anon', 'public.projects', 'UPDATE')
    or has_table_privilege('anon', 'public.projects', 'DELETE')
    or has_table_privilege('anon', 'public.canvas_snapshots', 'SELECT')
    or has_table_privilege('anon', 'public.canvas_snapshots', 'INSERT')
    or has_table_privilege('anon', 'public.canvas_snapshots', 'UPDATE')
    or has_table_privilege('anon', 'public.canvas_snapshots', 'DELETE')
    or has_table_privilege('anon', 'public.comments', 'SELECT')
    or has_table_privilege('anon', 'public.comments', 'INSERT')
    or has_table_privilege('anon', 'public.comments', 'UPDATE')
    or has_table_privilege('anon', 'public.comments', 'DELETE')
  then
    raise exception 'Anonymous access remains enabled for core project data';
  end if;

  if exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename in ('projects', 'canvas_snapshots', 'comments')
      and roles && array['anon']::name[]
  ) then
    raise exception 'An anon policy remains enabled for core project data';
  end if;
end;
$$;
