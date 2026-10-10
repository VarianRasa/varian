create table if not exists public.ai_video_jobs (
  request_id text primary key,
  model text not null,
  owner_subject text not null,
  status text not null check (status in ('queued', 'processing', 'completed', 'failed')),
  progress double precision check (progress is null or (progress >= 0 and progress <= 100)),
  video_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

alter table public.ai_video_jobs enable row level security;

revoke all on public.ai_video_jobs from public, anon, authenticated;
grant all on public.ai_video_jobs to service_role;
