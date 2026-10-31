alter table public.workspace_notes
  add column if not exists revision integer;

update public.workspace_notes
set revision = 1
where revision is null;

alter table public.workspace_notes
  alter column revision set default 1,
  alter column revision set not null;
