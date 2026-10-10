-- Avoid per-row auth lookups and avoid a write policy overlapping the folder
-- read policy for SELECT.
drop policy if exists asset_library_folders_write
  on public.asset_library_folders;
drop policy if exists asset_library_folders_insert
  on public.asset_library_folders;
drop policy if exists asset_library_folders_update
  on public.asset_library_folders;
drop policy if exists asset_library_folders_delete
  on public.asset_library_folders;

create policy asset_library_folders_insert on public.asset_library_folders
  for insert to authenticated
  with check (public.can_edit_project(project_id));

create policy asset_library_folders_update on public.asset_library_folders
  for update to authenticated
  using (public.can_edit_project(project_id))
  with check (public.can_edit_project(project_id));

create policy asset_library_folders_delete on public.asset_library_folders
  for delete to authenticated
  using (public.can_edit_project(project_id));

drop policy if exists asset_library_favorites_read
  on public.asset_library_favorites;
create policy asset_library_favorites_read on public.asset_library_favorites
  for select to authenticated
  using (
    user_id = (select auth.uid())
    and public.can_read_project(project_id)
  );

drop policy if exists asset_library_favorites_insert
  on public.asset_library_favorites;
create policy asset_library_favorites_insert on public.asset_library_favorites
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and public.can_read_project(project_id)
  );

drop policy if exists asset_library_favorites_update
  on public.asset_library_favorites;
create policy asset_library_favorites_update on public.asset_library_favorites
  for update to authenticated
  using (
    user_id = (select auth.uid())
    and public.can_read_project(project_id)
  )
  with check (
    user_id = (select auth.uid())
    and public.can_read_project(project_id)
  );

drop policy if exists asset_library_favorites_delete
  on public.asset_library_favorites;
create policy asset_library_favorites_delete on public.asset_library_favorites
  for delete to authenticated
  using (
    user_id = (select auth.uid())
    and public.can_read_project(project_id)
  );
