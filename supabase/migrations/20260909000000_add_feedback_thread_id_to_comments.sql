alter table public.comments
  add column if not exists feedback_thread_id text;

create index if not exists comments_project_feedback_thread_idx
  on public.comments (project_id, feedback_thread_id, created_at);
