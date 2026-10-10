alter table public.comments
  add column if not exists edited_at timestamptz;
