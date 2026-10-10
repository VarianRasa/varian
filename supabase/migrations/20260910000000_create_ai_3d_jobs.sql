create table if not exists public.ai_3d_jobs (
  request_id text primary key,
  project_id text not null references public.projects(id) on delete cascade,
  owner_subject uuid not null,
  worker_job_id text not null,
  capability text not null check (capability in ('textTo3D', 'imageTo3D')),
  provider text not null,
  status text not null check (status in ('queued', 'processing', 'completed', 'failed', 'canceled')),
  progress double precision check (progress is null or (progress >= 0 and progress <= 100)),
  prompt text not null,
  parameters jsonb not null default '{}'::jsonb,
  artifact jsonb,
  artifact_path text,
  error_code text,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists ai_3d_jobs_owner_created_idx
  on public.ai_3d_jobs (owner_subject, created_at desc);
create index if not exists ai_3d_jobs_project_created_idx
  on public.ai_3d_jobs (project_id, created_at desc);
create unique index if not exists ai_3d_jobs_worker_job_idx
  on public.ai_3d_jobs (worker_job_id);

alter table public.ai_3d_jobs enable row level security;
revoke all on public.ai_3d_jobs from public, anon, authenticated;
grant all on public.ai_3d_jobs to service_role;

create or replace function public.touch_ai_3d_job_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists ai_3d_jobs_touch_updated_at on public.ai_3d_jobs;
create trigger ai_3d_jobs_touch_updated_at
before update on public.ai_3d_jobs
for each row execute function public.touch_ai_3d_job_updated_at();
