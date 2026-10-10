create table if not exists public.projects (
  id text primary key,
  is_shared boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.canvas_snapshots (
  project_id text primary key references public.projects(id) on delete cascade,
  user_id text not null default 'local_user',
  document_data jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.comments (
  id text primary key,
  project_id text not null references public.projects(id) on delete cascade,
  author_id text not null default 'local_user',
  author_name text not null default 'Collaborator',
  text text not null default '',
  node_id text,
  x double precision not null default 0,
  y double precision not null default 0,
  resolved boolean not null default false,
  replies jsonb not null default '[]'::jsonb,
  mentions jsonb not null default '[]'::jsonb,
  reactions jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.projects enable row level security;
alter table public.canvas_snapshots enable row level security;
alter table public.comments enable row level security;

drop policy if exists projects_public_access on public.projects;
create policy projects_public_access on public.projects
  for all using (true) with check (true);

drop policy if exists canvas_snapshots_public_access on public.canvas_snapshots;
create policy canvas_snapshots_public_access on public.canvas_snapshots
  for all using (true) with check (true);

drop policy if exists comments_public_access on public.comments;
create policy comments_public_access on public.comments
  for all using (true) with check (true);

grant select, insert, update, delete on public.projects to anon, authenticated;
grant select, insert, update, delete on public.canvas_snapshots to anon, authenticated;
grant select, insert, update, delete on public.comments to anon, authenticated;
