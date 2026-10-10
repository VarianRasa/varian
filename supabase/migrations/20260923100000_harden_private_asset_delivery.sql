-- Keep collaborative binaries private. Canvas and catalog payloads store stable
-- object paths; clients must request short-lived signed URLs when rendering.
insert into storage.buckets (id, name, public)
values ('assets', 'assets', false)
on conflict (id) do update
set public = false;

grant select, insert, update, delete on storage.objects to authenticated;
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

drop policy if exists collaboration_assets_delete on storage.objects;
create policy collaboration_assets_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'assets'
    and public.can_edit_project(
      case
        when split_part(name, '/', 1) = 'drawing-paper'
          then split_part(name, '/', 2)
        else split_part(name, '/', 1)
      end
    )
  );
