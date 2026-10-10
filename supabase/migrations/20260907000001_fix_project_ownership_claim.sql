-- Ensure authenticated owners can create or claim a project atomically.
-- Existing projects owned by another user remain protected.

create or replace function public.claim_canvas_project_ownership(p_project_id text)
returns public.projects
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.projects;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  insert into public.projects as project (
    id,
    owner_id,
    updated_by,
    updated_at
  ) values (
    p_project_id,
    auth.uid(),
    auth.uid(),
    now()
  )
  on conflict (id) do update set
    owner_id = coalesce(project.owner_id, excluded.owner_id),
    updated_by = case
      when project.owner_id is null then excluded.updated_by
      else project.updated_by
    end,
    updated_at = case
      when project.owner_id is null then excluded.updated_at
      else project.updated_at
    end
  where project.owner_id is null
     or project.owner_id = auth.uid()
  returning * into result;

  if result.id is null or result.owner_id <> auth.uid() then
    raise exception using errcode = '42501', message = 'Project ownership cannot be claimed';
  end if;
  return result;
end;
$$;

grant execute on function public.claim_canvas_project_ownership(text)
to authenticated;
