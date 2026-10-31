revoke all privileges on table public.workspace_notes
from public, anon, authenticated;

grant select, insert, update, delete
on table public.workspace_notes
to authenticated;
