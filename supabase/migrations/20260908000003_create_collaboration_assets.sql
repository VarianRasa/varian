-- Shared binary assets used by collaborative canvas nodes.
-- The bucket is public so CRDT payloads can carry a stable URL that every
-- authenticated client can render without copying image bytes into CRDT ops.

insert into storage.buckets (id, name, public)
values ('assets', 'assets', true)
on conflict (id) do update
set public = excluded.public;

grant select, insert, update on storage.objects to authenticated;
grant execute on function public.can_read_project(text) to authenticated;
grant execute on function public.can_edit_project(text) to authenticated;

drop policy if exists collaboration_assets_read on storage.objects;
create policy collaboration_assets_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'assets'
    and public.can_read_project(
      case
        when split_part(name, '/', 1) = 'drawing-paper'
          then split_part(name, '/', 2)
        else split_part(name, '/', 1)
      end
    )
  );

drop policy if exists collaboration_assets_insert on storage.objects;
create policy collaboration_assets_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'assets'
    and public.can_edit_project(
      case
        when split_part(name, '/', 1) = 'drawing-paper'
          then split_part(name, '/', 2)
        else split_part(name, '/', 1)
      end
    )
  );

drop policy if exists collaboration_assets_update on storage.objects;
create policy collaboration_assets_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'assets'
    and public.can_edit_project(
      case
        when split_part(name, '/', 1) = 'drawing-paper'
          then split_part(name, '/', 2)
        else split_part(name, '/', 1)
      end
    )
  )
  with check (
    bucket_id = 'assets'
    and public.can_edit_project(
      case
        when split_part(name, '/', 1) = 'drawing-paper'
          then split_part(name, '/', 2)
        else split_part(name, '/', 1)
      end
    )
  );
