alter table public.projects
  add column if not exists name text,
  add column if not exists created_at timestamptz,
  add column if not exists archived_at timestamptz,
  add column if not exists trashed_at timestamptz;

update public.projects
set name = 'Untitled Project'
where name is null;

update public.projects
set created_at = coalesce(created_at, updated_at, now())
where created_at is null;

alter table public.projects
  alter column name set default 'Untitled Project',
  alter column name set not null,
  alter column created_at set default now(),
  alter column created_at set not null;

create table if not exists public.user_project_preferences (
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id text not null references public.projects(id) on delete cascade,
  is_pinned boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, project_id)
);

alter table public.user_project_preferences enable row level security;

drop policy if exists user_project_preferences_owner_access
  on public.user_project_preferences;
create policy user_project_preferences_owner_access
  on public.user_project_preferences
  for all to authenticated
  using (user_id = auth.uid() and public.can_read_project(project_id))
  with check (user_id = auth.uid() and public.can_read_project(project_id));

revoke all on public.user_project_preferences from anon;
revoke all on public.user_project_preferences from public;
grant select, insert, update, delete
  on public.user_project_preferences to authenticated;

