begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'workspace-note-assets',
  'workspace-note-assets',
  false,
  26214400,
  array['image/png', 'image/jpeg', 'image/gif', 'image/webp', 'application/pdf']::text[]
)
on conflict (id) do nothing;

do $bucket_contract$
begin
  if not exists (
    select 1
    from storage.buckets b
    where b.id = 'workspace-note-assets'
      and b.name = 'workspace-note-assets'
      and b.public = false
      and b.file_size_limit = 26214400
      and b.allowed_mime_types = array[
        'image/png', 'image/jpeg', 'image/gif', 'image/webp', 'application/pdf'
      ]::text[]
  ) then
    raise exception 'workspace_note_assets_bucket_contract_mismatch';
  end if;
end;
$bucket_contract$;

create or replace function public.workspace_note_attachment_path(
  p_owner_user_id uuid,
  p_project_id text,
  p_attachment_id uuid
)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog
as $function$
  select case
    when p_project_id is null then
      'private/' || p_owner_user_id::text || '/' || p_attachment_id::text
    else
      'project/' || encode(convert_to(p_project_id, 'UTF8'), 'hex') || '/' || p_attachment_id::text
  end;
$function$;

create table public.workspace_note_attachment_rehome_jobs (
  id uuid primary key default gen_random_uuid(),
  job_kind text not null check (job_kind in ('note_scope_change', 'project_delete')),
  note_id uuid references public.workspace_notes(id) on delete restrict,
  source_project_id text,
  target_project_id text,
  target_owner_user_id uuid not null references auth.users(id) on delete restrict,
  requested_by uuid not null references auth.users(id) on delete restrict,
  status text not null default 'pending'
    check (status in ('pending', 'copying', 'cleanup', 'failed', 'complete')),
  resume_status text check (resume_status in ('copying', 'cleanup')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  available_at timestamptz not null default now(),
  lease_token uuid,
  lease_expires_at timestamptz,
  last_error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (job_kind = 'note_scope_change' and note_id is not null)
    or (job_kind = 'project_delete' and note_id is null and source_project_id is not null)
  )
);
create unique index workspace_note_attachment_rehome_note_active_key
  on public.workspace_note_attachment_rehome_jobs (note_id)
  where job_kind = 'note_scope_change' and status <> 'complete';
create unique index workspace_note_attachment_rehome_project_active_key
  on public.workspace_note_attachment_rehome_jobs (source_project_id)
  where job_kind = 'project_delete' and status <> 'complete';
create index workspace_note_attachment_rehome_ready_idx
  on public.workspace_note_attachment_rehome_jobs (available_at, created_at)
  where status in ('pending', 'copying', 'cleanup');

create table public.workspace_note_attachments (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null references public.workspace_notes(id) on delete restrict,
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  project_id text references public.projects(id) on delete restrict,
  storage_path text not null unique,
  retired_storage_path text,
  original_name text not null check (
    length(btrim(original_name)) between 1 and 255
    and position('/' in original_name) = 0
    and position(chr(92) in original_name) = 0
  ),
  mime_type text,
  size_bytes bigint,
  sha256 text,
  status text not null default 'pending_upload'
    check (status in ('pending_upload', 'ready', 'rehome_pending', 'deleting')),
  rehome_job_id uuid references public.workspace_note_attachment_rehome_jobs(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint workspace_note_attachment_path_matches_scope check (
    storage_path = public.workspace_note_attachment_path(owner_user_id, project_id, id)
  ),
  constraint workspace_note_attachment_verified_metadata check (
    (status = 'pending_upload' and mime_type is null and size_bytes is null and sha256 is null)
    or (
      status in ('ready', 'rehome_pending', 'deleting')
      and mime_type in ('image/png', 'image/jpeg', 'image/gif', 'image/webp', 'application/pdf')
      and size_bytes between 1 and 26214400
      and sha256 ~ '^[0-9a-f]{64}$'
    )
  )
);
create index workspace_note_attachments_note_idx
  on public.workspace_note_attachments (note_id, created_at);
create index workspace_note_attachments_project_idx
  on public.workspace_note_attachments (project_id, note_id)
  where project_id is not null;

create table public.workspace_note_attachment_rehome_items (
  job_id uuid not null references public.workspace_note_attachment_rehome_jobs(id) on delete cascade,
  attachment_id uuid not null references public.workspace_note_attachments(id) on delete restrict,
  source_path text not null,
  target_path text not null,
  expected_sha256 text not null check (expected_sha256 ~ '^[0-9a-f]{64}$'),
  copied_sha256 text check (copied_sha256 is null or copied_sha256 ~ '^[0-9a-f]{64}$'),
  source_removed boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (job_id, attachment_id),
  check (source_path <> target_path)
);

create or replace function public.workspace_note_attachment_guard()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_note public.workspace_notes%rowtype;
begin
  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id
       or new.note_id is distinct from old.note_id
       or new.created_by is distinct from old.created_by
       or new.created_at is distinct from old.created_at
       or new.original_name is distinct from old.original_name then
      raise exception 'workspace_note_attachment_identity_immutable' using errcode = '42501';
    end if;
    if auth.role() <> 'service_role'
       and (new.owner_user_id is distinct from old.owner_user_id
         or new.project_id is distinct from old.project_id
         or new.storage_path is distinct from old.storage_path
         or new.retired_storage_path is distinct from old.retired_storage_path
         or (new.status is distinct from old.status and not (
           old.status = 'ready' and new.status = 'deleting'
         ))
         or new.rehome_job_id is distinct from old.rehome_job_id
         or new.mime_type is distinct from old.mime_type
         or new.size_bytes is distinct from old.size_bytes
         or new.sha256 is distinct from old.sha256) then
      raise exception 'workspace_note_attachment_update_forbidden' using errcode = '42501';
    end if;
  end if;

  select * into v_note
  from public.workspace_notes n
  where n.id = new.note_id;
  if not found then
    raise exception 'workspace_note_attachment_note_missing' using errcode = '23503';
  end if;

  if tg_op = 'INSERT' and (
    new.owner_user_id is distinct from v_note.owner_user_id
    or new.project_id is distinct from v_note.project_id
    or new.status <> 'pending_upload'
    or new.storage_path is distinct from public.workspace_note_attachment_path(
      v_note.owner_user_id, v_note.project_id, new.id
    )
  ) then
    raise exception 'workspace_note_attachment_scope_invalid' using errcode = '42501';
  end if;

  return new;
end;
$function$;
create trigger workspace_note_attachment_guard
  before insert or update on public.workspace_note_attachments
  for each row execute function public.workspace_note_attachment_guard();
revoke all on function public.workspace_note_attachment_guard() from public, anon, authenticated;

create or replace function public.workspace_note_attachment_scope_change_guard()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if (new.project_id is distinct from old.project_id
      or new.owner_user_id is distinct from old.owner_user_id)
     and exists (
       select 1
       from public.workspace_note_attachments a
       where a.note_id = old.id
         and (
           a.project_id is distinct from new.project_id
           or a.owner_user_id is distinct from new.owner_user_id
         )
     ) then
    raise exception 'workspace_note_attachment_rehome_required' using errcode = '40001';
  end if;
  return new;
end;
$function$;
create trigger workspace_note_attachment_scope_change_guard
  before update of project_id, owner_user_id on public.workspace_notes
  for each row execute function public.workspace_note_attachment_scope_change_guard();
revoke all on function public.workspace_note_attachment_scope_change_guard() from public, anon, authenticated;

create or replace function public.workspace_note_attachment_storage_can_read(p_path text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth
as $function$
  select exists (
    select 1
    from public.workspace_note_attachments a
    join public.workspace_notes n on n.id = a.note_id
    where a.storage_path = p_path
      and a.status = 'ready'
      and n.deleted_at is null
      and n.project_id is not distinct from a.project_id
      and n.owner_user_id = a.owner_user_id
      and public.workspace_note_can_read(a.owner_user_id, a.project_id)
  );
$function$;

create or replace function public.workspace_note_attachment_storage_can_upload(p_path text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth
as $function$
  select exists (
    select 1
    from public.workspace_note_attachments a
    join public.workspace_notes n on n.id = a.note_id
    where a.storage_path = p_path
      and a.status = 'pending_upload'
      and n.deleted_at is null
      and n.project_id is not distinct from a.project_id
      and n.owner_user_id = a.owner_user_id
      and public.workspace_note_can_edit(a.owner_user_id, a.project_id)
  );
$function$;

create or replace function public.workspace_note_attachment_storage_can_delete(p_path text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth
as $function$
  select exists (
    select 1
    from public.workspace_note_attachments a
    join public.workspace_notes n on n.id = a.note_id
    where a.storage_path = p_path
      and a.status = 'deleting'
      and n.deleted_at is null
      and n.project_id is not distinct from a.project_id
      and n.owner_user_id = a.owner_user_id
      and public.workspace_note_can_edit(a.owner_user_id, a.project_id)
  );
$function$;
revoke all on function public.workspace_note_attachment_storage_can_read(text) from public, anon;
revoke all on function public.workspace_note_attachment_storage_can_upload(text) from public, anon;
revoke all on function public.workspace_note_attachment_storage_can_delete(text) from public, anon;
grant execute on function public.workspace_note_attachment_storage_can_read(text),
  public.workspace_note_attachment_storage_can_upload(text),
  public.workspace_note_attachment_storage_can_delete(text) to authenticated;

alter table public.workspace_note_attachments enable row level security;
alter table public.workspace_note_attachment_rehome_jobs enable row level security;
alter table public.workspace_note_attachment_rehome_items enable row level security;
create policy workspace_note_attachments_read
  on public.workspace_note_attachments for select to authenticated
  using (
    status = 'ready'
    and public.workspace_note_can_read(owner_user_id, project_id)
    and exists (
      select 1 from public.workspace_notes n
      where n.id = workspace_note_attachments.note_id
        and n.deleted_at is null
        and n.project_id is not distinct from workspace_note_attachments.project_id
        and n.owner_user_id = workspace_note_attachments.owner_user_id
    )
  );
create policy workspace_note_attachment_rehome_jobs_read
  on public.workspace_note_attachment_rehome_jobs for select to authenticated
  using (requested_by = auth.uid());
revoke all on public.workspace_note_attachments,
  public.workspace_note_attachment_rehome_jobs,
  public.workspace_note_attachment_rehome_items
  from public, anon, authenticated;
grant select on public.workspace_note_attachments,
  public.workspace_note_attachment_rehome_jobs to authenticated;

create policy workspace_note_assets_read
  on storage.objects for select to authenticated
  using (
    bucket_id = 'workspace-note-assets'
    and public.workspace_note_attachment_storage_can_read(name)
  );
create policy workspace_note_assets_insert
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'workspace-note-assets'
    and public.workspace_note_attachment_storage_can_upload(name)
  );
create policy workspace_note_assets_delete
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'workspace-note-assets'
    and public.workspace_note_attachment_storage_can_delete(name)
  );

create or replace function public.create_workspace_note_attachment(
  p_note_id uuid,
  p_original_name text
)
returns table (attachment_id uuid, storage_path text)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_note public.workspace_notes%rowtype;
  v_id uuid;
  v_path text;
begin
  if auth.uid() is null or p_note_id is null
     or p_original_name is null
     or length(btrim(p_original_name)) not between 1 and 255
     or position('/' in p_original_name) > 0
     or position(chr(92) in p_original_name) > 0 then
    raise exception 'workspace_note_attachment_input_invalid' using errcode = '22023';
  end if;

  select * into v_note
  from public.workspace_notes n
  where n.id = p_note_id and n.deleted_at is null
  for update;
  if not found or not public.workspace_note_can_edit(v_note.owner_user_id, v_note.project_id) then
    raise exception 'workspace_note_attachment_forbidden' using errcode = '42501';
  end if;

  v_id := gen_random_uuid();
  v_path := public.workspace_note_attachment_path(v_note.owner_user_id, v_note.project_id, v_id);
  insert into public.workspace_note_attachments (
    id, note_id, owner_user_id, project_id, storage_path,
    original_name, status, created_by
  ) values (
    v_id, v_note.id, v_note.owner_user_id, v_note.project_id,
    v_path, btrim(p_original_name), 'pending_upload', auth.uid()
  );
  return query select v_id, v_path;
end;
$function$;

create or replace function public.get_workspace_note_attachment_pending_upload(
  p_attachment_id uuid
)
returns table (
  attachment_id uuid,
  owner_user_id uuid,
  project_id text,
  storage_path text
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
begin
  if auth.role() <> 'service_role' then
    raise exception 'workspace_note_attachment_worker_required' using errcode = '42501';
  end if;
  return query
  select a.id, a.owner_user_id, a.project_id, a.storage_path
  from public.workspace_note_attachments a
  join public.workspace_notes n on n.id = a.note_id
  where a.id = p_attachment_id
    and a.status = 'pending_upload'
    and n.deleted_at is null
    and n.project_id is not distinct from a.project_id
    and n.owner_user_id = a.owner_user_id;
end;
$function$;

create or replace function public.finalize_workspace_note_attachment_upload(
  p_attachment_id uuid,
  p_actor_id uuid,
  p_mime_type text,
  p_size_bytes bigint,
  p_sha256 text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth, storage
as $function$
declare
  v_attachment public.workspace_note_attachments%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception 'workspace_note_attachment_worker_required' using errcode = '42501';
  end if;
  if p_attachment_id is null or p_actor_id is null
     or p_size_bytes is null
     or p_size_bytes < 1
     or p_size_bytes > 26214400
     or p_mime_type not in ('image/png', 'image/jpeg', 'image/gif', 'image/webp', 'application/pdf')
     or p_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'workspace_note_attachment_verification_invalid' using errcode = '22023';
  end if;

  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  select a.* into v_attachment
  from public.workspace_note_attachments a
  join public.workspace_notes n on n.id = a.note_id
  where a.id = p_attachment_id and a.status = 'pending_upload'
    and n.deleted_at is null
    and n.project_id is not distinct from a.project_id
    and n.owner_user_id = a.owner_user_id
    and public.workspace_note_can_edit(a.owner_user_id, a.project_id)
  for update of a;
  if not found then
    raise exception 'workspace_note_attachment_pending_missing' using errcode = 'P0002';
  end if;
  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'workspace-note-assets'
      and o.name = v_attachment.storage_path
  ) then
    raise exception 'workspace_note_attachment_object_missing' using errcode = 'P0002';
  end if;

  update public.workspace_note_attachments
  set mime_type = p_mime_type,
      size_bytes = p_size_bytes,
      sha256 = p_sha256,
      status = 'ready',
      updated_at = now()
  where id = p_attachment_id;
end;
$function$;
revoke all on function public.create_workspace_note_attachment(uuid, text) from public, anon;
grant execute on function public.create_workspace_note_attachment(uuid, text) to authenticated;
revoke all on function public.get_workspace_note_attachment_pending_upload(uuid)
  from public, anon, authenticated;
grant execute on function public.get_workspace_note_attachment_pending_upload(uuid)
  to service_role;
revoke all on function public.finalize_workspace_note_attachment_upload(uuid, uuid, text, bigint, text)
  from public, anon, authenticated;
grant execute on function public.finalize_workspace_note_attachment_upload(uuid, uuid, text, bigint, text)
  to service_role;

create or replace function public.begin_workspace_note_attachment_delete(
  p_note_id uuid,
  p_attachment_id uuid
)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_path text;
  v_status text;
begin
  if auth.uid() is null or p_note_id is null or p_attachment_id is null then
    raise exception 'workspace_note_attachment_delete_invalid' using errcode = '22023';
  end if;
  select a.storage_path, a.status into v_path, v_status
  from public.workspace_note_attachments a
  join public.workspace_notes n on n.id = a.note_id
  where a.id = p_attachment_id
    and a.note_id = p_note_id
    and n.deleted_at is null
    and n.project_id is not distinct from a.project_id
    and n.owner_user_id = a.owner_user_id
    and public.workspace_note_can_edit(a.owner_user_id, a.project_id)
    and a.status in ('ready', 'deleting')
  for update of a;
  if not found then
    raise exception 'workspace_note_attachment_delete_forbidden' using errcode = '42501';
  end if;
  if v_status = 'ready' then
    update public.workspace_note_attachments
    set status = 'deleting', updated_at = now()
    where id = p_attachment_id;
  end if;
  return v_path;
end;
$function$;

create or replace function public.finish_workspace_note_attachment_delete(
  p_note_id uuid,
  p_attachment_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
begin
  if auth.uid() is null or p_note_id is null or p_attachment_id is null then
    raise exception 'workspace_note_attachment_delete_invalid' using errcode = '22023';
  end if;
  delete from public.workspace_note_attachments a
  using public.workspace_notes n
  where a.id = p_attachment_id
    and a.note_id = p_note_id
    and a.status = 'deleting'
    and n.id = a.note_id
    and n.deleted_at is null
    and n.project_id is not distinct from a.project_id
    and n.owner_user_id = a.owner_user_id
    and public.workspace_note_can_edit(a.owner_user_id, a.project_id);
  if not found then
    raise exception 'workspace_note_attachment_delete_forbidden' using errcode = '42501';
  end if;
end;
$function$;
revoke all on function public.begin_workspace_note_attachment_delete(uuid, uuid)
  from public, anon;
revoke all on function public.finish_workspace_note_attachment_delete(uuid, uuid)
  from public, anon;
grant execute on function public.begin_workspace_note_attachment_delete(uuid, uuid),
  public.finish_workspace_note_attachment_delete(uuid, uuid) to authenticated;

create or replace function public.request_workspace_note_attachment_scope_change(
  p_note_id uuid,
  p_target_project_id text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_note public.workspace_notes%rowtype;
  v_target_owner uuid;
  v_job_id uuid;
  v_attachment_count integer;
begin
  if auth.uid() is null or p_note_id is null then
    raise exception 'workspace_note_attachment_scope_change_invalid' using errcode = '22023';
  end if;
  select * into v_note
  from public.workspace_notes n
  where n.id = p_note_id and n.deleted_at is null
  for update;
  if not found then
    raise exception 'workspace_note_missing' using errcode = 'P0002';
  end if;
  if v_note.project_id is null then
    if v_note.owner_user_id <> auth.uid() then
      raise exception 'workspace_note_attachment_scope_change_forbidden' using errcode = '42501';
    end if;
  elsif not public.is_project_owner(v_note.project_id) then
    raise exception 'workspace_note_attachment_scope_change_forbidden' using errcode = '42501';
  end if;
  if p_target_project_id is not null and not public.can_edit_project(p_target_project_id) then
    raise exception 'workspace_note_attachment_scope_change_forbidden' using errcode = '42501';
  end if;
  if p_target_project_id is not distinct from v_note.project_id then
    return null;
  end if;

  select j.id into v_job_id
  from public.workspace_note_attachment_rehome_jobs j
  where j.job_kind = 'note_scope_change'
    and j.note_id = p_note_id
    and j.status <> 'complete';
  if found then return v_job_id; end if;

  select count(*) into v_attachment_count
  from public.workspace_note_attachments a
  where a.note_id = p_note_id;
  if exists (
    select 1 from public.workspace_note_attachments a
    where a.note_id = p_note_id and a.status <> 'ready'
  ) then
    raise exception 'workspace_note_attachment_operation_in_progress' using errcode = '40001';
  end if;

  v_target_owner := case
    when p_target_project_id is null then auth.uid()
    else v_note.owner_user_id
  end;
  if v_attachment_count = 0 then
    update public.workspace_notes
    set project_id = p_target_project_id,
        owner_user_id = v_target_owner,
        folder_id = null,
        updated_at = now()
    where id = p_note_id;
    return null;
  end if;

  insert into public.workspace_note_attachment_rehome_jobs (
    job_kind, note_id, source_project_id, target_project_id,
    target_owner_user_id, requested_by
  ) values (
    'note_scope_change', p_note_id, v_note.project_id, p_target_project_id,
    v_target_owner, auth.uid()
  ) returning id into v_job_id;

  insert into public.workspace_note_attachment_rehome_items (
    job_id, attachment_id, source_path, target_path, expected_sha256
  )
  select v_job_id, a.id, a.storage_path,
         public.workspace_note_attachment_path(v_target_owner, p_target_project_id, a.id),
         a.sha256
  from public.workspace_note_attachments a
  where a.note_id = p_note_id;

  update public.workspace_note_attachments
  set status = 'rehome_pending', rehome_job_id = v_job_id, updated_at = now()
  where note_id = p_note_id;
  return v_job_id;
end;
$function$;
revoke all on function public.request_workspace_note_attachment_scope_change(uuid, text)
  from public, anon;
grant execute on function public.request_workspace_note_attachment_scope_change(uuid, text)
  to authenticated;

create or replace function public.claim_workspace_note_attachment_rehome_jobs(p_limit integer default 10)
returns table (
  id uuid,
  job_kind text,
  note_id uuid,
  source_project_id text,
  target_project_id text,
  target_owner_user_id uuid,
  requested_by uuid,
  status text,
  lease_token uuid
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
begin
  if auth.role() <> 'service_role' then
    raise exception 'workspace_note_attachment_worker_required' using errcode = '42501';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 50 then
    raise exception 'workspace_note_attachment_job_limit_invalid' using errcode = '22023';
  end if;
  return query
  with candidates as (
    select j.id
    from public.workspace_note_attachment_rehome_jobs j
    where j.status in ('pending', 'copying', 'cleanup')
      and j.available_at <= now()
      and (j.lease_expires_at is null or j.lease_expires_at <= now())
    order by j.created_at
    limit p_limit
    for update skip locked
  )
  update public.workspace_note_attachment_rehome_jobs j
  set status = case when j.status = 'pending' then 'copying' else j.status end,
      lease_token = gen_random_uuid(),
      lease_expires_at = now() + interval '5 minutes',
      updated_at = now()
  from candidates c
  where j.id = c.id
  returning j.id, j.job_kind, j.note_id, j.source_project_id,
    j.target_project_id, j.target_owner_user_id, j.requested_by,
    j.status, j.lease_token;
end;
$function$;

create or replace function public.get_workspace_note_attachment_rehome_items(
  p_job_id uuid,
  p_lease_token uuid
)
returns table (
  attachment_id uuid,
  source_path text,
  target_path text,
  expected_sha256 text,
  mime_type text,
  size_bytes bigint
)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
begin
  if auth.role() <> 'service_role' then
    raise exception 'workspace_note_attachment_worker_required' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.workspace_note_attachment_rehome_jobs j
    where j.id = p_job_id and j.lease_token = p_lease_token
      and j.lease_expires_at > now() and j.status in ('copying', 'cleanup')
  ) then
    raise exception 'workspace_note_attachment_job_lease_invalid' using errcode = '40001';
  end if;
  return query
  select i.attachment_id, i.source_path, i.target_path, i.expected_sha256,
    a.mime_type, a.size_bytes
  from public.workspace_note_attachment_rehome_items i
  join public.workspace_note_attachments a on a.id = i.attachment_id
  where i.job_id = p_job_id
  order by i.attachment_id;
end;
$function$;

create or replace function public.mark_workspace_note_attachment_rehome_item_verified(
  p_job_id uuid,
  p_lease_token uuid,
  p_attachment_id uuid,
  p_copied_sha256 text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_expected text;
begin
  if auth.role() <> 'service_role' then
    raise exception 'workspace_note_attachment_worker_required' using errcode = '42501';
  end if;
  select i.expected_sha256 into v_expected
  from public.workspace_note_attachment_rehome_items i
  join public.workspace_note_attachment_rehome_jobs j on j.id = i.job_id
  where i.job_id = p_job_id and i.attachment_id = p_attachment_id
    and j.lease_token = p_lease_token and j.lease_expires_at > now()
    and j.status = 'copying';
  if not found or p_copied_sha256 !~ '^[0-9a-f]{64}$'
     or p_copied_sha256 is distinct from v_expected then
    raise exception 'workspace_note_attachment_copy_verification_failed' using errcode = '22023';
  end if;
  update public.workspace_note_attachment_rehome_items
  set copied_sha256 = p_copied_sha256, updated_at = now()
  where job_id = p_job_id and attachment_id = p_attachment_id;
end;
$function$;

create or replace function public.commit_workspace_note_attachment_rehome(
  p_job_id uuid,
  p_lease_token uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_job public.workspace_note_attachment_rehome_jobs%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception 'workspace_note_attachment_worker_required' using errcode = '42501';
  end if;
  select * into v_job
  from public.workspace_note_attachment_rehome_jobs j
  where j.id = p_job_id and j.lease_token = p_lease_token
    and j.lease_expires_at > now() and j.status = 'copying'
  for update;
  if not found then
    raise exception 'workspace_note_attachment_job_lease_invalid' using errcode = '40001';
  end if;
  if exists (
    select 1 from public.workspace_note_attachment_rehome_items i
    where i.job_id = p_job_id
      and (i.copied_sha256 is null or i.copied_sha256 is distinct from i.expected_sha256)
  ) then
    raise exception 'workspace_note_attachment_copy_incomplete' using errcode = '40001';
  end if;

  update public.workspace_note_attachments a
  set owner_user_id = v_job.target_owner_user_id,
      project_id = v_job.target_project_id,
      storage_path = i.target_path,
      retired_storage_path = i.source_path,
      status = 'rehome_pending',
      updated_at = now()
  from public.workspace_note_attachment_rehome_items i
  where i.job_id = p_job_id and i.attachment_id = a.id;

  if v_job.job_kind = 'note_scope_change' then
    perform set_config('request.jwt.claim.sub', v_job.requested_by::text, true);
    update public.workspace_notes
    set owner_user_id = v_job.target_owner_user_id,
        project_id = v_job.target_project_id,
        folder_id = null,
        updated_at = now()
    where id = v_job.note_id;
    if not found then
      raise exception 'workspace_note_missing' using errcode = 'P0002';
    end if;
  end if;

  update public.workspace_note_attachment_rehome_jobs
  set status = 'cleanup', updated_at = now()
  where id = p_job_id;
end;
$function$;

create or replace function public.mark_workspace_note_attachment_rehome_source_removed(
  p_job_id uuid,
  p_lease_token uuid,
  p_attachment_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
begin
  if auth.role() <> 'service_role' then
    raise exception 'workspace_note_attachment_worker_required' using errcode = '42501';
  end if;
  update public.workspace_note_attachment_rehome_items i
  set source_removed = true, updated_at = now()
  from public.workspace_note_attachment_rehome_jobs j
  where i.job_id = p_job_id and i.attachment_id = p_attachment_id
    and j.id = i.job_id and j.lease_token = p_lease_token
    and j.lease_expires_at > now() and j.status = 'cleanup';
  if not found then
    raise exception 'workspace_note_attachment_job_lease_invalid' using errcode = '40001';
  end if;
end;
$function$;

create or replace function public.complete_workspace_note_attachment_rehome_cleanup(
  p_job_id uuid,
  p_lease_token uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_job public.workspace_note_attachment_rehome_jobs%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception 'workspace_note_attachment_worker_required' using errcode = '42501';
  end if;
  select * into v_job
  from public.workspace_note_attachment_rehome_jobs j
  where j.id = p_job_id and j.lease_token = p_lease_token
    and j.lease_expires_at > now() and j.status = 'cleanup'
  for update;
  if not found then
    raise exception 'workspace_note_attachment_job_lease_invalid' using errcode = '40001';
  end if;
  if exists (
    select 1 from public.workspace_note_attachment_rehome_items i
    where i.job_id = p_job_id and not i.source_removed
  ) then
    raise exception 'workspace_note_attachment_cleanup_incomplete' using errcode = '40001';
  end if;

  update public.workspace_note_attachments a
  set status = 'ready', retired_storage_path = null,
      rehome_job_id = null, updated_at = now()
  from public.workspace_note_attachment_rehome_items i
  where i.job_id = p_job_id and i.attachment_id = a.id;

  if v_job.job_kind = 'project_delete' then
    perform set_config('request.jwt.claim.sub', v_job.requested_by::text, true);
    delete from public.projects p where p.id = v_job.source_project_id;
    if not found then
      raise exception 'workspace_note_project_missing' using errcode = 'P0002';
    end if;
  end if;

  update public.workspace_note_attachment_rehome_jobs
  set status = 'complete', lease_token = null, lease_expires_at = null,
      last_error_code = null, updated_at = now()
  where id = p_job_id;
end;
$function$;

create or replace function public.record_workspace_note_attachment_rehome_failure(
  p_job_id uuid,
  p_lease_token uuid,
  p_error_code text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_attempt integer;
  v_job_status text;
begin
  if auth.role() <> 'service_role' then
    raise exception 'workspace_note_attachment_worker_required' using errcode = '42501';
  end if;
  if p_error_code is null or p_error_code !~ '^[A-Z0-9_]{1,64}$' then
    raise exception 'workspace_note_attachment_error_code_invalid' using errcode = '22023';
  end if;
  select attempt_count, status into v_attempt, v_job_status
  from public.workspace_note_attachment_rehome_jobs j
  where j.id = p_job_id and j.lease_token = p_lease_token
    and j.lease_expires_at > now()
  for update;
  if not found or v_job_status not in ('copying', 'cleanup') then
    raise exception 'workspace_note_attachment_job_lease_invalid' using errcode = '40001';
  end if;
  v_attempt := v_attempt + 1;
  update public.workspace_note_attachment_rehome_jobs
  set attempt_count = v_attempt,
      status = case
        when v_attempt >= 8 then 'failed'
        when v_job_status = 'cleanup' then 'cleanup'
        else 'pending'
      end,
      resume_status = case when v_attempt >= 8 then v_job_status else null end,
      available_at = now() + make_interval(secs => least(3600, (30 * (2 ^ least(v_attempt, 7))::integer))),
      lease_token = null,
      lease_expires_at = null,
      last_error_code = p_error_code,
      updated_at = now()
  where id = p_job_id;
end;
$function$;

create or replace function public.retry_workspace_note_attachment_rehome(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
begin
  if auth.uid() is null or not exists (
    select 1 from public.workspace_note_attachment_rehome_jobs j
    where j.id = p_job_id and j.requested_by = auth.uid() and j.status = 'failed'
  ) then
    raise exception 'workspace_note_attachment_retry_forbidden' using errcode = '42501';
  end if;
  update public.workspace_note_attachment_rehome_jobs
  set status = coalesce(resume_status, 'copying'), resume_status = null,
      attempt_count = 0, available_at = now(),
      last_error_code = null, updated_at = now()
  where id = p_job_id;
end;
$function$;

create or replace function public.rehome_workspace_notes_before_project_delete()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_job_id uuid;
begin
  if exists (
    select 1 from public.workspace_note_attachments a
    where a.project_id = old.id
  ) then
    select j.id into v_job_id
    from public.workspace_note_attachment_rehome_jobs j
    where j.job_kind = 'project_delete'
      and j.source_project_id = old.id
      and j.status <> 'complete';
    if found then return null; end if;

    if old.owner_id is null then
      raise exception 'Cannot delete project with Notes attachments and no owner';
    end if;
    if exists (
      select 1 from public.workspace_note_attachments a
      where a.project_id = old.id and a.status <> 'ready'
    ) then
      raise exception 'workspace_note_attachment_operation_in_progress' using errcode = '40001';
    end if;

    insert into public.workspace_note_attachment_rehome_jobs (
      job_kind, source_project_id, target_project_id,
      target_owner_user_id, requested_by
    ) values (
      'project_delete', old.id, null, old.owner_id, old.owner_id
    ) returning id into v_job_id;

    insert into public.workspace_note_attachment_rehome_items (
      job_id, attachment_id, source_path, target_path, expected_sha256
    )
    select v_job_id, a.id, a.storage_path,
      public.workspace_note_attachment_path(old.owner_id, null, a.id), a.sha256
    from public.workspace_note_attachments a
    where a.project_id = old.id;

    update public.workspace_note_attachments
    set status = 'rehome_pending', rehome_job_id = v_job_id, updated_at = now()
    where project_id = old.id;
    return null;
  end if;

  if exists (select 1 from public.workspace_notes where project_id = old.id)
     or exists (select 1 from public.workspace_note_folders where project_id = old.id)
     or exists (select 1 from public.workspace_note_templates where project_id = old.id)
     or exists (select 1 from public.workspace_note_canvas_boards where project_id = old.id) then
    if old.owner_id is null then
      raise exception 'Cannot delete project with linked Notes or Canvas records and no owner';
    end if;

    update public.workspace_notes project_daily
    set deleted_at = now(), updated_at = now()
    where project_daily.project_id = old.id
      and project_daily.daily_note_date is not null
      and project_daily.deleted_at is null
      and exists (
        select 1
        from public.workspace_notes private_daily
        where private_daily.project_id is null
          and private_daily.owner_user_id = old.owner_id
          and private_daily.daily_note_date = project_daily.daily_note_date
          and private_daily.deleted_at is null
      );

    update public.workspace_notes
    set project_id = null, folder_id = null, owner_user_id = old.owner_id
    where project_id = old.id;
    update public.workspace_note_folders
    set project_id = null, parent_folder_id = null, owner_user_id = old.owner_id
    where project_id = old.id;
    update public.workspace_note_templates
    set project_id = null, owner_user_id = old.owner_id,
        revision = revision + 1, updated_at = now()
    where project_id = old.id;
    update public.workspace_note_canvas_boards
    set project_id = null, owner_user_id = old.owner_id,
        revision = revision + 1, updated_at = now()
    where project_id = old.id;
  end if;
  return old;
end;
$function$;

create or replace function public.request_workspace_note_project_delete(
  p_project_id text
)
returns table (status text, job_id uuid)
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $function$
declare
  v_owner uuid;
  v_deleted_project_id text;
  v_job_id uuid;
  v_job_status text;
begin
  if auth.uid() is null or p_project_id is null or length(btrim(p_project_id)) = 0 then
    raise exception 'workspace_note_project_delete_invalid' using errcode = '22023';
  end if;

  select p.owner_id into v_owner
  from public.projects p
  where p.id = p_project_id
  for update;
  if not found then
    select j.id, j.status into v_job_id, v_job_status
    from public.workspace_note_attachment_rehome_jobs j
    where j.job_kind = 'project_delete'
      and j.source_project_id = p_project_id
      and j.requested_by = auth.uid()
    order by j.created_at desc
    limit 1;
    if found then
      return query select v_job_status, v_job_id;
      return;
    end if;
    raise exception 'workspace_note_project_missing' using errcode = 'P0002';
  end if;
  if v_owner is distinct from auth.uid() then
    raise exception 'workspace_note_project_delete_forbidden' using errcode = '42501';
  end if;

  delete from public.projects p
  where p.id = p_project_id
  returning p.id into v_deleted_project_id;
  if v_deleted_project_id is not null then
    insert into public.workspace_note_attachment_rehome_jobs (
      job_kind, source_project_id, target_project_id,
      target_owner_user_id, requested_by, status
    ) values (
      'project_delete', p_project_id, null, v_owner, auth.uid(), 'complete'
    ) returning id into v_job_id;
    return query select 'complete'::text, v_job_id;
    return;
  end if;

  select j.id, j.status into v_job_id, v_job_status
  from public.workspace_note_attachment_rehome_jobs j
  where j.job_kind = 'project_delete'
    and j.source_project_id = p_project_id
    and j.requested_by = auth.uid()
    and j.status <> 'complete'
  order by j.created_at desc
  limit 1;
  if found then
    return query select v_job_status, v_job_id;
    return;
  end if;

  raise exception 'workspace_note_project_delete_state_missing' using errcode = '40001';
end;
$function$;
revoke all on function public.request_workspace_note_project_delete(text)
  from public, anon;
grant execute on function public.request_workspace_note_project_delete(text)
  to authenticated;

revoke all on function public.claim_workspace_note_attachment_rehome_jobs(integer)
  from public, anon, authenticated;
revoke all on function public.get_workspace_note_attachment_rehome_items(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.mark_workspace_note_attachment_rehome_item_verified(uuid, uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.commit_workspace_note_attachment_rehome(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.mark_workspace_note_attachment_rehome_source_removed(uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.complete_workspace_note_attachment_rehome_cleanup(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.record_workspace_note_attachment_rehome_failure(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.claim_workspace_note_attachment_rehome_jobs(integer),
  public.get_workspace_note_attachment_rehome_items(uuid, uuid),
  public.mark_workspace_note_attachment_rehome_item_verified(uuid, uuid, uuid, text),
  public.commit_workspace_note_attachment_rehome(uuid, uuid),
  public.mark_workspace_note_attachment_rehome_source_removed(uuid, uuid, uuid),
  public.complete_workspace_note_attachment_rehome_cleanup(uuid, uuid),
  public.record_workspace_note_attachment_rehome_failure(uuid, uuid, text)
  to service_role;
revoke all on function public.retry_workspace_note_attachment_rehome(uuid) from public, anon;
grant execute on function public.retry_workspace_note_attachment_rehome(uuid) to authenticated;

create schema if not exists vault;
create extension if not exists pg_cron;
create extension if not exists pg_net;
create extension if not exists supabase_vault with schema vault;

select cron.schedule(
  'notes-attachment-rehome',
  '* * * * *',
  $command$
    select net.http_post(
      url := rtrim(project_url.decrypted_secret, '/') || '/functions/v1/notes-attachment-rehome',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', public_key.decrypted_secret,
        'Authorization', 'Bearer ' || public_key.decrypted_secret,
        'x-notes-attachment-worker-secret', worker_secret.decrypted_secret
      ),
      body := '{"action":"process_rehome_jobs"}'::jsonb,
      timeout_milliseconds := 10000
    )
    from vault.decrypted_secrets project_url
    cross join vault.decrypted_secrets public_key
    cross join vault.decrypted_secrets worker_secret
    where project_url.name = 'notes_attachment_project_url'
      and public_key.name = 'notes_attachment_anon_key'
      and worker_secret.name = 'notes_attachment_worker_secret'
      and project_url.decrypted_secret ~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?$'
      and length(public_key.decrypted_secret) > 0
      and length(worker_secret.decrypted_secret) >= 16
  $command$
);

commit;
