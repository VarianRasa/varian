-- Reusable, project-scoped asset catalog. Binary data stays in Storage; this
-- table stores searchable metadata, provenance, and durable references only.
-- The bucket is shared with collaboration assets, so keep its broad MIME
-- support but enforce the catalog's hard binary size ceiling at Storage level.
update storage.buckets
set file_size_limit = 536870912
where id = 'assets';

-- Library uploads are UUID-addressed and use a dedicated namespace in the
-- shared bucket. Keep this predicate in one place for the catalog trigger and
-- Storage RLS so a direct Storage client cannot choose a colliding path.
create or replace function public.is_asset_library_storage_path(p_name text)
returns boolean
language sql
immutable
set search_path = public
as $$
  select p_name is not null
    and length(p_name) <= 512
    and position(chr(92) in p_name) = 0
    and p_name !~ '[[:cntrl:]]'
    and p_name ~* '^[^/]+/(images|files|audio|video|library)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}_[^/]+$';
$$;

revoke all on function public.is_asset_library_storage_path(text)
from public, anon, authenticated;

grant execute on function public.is_asset_library_storage_path(text)
to authenticated;

create table if not exists public.asset_library_items (
  id text not null,
  project_id text not null references public.projects(id) on delete cascade,
  kind text not null check (kind in (
    'image', 'graphic', 'icon', 'illustration', 'video', 'audio', 'model3d', 'file'
  )),
  source text not null check (source in (
    'upload', 'openverse', 'wikimedia', 'bundled', 'remote'
  )),
  status text not null default 'ready' check (status in (
    'ready', 'syncing', 'missing', 'failed'
  )),
  name text not null check (length(trim(name)) between 1 and 240),
  description text,
  creator text,
  creator_url text,
  source_url text,
  preview_url text,
  download_url text,
  local_path text,
  storage_path text,
  mime_type text not null default 'application/octet-stream',
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  width integer check (width is null or width > 0),
  height integer check (height is null or height > 0),
  duration_ms bigint check (duration_ms is null or duration_ms >= 0),
  checksum text,
  provider_asset_id text,
  license text,
  license_url text,
  attribution text,
  folder_id text,
  tags text[] not null default '{}',
  usage_count bigint not null default 0 check (usage_count >= 0),
  last_used_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (project_id, id),
  unique (project_id, source, provider_asset_id)
);

create or replace function public.asset_library_usage_operation(
  p_prefix text,
  p_item_id text
)
returns text
language sql
immutable
set search_path = public
as $$
  select coalesce(p_prefix, '') || case
    when length(coalesce(p_prefix, '')) + length(coalesce(p_item_id, '')) <= 200
      then coalesce(p_item_id, '')
    else md5(coalesce(p_item_id, ''))
  end;
$$;

revoke all on function public.asset_library_usage_operation(text, text)
from public, anon, authenticated;

-- Storage quota releases are performed by the catalog delete trigger, not by
-- an editor-callable RPC. Keeping this function ungranted prevents a client
-- from manufacturing negative usage entries to bypass an asset quota.
create or replace function public.record_asset_library_usage_release(
  p_project_id text,
  p_delta bigint,
  p_operation_id text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_row public.workspace_usage_ledger;
  current_usage jsonb;
  current_value bigint;
  effective_delta bigint;
begin
  if p_project_id is null
      or p_project_id <> btrim(p_project_id)
      or length(trim(coalesce(p_project_id, ''))) < 1
      or length(trim(coalesce(p_project_id, ''))) > 256
      or p_project_id ~ '[[:cntrl:]]'
      or p_delta is null
      or p_delta >= 0
      or p_operation_id is null
      or p_operation_id <> btrim(p_operation_id)
      or length(trim(coalesce(p_operation_id, ''))) < 8
      or length(trim(coalesce(p_operation_id, ''))) > 200
      or p_operation_id ~ '[[:cntrl:]]'
      or jsonb_typeof(coalesce(p_metadata, '{}'::jsonb)) <> 'object'
      or octet_length((coalesce(p_metadata, '{}'::jsonb))::text) > 32768 then
    raise exception using errcode = '22023', message = 'Invalid asset usage release';
  end if;

  perform 1 from public.projects where id = p_project_id for update;
  if not found then
    -- A project delete cascades its usage ledger. Do not make that cascade
    -- fail merely because the child asset trigger runs after the parent row
    -- has become invisible to this transaction.
    return jsonb_build_object(
      'accepted', true,
      'duplicate', false,
      'category', 'assets',
      'delta', p_delta,
      'operationId', trim(p_operation_id),
      'skipped', true
    );
  end if;

  select * into existing_row
  from public.workspace_usage_ledger
  where project_id = p_project_id
    and category = 'assets'
    and operation_id = trim(p_operation_id);
  if existing_row.id is not null then
    return jsonb_build_object(
      'accepted', true,
      'duplicate', true,
      'category', existing_row.category,
      'delta', existing_row.delta,
      'operationId', existing_row.operation_id,
      'usage', public.workspace_usage_for(p_project_id)
    );
  end if;

  current_usage := public.workspace_usage_for(p_project_id);
  current_value := coalesce((current_usage ->> 'assetBytes')::bigint, 0);
  effective_delta := case
    when current_value <= 0 then 0
    when current_value + p_delta < 0 then -current_value
    else p_delta
  end;
  if effective_delta = 0 then
    return jsonb_build_object(
      'accepted', true,
      'duplicate', false,
      'category', 'assets',
      'delta', 0,
      'requestedDelta', p_delta,
      'operationId', trim(p_operation_id),
      'usage', current_usage,
      'clamped', true
    );
  end if;

  insert into public.workspace_usage_ledger (
    project_id, category, delta, operation_id, metadata, created_by
  ) values (
    p_project_id,
    'assets',
    effective_delta,
    trim(p_operation_id),
    coalesce(p_metadata, '{}'::jsonb),
    coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
  );
  insert into public.workspace_audit_events (
    project_id, actor_id, action, metadata
  ) values (
    p_project_id,
    coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid),
    'workspace.usage.recorded',
    jsonb_build_object(
      'category', 'assets',
      'delta', effective_delta,
      'requestedDelta', p_delta,
      'operationId', trim(p_operation_id),
      'source', 'asset_library.delete'
    )
  );
  return jsonb_build_object(
    'accepted', true,
    'duplicate', false,
    'category', 'assets',
    'delta', effective_delta,
    'requestedDelta', p_delta,
    'operationId', trim(p_operation_id),
    'usage', public.workspace_usage_for(p_project_id),
    'clamped', effective_delta <> p_delta
  );
end;
$$;

revoke all on function public.record_asset_library_usage_release(text, bigint, text, jsonb)
from public, anon, authenticated;

create or replace function public.validate_asset_library_item_boundaries()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  should_charge boolean := false;
begin
  if tg_op = 'DELETE' then
    if old.storage_path is not null and old.size_bytes is not null and old.size_bytes > 0 then
      perform public.record_asset_library_usage_release(
        old.project_id,
        -old.size_bytes,
        public.asset_library_usage_operation(
          'asset-library:remove:',
          old.id || ':' || coalesce(old.storage_path, '')
        ),
        jsonb_build_object(
          'assetId', old.id,
          'sizeBytes', old.size_bytes,
          'source', old.source
        )
      );
    end if;
    return old;
  end if;

  if new.source = 'bundled' then
    raise exception using errcode = '22023', message = 'Bundled assets are local-only';
  end if;
  if tg_op = 'INSERT'
      and (coalesce(new.usage_count, 0) <> 0 or new.last_used_at is not null) then
    raise exception using errcode = '42501', message = 'Asset usage is recorded through its RPC';
  end if;
  if tg_op = 'UPDATE'
      and (new.usage_count is distinct from old.usage_count
        or new.last_used_at is distinct from old.last_used_at)
      and coalesce(current_setting('asset_library.usage_rpc', true), '') <> 'on' then
    raise exception using errcode = '42501', message = 'Asset usage is recorded through its RPC';
  end if;
  if tg_op = 'INSERT' and auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  if tg_op = 'INSERT' and new.checksum is not null and
      new.checksum ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'Asset checksum contains control characters';
  end if;
  if tg_op = 'INSERT' and new.checksum is not null then
    new.checksum := lower(btrim(new.checksum));
  end if;
  if btrim(new.id) = ''
      or new.id <> btrim(new.id)
      or length(new.id) > 256
      or new.id ~ '[[:cntrl:]]'
      or btrim(new.project_id::text) = ''
      or new.project_id <> btrim(new.project_id::text)
      or length(new.project_id::text) > 256
      or new.project_id = 'drawing-paper' then
    raise exception using errcode = '22023', message = 'Asset identity is invalid';
  end if;
  if new.size_bytes is not null and new.size_bytes > 536870912 then
    raise exception using errcode = '22023', message = 'Asset exceeds the 512 MB upload limit';
  end if;
  if new.checksum is not null
      and new.checksum !~* '^(sha256:)?[0-9a-f]{64}$' then
    raise exception using errcode = '22023', message = 'Asset checksum must be SHA-256';
  end if;
  if jsonb_typeof(coalesce(new.metadata, '{}'::jsonb)) <> 'object'
      or octet_length(coalesce(new.metadata, '{}'::jsonb)::text) > 262144
      or coalesce(new.metadata, '{}'::jsonb)::text ~* '"[[:space:]]*data:[^"]*' then
    raise exception using errcode = '22023', message = 'Asset metadata is too large or contains binary data';
  end if;
  if coalesce(array_position(new.tags, null), 0) > 0
      or cardinality(new.tags) > 50
      or exists (
        select 1 from unnest(new.tags) tag
        where btrim(tag) = ''
          or tag <> btrim(tag)
          or length(tag) > 80
          or tag ~ '[[:cntrl:]]'
      ) then
    raise exception using errcode = '22023', message = 'Asset tags are invalid';
  end if;
  if btrim(new.name) = ''
      or new.name <> btrim(new.name)
      or length(new.name) > 240
      or new.name ~ '[[:cntrl:]]'
      or (new.description is not null and (
        length(new.description) > 4096
        or replace(replace(replace(new.description, chr(9), ''), chr(10), ''), chr(13), '')
          ~ '[[:cntrl:]]'
      ))
      or (new.creator is not null and (
        length(new.creator) > 240 or new.creator ~ '[[:cntrl:]]'
      ))
      or (new.license is not null and (
        length(new.license) > 120 or new.license ~ '[[:cntrl:]]'
      ))
      or (new.attribution is not null and (
        length(new.attribution) > 4096 or new.attribution ~ '[[:cntrl:]]'
      )) then
    raise exception using errcode = '22023', message = 'Asset text metadata is invalid';
  end if;
  if new.mime_type is null
      or length(new.mime_type) > 120
      or new.mime_type !~* '^[a-z0-9][a-z0-9!#$&^_.+-]*/[a-z0-9][a-z0-9!#$&^_.+-]*$'
      or new.mime_type ~ '[[:cntrl:]]' then
    raise exception using errcode = '22023', message = 'Asset MIME type is invalid';
  end if;
  if new.provider_asset_id is not null and (
      length(btrim(new.provider_asset_id)) = 0
      or new.provider_asset_id <> btrim(new.provider_asset_id)
      or length(new.provider_asset_id) > 256
      or new.provider_asset_id ~ '[[:cntrl:]]'
    ) then
    raise exception using errcode = '22023', message = 'Asset provider ID is invalid';
  end if;
  if new.local_path is not null and btrim(new.local_path) <> '' then
    raise exception using errcode = '22023', message = 'Machine-local paths cannot be stored remotely';
  end if;
  if new.storage_path is not null and (
      btrim(new.storage_path) = ''
      or length(new.storage_path) > 512
      or left(new.storage_path, 1) = '/'
      or position(chr(92) in new.storage_path) > 0
      or position('//' in new.storage_path) > 0
      or right(new.storage_path, 1) = '/'
      or new.storage_path <> btrim(new.storage_path)
      or new.storage_path ~ '(^|/)([.]{1,2})(/|$)'
      or new.storage_path ~ '[[:cntrl:]]'
      or split_part(new.storage_path, '/', 3) = ''
      or split_part(new.storage_path, '/', 1) <> new.project_id
      or split_part(new.storage_path, '/', 2) not in (
        'images', 'files', 'audio', 'video', 'library'
      )
      or not public.is_asset_library_storage_path(new.storage_path)
    ) then
    raise exception using errcode = '22023', message = 'Asset storage path is invalid';
  end if;
  if new.storage_path is not null then
    declare
      storage_size_text text;
      storage_mime text;
      storage_size bigint;
    begin
      select coalesce(metadata ->> 'size', metadata ->> 'contentLength'),
             coalesce(metadata ->> 'mimetype', metadata ->> 'mimeType')
        into storage_size_text, storage_mime
      from storage.objects
      where bucket_id = 'assets' and name = new.storage_path;
      if not found then
        raise exception using errcode = '22023', message = 'Asset storage object not found';
      end if;
      if new.size_bytes is null or new.size_bytes <= 0 then
        raise exception using errcode = '22023', message = 'Storage-backed asset size is required';
      end if;
      if storage_size_text is null or storage_size_text !~ '^\d+$' then
        raise exception using errcode = '22023', message = 'Asset storage size is invalid';
      end if;
      storage_size := storage_size_text::bigint;
      if storage_size > 536870912 or storage_size <> new.size_bytes then
        raise exception using errcode = '22023', message = 'Asset size does not match Storage';
      end if;
      if storage_mime is null or lower(storage_mime) <> lower(new.mime_type) then
        raise exception using errcode = '22023', message = 'Asset MIME type does not match Storage';
      end if;
    end;
  end if;
  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id
        or new.project_id is distinct from old.project_id then
      raise exception using errcode = '22023', message = 'Asset identity and project are immutable';
    end if;
    if (new.storage_path is distinct from old.storage_path
          and not (old.storage_path is null and new.storage_path is not null))
        or old.storage_path is not null and (
          new.size_bytes is distinct from old.size_bytes
          or new.mime_type is distinct from old.mime_type
          or new.checksum is distinct from old.checksum
        ) then
      raise exception using errcode = '22023', message = 'Asset binary fields are immutable';
    end if;
  end if;
  if tg_op = 'INSERT' then
    should_charge := new.storage_path is not null;
  elsif tg_op = 'UPDATE' then
    -- A local-first row may receive its Storage object during reconciliation.
    -- Charge that transition exactly once; existing binary references remain
    -- immutable below.
    should_charge := old.storage_path is null and new.storage_path is not null;
  end if;
  if should_charge then
    perform public.record_workspace_usage(
      new.project_id,
      'assets',
      new.size_bytes,
      public.asset_library_usage_operation(
        'asset-library:add:',
        new.id || ':' || coalesce(new.storage_path, '')
      ),
      jsonb_build_object(
        'assetId', new.id,
        'sizeBytes', new.size_bytes,
        'source', new.source
      )
    );
  end if;
  if new.source_url is not null
      and (
        length(new.source_url) > 2048
        or new.source_url ~ '[[:space:][:cntrl:]]'
        or new.source_url !~* '^https://[^@[:space:]/?#]+([/?#].*)?$'
      ) then
    raise exception using errcode = '22023', message = 'Asset source URL must use HTTPS';
  end if;
  if new.download_url is not null
      and (
        length(new.download_url) > 2048
        or new.download_url ~ '[[:space:][:cntrl:]]'
        or new.download_url !~* '^https://[^@[:space:]/?#]+([/?#].*)?$'
      ) then
    raise exception using errcode = '22023', message = 'Asset download URL must use HTTPS';
  end if;
  if new.preview_url is not null
      and (
        length(new.preview_url) > 2048
        or new.preview_url ~ '[[:space:][:cntrl:]]'
        or new.preview_url !~* '^https://[^@[:space:]/?#]+([/?#].*)?$'
      ) then
    raise exception using errcode = '22023', message = 'Asset preview URL must use HTTPS';
  end if;
  if new.creator_url is not null
      and (
        length(new.creator_url) > 2048
        or new.creator_url ~ '[[:space:][:cntrl:]]'
        or new.creator_url !~* '^https://[^@[:space:]/?#]+([/?#].*)?$'
      ) then
    raise exception using errcode = '22023', message = 'Asset creator URL must use HTTPS';
  end if;
  if new.license_url is not null
      and (
        length(new.license_url) > 2048
        or new.license_url ~ '[[:space:][:cntrl:]]'
        or new.license_url !~* '^https://[^@[:space:]/?#]+([/?#].*)?$'
      ) then
    raise exception using errcode = '22023', message = 'Asset license URL must use HTTPS';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_asset_library_item_boundaries_trigger
  on public.asset_library_items;
create trigger validate_asset_library_item_boundaries_trigger
before insert or update or delete on public.asset_library_items
for each row execute function public.validate_asset_library_item_boundaries();

create or replace function public.audit_asset_library_item_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- A project cascade can remove the parent before its child DELETE trigger
  -- fires. The catalog row still disappears, but an audit row would violate
  -- the audit table's project foreign key, so skip only that cascade case.
  if tg_op = 'DELETE' and not exists (
    select 1 from public.projects where id = old.project_id
  ) then
    return old;
  end if;
  insert into public.workspace_audit_events (project_id, actor_id, action, metadata)
  values (
    case when tg_op = 'DELETE' then old.project_id else new.project_id end,
    coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid),
    case tg_op
      when 'INSERT' then 'asset_library.item.created'
      when 'UPDATE' then 'asset_library.item.updated'
      else 'asset_library.item.deleted'
    end,
    jsonb_build_object(
      'itemId', case when tg_op = 'DELETE' then old.id else new.id end,
      'source', case when tg_op = 'DELETE' then old.source else new.source end,
      'hasStorageObject', case
        when tg_op = 'DELETE' then old.storage_path is not null
        else new.storage_path is not null
      end
    )
  );
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists audit_asset_library_item_change_trigger
  on public.asset_library_items;
create trigger audit_asset_library_item_change_trigger
after insert or update or delete on public.asset_library_items
for each row execute function public.audit_asset_library_item_change();

-- Seed idempotent quota reservations for rows created before this migration.
-- New rows are charged by the boundary trigger above.
insert into public.workspace_usage_ledger (
  project_id,
  category,
  delta,
  operation_id,
  metadata,
  created_by
)
select
  item.project_id,
  'assets',
  item.size_bytes,
  public.asset_library_usage_operation(
    'asset-library:add:',
    item.id || ':' || coalesce(item.storage_path, '')
  ),
  jsonb_build_object(
    'assetId', item.id,
    'sizeBytes', item.size_bytes,
    'source', item.source,
    'backfilled', true
  ),
  coalesce(item.created_by, '00000000-0000-0000-0000-000000000000'::uuid)
from public.asset_library_items item
where item.storage_path is not null
  and item.size_bytes is not null
  and item.size_bytes > 0
on conflict (project_id, category, operation_id) do nothing;

create table if not exists public.asset_library_folders (
  id text not null,
  project_id text not null references public.projects(id) on delete cascade,
  parent_id text,
  name text not null check (
    length(trim(name)) between 1 and 120
    and name !~ '[[:cntrl:]]'
  ),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (project_id, id),
  foreign key (project_id, parent_id)
    references public.asset_library_folders(project_id, id) on delete cascade
);

create or replace function public.validate_asset_library_folder_boundaries()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    return old;
  end if;
  if tg_op = 'INSERT' and auth.uid() is not null then
    new.created_by := auth.uid();
  end if;
  if new.id is null
      or btrim(new.id) = ''
      or new.id <> btrim(new.id)
      or length(new.id) > 256
      or new.id ~ '[[:cntrl:]]'
      or new.project_id is null
      or btrim(new.project_id) = ''
      or new.project_id <> btrim(new.project_id)
      or length(new.project_id) > 256
      or new.project_id = 'drawing-paper'
      or btrim(new.name) = ''
      or new.name <> btrim(new.name)
      or length(new.name) > 120
      or new.name ~ '[[:cntrl:]]'
      or (new.parent_id is not null and (
        new.parent_id <> btrim(new.parent_id)
        or length(new.parent_id) > 256
        or new.parent_id ~ '[[:cntrl:]]'
      ))
      or new.parent_id = new.id then
    raise exception using errcode = '22023', message = 'Asset library folder is invalid';
  end if;
  if tg_op = 'UPDATE' and (
      new.id is distinct from old.id
      or new.project_id is distinct from old.project_id
    ) then
    raise exception using errcode = '22023', message = 'Folder identity and project are immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_asset_library_folder_boundaries_trigger
  on public.asset_library_folders;
create trigger validate_asset_library_folder_boundaries_trigger
before insert or update on public.asset_library_folders
for each row execute function public.validate_asset_library_folder_boundaries();

do $$
begin
  -- Recreate the legacy single-column FK as a composite project-scoped FK.
  -- SET NULL must affect only folder_id; project_id is required.
  if exists (
    select 1 from pg_constraint
    where conname = 'asset_library_items_folder_fk'
      and conrelid = 'public.asset_library_items'::regclass
  ) then
    alter table public.asset_library_items
      drop constraint asset_library_items_folder_fk;
  end if;
  -- Legacy rows can contain a folder ID from another project. Preserve the
  -- asset while dropping that unsafe association before adding the valid
  -- project-scoped constraint.
  update public.asset_library_items item
  set folder_id = null
  where item.folder_id is not null
    and not exists (
      select 1
      from public.asset_library_folders folder
      where folder.project_id = item.project_id
        and folder.id = item.folder_id
    );
  alter table public.asset_library_items
    add constraint asset_library_items_folder_fk
    foreign key (project_id, folder_id)
    references public.asset_library_folders(project_id, id)
    on delete set null (folder_id);
end;
$$;

create or replace function public.validate_asset_library_item_folder()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.folder_id is not null and not exists (
    select 1 from public.asset_library_folders
    where id = new.folder_id and project_id = new.project_id
  ) then
    raise exception using errcode = '22023', message = 'Asset library folder does not belong to project';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_asset_library_item_folder_trigger
  on public.asset_library_items;
create trigger validate_asset_library_item_folder_trigger
before insert or update of project_id, folder_id
on public.asset_library_items
for each row execute function public.validate_asset_library_item_folder();

create table if not exists public.asset_library_favorites (
  project_id text not null references public.projects(id) on delete cascade,
  item_id text not null,
  user_id uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (project_id, item_id, user_id),
  foreign key (project_id, item_id)
    references public.asset_library_items(project_id, id) on delete cascade
);

create table if not exists public.asset_library_usage (
  id bigint generated always as identity primary key,
  project_id text not null references public.projects(id) on delete cascade,
  item_id text not null,
  node_id text,
  user_id uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  foreign key (project_id, item_id)
    references public.asset_library_items(project_id, id) on delete cascade
);

create index if not exists asset_library_items_project_updated_idx
  on public.asset_library_items (project_id, updated_at desc);
create index if not exists asset_library_items_project_kind_idx
  on public.asset_library_items (project_id, kind, updated_at desc);
create index if not exists asset_library_items_project_folder_idx
  on public.asset_library_items (project_id, folder_id, updated_at desc);
create index if not exists asset_library_items_tags_gin_idx
  on public.asset_library_items using gin (tags);
create index if not exists asset_library_folders_project_idx
  on public.asset_library_folders (project_id, parent_id, name);
create unique index if not exists asset_library_folders_case_insensitive_name_idx
  on public.asset_library_folders (project_id, coalesce(parent_id, ''), lower(name));
create unique index if not exists asset_library_items_project_checksum_idx
  on public.asset_library_items (project_id, lower(checksum))
  where checksum is not null;
create index if not exists asset_library_usage_item_idx
  on public.asset_library_usage (project_id, item_id, created_at desc);
create unique index if not exists asset_library_usage_node_event_idx
  on public.asset_library_usage (project_id, item_id, node_id, user_id)
  where node_id is not null;

alter table public.asset_library_items enable row level security;
alter table public.asset_library_folders enable row level security;
alter table public.asset_library_favorites enable row level security;
alter table public.asset_library_usage enable row level security;

revoke all on public.asset_library_items from public, anon, authenticated;
revoke all on public.asset_library_folders from public, anon, authenticated;
revoke all on public.asset_library_favorites from public, anon, authenticated;
revoke all on public.asset_library_usage from public, anon, authenticated;

grant delete on storage.objects to authenticated;

-- The bucket is shared with drawing paper and collaboration assets. Replace the
-- older broad policies with the same project checks plus explicit namespaces;
-- otherwise a user could bypass the UUID-only library path contract by writing
-- directly to storage.objects.
drop policy if exists collaboration_assets_read on storage.objects;
create policy collaboration_assets_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'assets'
    and (
      (
        split_part(name, '/', 1) = 'drawing-paper'
        and split_part(name, '/', 2) <> ''
        and split_part(name, '/', 3) <> ''
      )
      or (
        split_part(name, '/', 1) <> 'drawing-paper'
        and split_part(name, '/', 2) in ('ai', 'collaboration')
      )
      or public.is_asset_library_storage_path(name)
    )
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
    and (
      (
        split_part(name, '/', 1) = 'drawing-paper'
        and split_part(name, '/', 2) <> ''
        and split_part(name, '/', 3) <> ''
      )
      or (
        split_part(name, '/', 1) <> 'drawing-paper'
        and split_part(name, '/', 2) in ('ai', 'collaboration')
      )
      or public.is_asset_library_storage_path(name)
    )
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
    and not public.is_asset_library_storage_path(name)
    and (
      (
        split_part(name, '/', 1) = 'drawing-paper'
        and split_part(name, '/', 2) <> ''
        and split_part(name, '/', 3) <> ''
      )
      or (
        split_part(name, '/', 1) <> 'drawing-paper'
        and split_part(name, '/', 2) in ('ai', 'collaboration')
      )
    )
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
    and not public.is_asset_library_storage_path(name)
    and (
      (
        split_part(name, '/', 1) = 'drawing-paper'
        and split_part(name, '/', 2) <> ''
        and split_part(name, '/', 3) <> ''
      )
      or (
        split_part(name, '/', 1) <> 'drawing-paper'
        and split_part(name, '/', 2) in ('ai', 'collaboration')
      )
    )
    and public.can_edit_project(
      case
        when split_part(name, '/', 1) = 'drawing-paper'
          then split_part(name, '/', 2)
        else split_part(name, '/', 1)
      end
    )
  );

drop policy if exists asset_library_storage_delete on storage.objects;
create policy asset_library_storage_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'assets'
    and public.is_asset_library_storage_path(name)
    and public.can_edit_project(split_part(name, '/', 1))
  );

drop policy if exists asset_library_items_read on public.asset_library_items;
create policy asset_library_items_read on public.asset_library_items
  for select to authenticated
  using (public.can_read_project(project_id));

drop policy if exists asset_library_items_insert on public.asset_library_items;
create policy asset_library_items_insert on public.asset_library_items
  for insert to authenticated
  with check (
    public.can_edit_project(project_id)
    and source <> 'bundled'
  );

drop policy if exists asset_library_items_update on public.asset_library_items;
create policy asset_library_items_update on public.asset_library_items
  for update to authenticated
  using (
    public.can_edit_project(project_id)
    and source <> 'bundled'
  )
  with check (
    public.can_edit_project(project_id)
    and source <> 'bundled'
  );

drop policy if exists asset_library_items_delete on public.asset_library_items;
create policy asset_library_items_delete on public.asset_library_items
  for delete to authenticated
  using (
    public.can_edit_project(project_id)
    and source <> 'bundled'
  );

drop policy if exists asset_library_folders_read on public.asset_library_folders;
create policy asset_library_folders_read on public.asset_library_folders
  for select to authenticated
  using (public.can_read_project(project_id));

drop policy if exists asset_library_folders_write on public.asset_library_folders;
create policy asset_library_folders_write on public.asset_library_folders
  for all to authenticated
  using (public.can_edit_project(project_id))
  with check (public.can_edit_project(project_id));

drop policy if exists asset_library_favorites_read on public.asset_library_favorites;
create policy asset_library_favorites_read on public.asset_library_favorites
  for select to authenticated
  using (user_id = auth.uid() and public.can_read_project(project_id));

drop policy if exists asset_library_favorites_insert on public.asset_library_favorites;
create policy asset_library_favorites_insert on public.asset_library_favorites
  for insert to authenticated
  with check (user_id = auth.uid() and public.can_read_project(project_id));

drop policy if exists asset_library_favorites_update on public.asset_library_favorites;
create policy asset_library_favorites_update on public.asset_library_favorites
  for update to authenticated
  using (user_id = auth.uid() and public.can_read_project(project_id))
  with check (user_id = auth.uid() and public.can_read_project(project_id));

drop policy if exists asset_library_favorites_delete on public.asset_library_favorites;
create policy asset_library_favorites_delete on public.asset_library_favorites
  for delete to authenticated
  using (user_id = auth.uid() and public.can_read_project(project_id));

drop policy if exists asset_library_usage_read on public.asset_library_usage;
create policy asset_library_usage_read on public.asset_library_usage
  for select to authenticated
  using (public.can_read_project(project_id));

create or replace function public.record_asset_library_usage(
  p_project_id text,
  p_item_id text,
  p_node_id text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_project_id is null
      or p_project_id <> btrim(p_project_id)
      or length(trim(coalesce(p_project_id, ''))) < 1
      or length(trim(coalesce(p_project_id, ''))) > 256
      or p_project_id ~ '[[:cntrl:]]'
      or auth.uid() is null
      or not public.can_edit_project(p_project_id) then
    raise exception using errcode = '42501', message = 'Asset library usage access denied';
  end if;
  if p_item_id is null
      or p_item_id <> btrim(p_item_id)
      or length(trim(coalesce(p_item_id, ''))) < 1
      or length(trim(p_item_id)) > 256
      or p_item_id ~ '[[:cntrl:]]'
      or (p_node_id is not null and (
        p_node_id <> btrim(p_node_id)
        or length(trim(p_node_id)) > 256
        or p_node_id ~ '[[:cntrl:]]'
      )) then
    raise exception using errcode = '22023', message = 'Invalid asset library usage identifiers';
  end if;
  if not exists (
    select 1 from public.asset_library_items
    where id = trim(p_item_id) and project_id = p_project_id
  ) then
    raise exception using errcode = '22023', message = 'Asset library item not found';
  end if;
  insert into public.asset_library_usage (project_id, item_id, node_id, user_id)
  values (
    p_project_id,
    trim(p_item_id),
    nullif(trim(coalesce(p_node_id, '')), ''),
    auth.uid()
  )
  on conflict do nothing;
  if not found then
    return false;
  end if;
  perform set_config('asset_library.usage_rpc', 'on', true);
  update public.asset_library_items
  set usage_count = usage_count + 1,
      last_used_at = now(),
      updated_at = now()
  where id = trim(p_item_id) and project_id = p_project_id;
  -- Do not leave the internal trigger marker enabled for a caller-owned
  -- transaction that invokes this function more than once.
  perform set_config('asset_library.usage_rpc', 'off', true);
  return true;
end;
$$;

grant select, delete on public.asset_library_items to authenticated;
grant insert (
  id, project_id, kind, source, status, name, description, creator,
  creator_url, source_url, preview_url, download_url, storage_path, mime_type,
  size_bytes, width, height, duration_ms, checksum, provider_asset_id, license,
  license_url, attribution, folder_id, tags, metadata, updated_at
) on public.asset_library_items to authenticated;
grant update (
  id, project_id, kind, source, status, name, description, creator,
  creator_url, source_url, preview_url, download_url, storage_path, mime_type,
  size_bytes, width, height, duration_ms, checksum, provider_asset_id, license,
  license_url, attribution, folder_id, tags, metadata, updated_at
) on public.asset_library_items to authenticated;
grant select, insert, update, delete on public.asset_library_folders to authenticated;
grant select, insert, update, delete on public.asset_library_favorites to authenticated;
grant select on public.asset_library_usage to authenticated;
grant execute on function public.record_asset_library_usage(text, text, text) to authenticated;
revoke execute on function public.record_asset_library_usage(text, text, text) from public, anon;
