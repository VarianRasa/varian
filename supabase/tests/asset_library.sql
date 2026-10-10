create extension if not exists pgtap;
begin;
set local search_path = public, extensions;
select plan(26);

select has_table(
  'public',
  'asset_library_items',
  'asset catalog table exists'
);
select has_table(
  'public',
  'asset_library_favorites',
  'asset favorites table exists'
);
select has_function(
  'public',
  'is_asset_library_storage_path',
  ARRAY['text'],
  'Storage namespace validator exists'
);
select ok(
  public.is_asset_library_storage_path(
    'asset-p1/library/550e8400-e29b-41d4-a716-446655440000_logo.png'
  ),
  'UUID-addressed library path is accepted'
);
select ok(
  not public.is_asset_library_storage_path(
    'asset-p1/library/not-a-uuid_logo.png'
  ),
  'non-UUID library path is rejected'
);

select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'service_role', true);
insert into public.projects (id, owner_id)
values
  ('asset-p1', '00000000-0000-0000-0000-000000000001'),
  ('asset-p2', '00000000-0000-0000-0000-000000000002');
insert into public.workspace_entitlements (
  project_id,
  provider,
  plan_id,
  status,
  limits,
  overage_policy
)
values
  ('asset-p1', 'manual', 'test', 'active', '{"assetBytes": 8}', 'block'),
  ('asset-p2', 'manual', 'test', 'active', '{"assetBytes": 8}', 'block');

select lives_ok(
  $$
    insert into public.asset_library_folders (id, project_id, name)
    values ('shared-folder-id', 'asset-p1', 'Brand')
  $$,
  'a folder can be created in the first project'
);
select lives_ok(
  $$
    insert into public.asset_library_folders (id, project_id, name)
    values ('shared-folder-id', 'asset-p2', 'Brand')
  $$,
  'the same folder ID can be scoped to a second project'
);
select is(
  (
    select count(*)::integer
    from public.asset_library_folders
    where id = 'shared-folder-id'
  ),
  2,
  'folder IDs are isolated by project scope'
);

select lives_ok(
  $$
    insert into public.asset_library_items (
      id, project_id, kind, source, status, name, source_url, mime_type,
      license, tags, metadata
    ) values (
      'openverse:same', 'asset-p1', 'image', 'openverse', 'ready', 'P1',
      'https://example.org/p1.png', 'image/png', 'CC0', '{}', '{}'
    )
  $$,
  'an item can be created in the first project'
);
select lives_ok(
  $$
    insert into public.asset_library_items (
      id, project_id, kind, source, status, name, source_url, mime_type,
      license, tags, metadata
    ) values (
      'openverse:same', 'asset-p2', 'image', 'openverse', 'ready', 'P2',
      'https://example.org/p2.png', 'image/png', 'CC0', '{}', '{}'
    )
  $$,
  'the same provider item ID can be scoped to a second project'
);
select is(
  (
    select count(*)::integer
    from public.asset_library_items
    where id = 'openverse:same'
  ),
  2,
  'provider item IDs are isolated by project scope'
);
select throws_ok(
  $$
    insert into public.asset_library_items (
      id, project_id, kind, source, status, name, source_url, mime_type,
      tags, metadata
    ) values (
      'unlicensed', 'asset-p1', 'image', 'openverse', 'ready', 'Unlicensed',
      'https://example.org/unlicensed.png', 'image/png', '{}', '{}'
    )
  $$,
  'External asset licenses are required',
  'external provider rows require license provenance'
);
select throws_ok(
  $$
    insert into public.asset_library_items (
      id, project_id, kind, source, status, name, source_url, mime_type,
      license, tags, metadata
    ) values (
      'whitespace-license', 'asset-p1', 'image', 'openverse', 'ready',
      'Whitespace license', 'https://example.org/whitespace.png',
      'image/png', ' CC0 ', '{}', '{}'
    )
  $$,
  'Asset license cannot contain surrounding whitespace',
  'external license provenance is validated before normalization'
);

insert into storage.objects (
  bucket_id,
  name,
  metadata,
  version,
  is_versioned
)
values (
  'assets',
  'asset-p1/library/550e8400-e29b-41d4-a716-446655440000_logo.png',
  '{"size": 8, "mimetype": "image/png"}',
  'asset-library-test-v1',
  false
);
select lives_ok(
  $$
    insert into public.asset_library_items (
      id, project_id, kind, source, status, name, mime_type, size_bytes,
      storage_path, tags, metadata
    ) values (
      'upload-1', 'asset-p1', 'image', 'upload', 'ready', 'Logo', 'image/png',
      8,
      'asset-p1/library/550e8400-e29b-41d4-a716-446655440000_logo.png',
      '{}', '{}'
    )
  $$,
  'a Storage-backed item reserves its exact byte count'
);
select is(
  public.workspace_usage_for('asset-p1') ->> 'assetBytes',
  '8',
  'Storage-backed catalog rows reserve asset quota'
);

insert into storage.objects (
  bucket_id,
  name,
  metadata,
  version,
  is_versioned
)
values (
  'assets',
  'asset-p1/library/550e8400-e29b-41d4-a716-446655440001_extra.png',
  '{"size": 1, "mimetype": "image/png"}',
  'asset-library-test-v2',
  false
);
select throws_ok(
  $$
    insert into public.asset_library_items (
      id, project_id, kind, source, status, name, mime_type, size_bytes,
      storage_path, tags, metadata
    ) values (
      'upload-over-quota', 'asset-p1', 'image', 'upload', 'ready', 'Extra',
      'image/png', 1,
      'asset-p1/library/550e8400-e29b-41d4-a716-446655440001_extra.png',
      '{}', '{}'
    )
  $$,
  'Workspace quota exceeded',
  'quota blocks a Storage-backed row before it is committed'
);
select throws_ok(
  $$
    insert into public.asset_library_items (
      id, project_id, kind, source, status, name, mime_type, size_bytes,
      storage_path, tags, metadata
    ) values (
      'invalid-path', 'asset-p1', 'image', 'upload', 'ready', 'Invalid',
      'image/png', 1, 'asset-p1/library/not-a-uuid.png', '{}', '{}'
    )
  $$,
  'Asset storage path is invalid',
  'catalog rows reject non-UUID Storage paths'
);

select lives_ok(
  $$
    delete from public.asset_library_items
    where project_id = 'asset-p1' and id = 'upload-1'
  $$,
  'deleting a catalog row releases reserved quota'
);
select is(
  public.workspace_usage_for('asset-p1') ->> 'assetBytes',
  '0',
  'quota release is clamped at zero'
);
select is(
  public.record_asset_library_usage_release(
    'asset-p1', -100, 'asset-library:remove:over-release', '{}'
  ) ->> 'delta',
  '0',
  'an over-release cannot create negative usage'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000001',
  true
);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is(
  (
    select count(*)::integer
    from public.asset_library_items
    where project_id = 'asset-p1'
  ),
  1,
  'project members can read their own catalog'
);
select is(
  (
    select count(*)::integer
    from public.asset_library_items
    where project_id = 'asset-p2'
  ),
  0,
  'RLS hides another project catalog'
);
select lives_ok(
  $$
    insert into public.asset_library_favorites (project_id, item_id)
    values ('asset-p1', 'openverse:same')
  $$,
  'a member can write a personal favorite in their project'
);
select lives_ok(
  $$
    update storage.objects
    set metadata = jsonb_build_object('size', 9, 'mimetype', 'image/png')
    where bucket_id = 'assets'
      and name = 'asset-p1/library/550e8400-e29b-41d4-a716-446655440000_logo.png'
  $$,
  'library Storage update requests do not bypass policy'
);
select is(
  (
    select metadata ->> 'size'
    from storage.objects
    where bucket_id = 'assets'
      and name = 'asset-p1/library/550e8400-e29b-41d4-a716-446655440000_logo.png'
  ),
  '8',
  'library Storage objects cannot be updated in place'
);
select throws_ok(
  $$
    delete from storage.objects
    where bucket_id = 'assets'
      and name = 'asset-p1/library/550e8400-e29b-41d4-a716-446655440000_logo.png'
  $$,
  'Direct deletion from storage tables is not allowed. Use the Storage API instead.',
  'binary deletion must use the Storage API'
);

set local role postgres;
select * from finish();
rollback;
