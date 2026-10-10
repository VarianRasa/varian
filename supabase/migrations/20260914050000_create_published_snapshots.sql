alter table public.comments
  add column if not exists feedback_thread_id text,
  add column if not exists edited_at timestamptz,
  add column if not exists attachments jsonb not null default '[]'::jsonb,
  add column if not exists labels jsonb not null default '[]'::jsonb,
  add column if not exists assignee_id text,
  add column if not exists assignee_name text,
  add column if not exists due_date timestamptz,
  add column if not exists watchers jsonb not null default '[]'::jsonb;

create table if not exists public.published_snapshots (
  id text primary key,
  project_id text not null references public.projects(id) on delete cascade,
  version integer not null check (version > 0),
  document_data jsonb not null,
  published_by text not null,
  published_at timestamptz not null,
  expires_at timestamptz,
  access text not null check (access in ('link', 'password', 'private')),
  download_policy text not null check (
    download_policy in ('allowed', 'disabled', 'exportOnly')
  ),
  embed_enabled boolean not null default false,
  watermark_enabled boolean not null default false,
  password_digest text,
  content_hash text not null,
  created_at timestamptz not null default now(),
  unique (project_id, version),
  check (jsonb_typeof(document_data) = 'object'),
  check (
    password_digest is null
    or password_digest ~ '^[0-9a-fA-F]{64}$'
  ),
  check (
    (access = 'password' and password_digest is not null)
    or (access <> 'password' and password_digest is null)
  )
);

alter table public.share_links
  add column if not exists published_snapshot_id text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'share_links_published_snapshot_id_fkey'
      and conrelid = 'public.share_links'::regclass
  ) then
    alter table public.share_links
      add constraint share_links_published_snapshot_id_fkey
      foreign key (published_snapshot_id)
      references public.published_snapshots(id)
      on delete cascade;
  end if;
end;
$$;

create index if not exists published_snapshots_project_version_idx
  on public.published_snapshots (project_id, version desc);

create index if not exists share_links_published_snapshot_idx
  on public.share_links (published_snapshot_id)
  where published_snapshot_id is not null;

alter table public.published_snapshots enable row level security;

drop policy if exists published_snapshots_owner_read
  on public.published_snapshots;

create policy published_snapshots_owner_read on public.published_snapshots
  for select to authenticated
  using (public.is_project_owner(project_id));

revoke all on public.published_snapshots from anon;
grant select on public.published_snapshots to authenticated;

create or replace function public.publish_canvas_snapshot(
  p_project_id text,
  p_snapshot_id text,
  p_version integer,
  p_document_data jsonb,
  p_published_by text,
  p_published_at timestamptz,
  p_expires_at timestamptz,
  p_access text,
  p_download_policy text,
  p_embed_enabled boolean,
  p_watermark_enabled boolean,
  p_password_digest text,
  p_content_hash text,
  p_token_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_share_link_id uuid;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message =
      'Sign in is required before publishing a canvas snapshot.';
  end if;
  if not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message =
      'Only the project owner can publish a canvas snapshot';
  end if;
  if p_snapshot_id is null or length(trim(p_snapshot_id)) = 0 then
    raise exception using errcode = '22023', message =
      'Published snapshot ID is required';
  end if;
  if p_version is null or p_version <= 0 then
    raise exception using errcode = '22023', message =
      'Published snapshot version must be positive';
  end if;
  if p_document_data is null or jsonb_typeof(p_document_data) <> 'object' then
    raise exception using errcode = '22023', message =
      'Published snapshot document is invalid';
  end if;
  if p_access is null or p_access not in ('link', 'password', 'private') then
    raise exception using errcode = '22023', message =
      'Published snapshot access policy is invalid';
  end if;
  if p_download_policy is null
      or p_download_policy not in ('allowed', 'disabled', 'exportOnly') then
    raise exception using errcode = '22023', message =
      'Published snapshot download policy is invalid';
  end if;
  if p_content_hash is null or length(trim(p_content_hash)) <> 64 then
    raise exception using errcode = '22023', message =
      'Published snapshot content hash is invalid';
  end if;
  if p_access = 'password' then
    if p_password_digest is null
        or lower(trim(p_password_digest)) !~ '^[0-9a-f]{64}$' then
      raise exception using errcode = '22023', message =
        'Password digest is required for protected snapshots';
    end if;
  elsif p_password_digest is not null then
    raise exception using errcode = '22023', message =
      'Password digest is only valid for protected snapshots';
  end if;
  if p_access = 'private' and p_token_hash is not null then
    raise exception using errcode = '22023', message =
      'Private snapshots cannot have a share token';
  end if;
  if p_access <> 'private' then
    if p_token_hash is null
        or lower(trim(p_token_hash)) !~ '^[0-9a-f]{64}$' then
      raise exception using errcode = '22023', message =
        'A share token is required for public snapshots';
    end if;
  end if;

  insert into public.published_snapshots (
    id,
    project_id,
    version,
    document_data,
    published_by,
    published_at,
    expires_at,
    access,
    download_policy,
    embed_enabled,
    watermark_enabled,
    password_digest,
    content_hash
  ) values (
    trim(p_snapshot_id),
    p_project_id,
    p_version,
    p_document_data,
    coalesce(nullif(trim(p_published_by), ''), auth.uid()::text),
    coalesce(p_published_at, now()),
    p_expires_at,
    p_access,
    p_download_policy,
    coalesce(p_embed_enabled, false),
    coalesce(p_watermark_enabled, false),
    case when p_password_digest is null then null
      else lower(trim(p_password_digest)) end,
    lower(trim(p_content_hash))
  );

  if p_access = 'private' then
    update public.share_links
    set revoked_at = now()
    where project_id = p_project_id
      and revoked_at is null;
  else
    insert into public.share_links (
      project_id,
      token_hash,
      expires_at,
      created_by,
      published_snapshot_id
    ) values (
      p_project_id,
      lower(trim(p_token_hash)),
      p_expires_at,
      auth.uid(),
      trim(p_snapshot_id)
    ) returning id into v_share_link_id;
  end if;

  update public.projects
  set is_shared = p_access <> 'private',
      updated_at = now(),
      updated_by = auth.uid()
  where id = p_project_id;

  return jsonb_build_object(
    'snapshot_id', trim(p_snapshot_id),
    'share_link_id', v_share_link_id
  );
end;
$$;

revoke execute on function public.publish_canvas_snapshot(
  text,
  text,
  integer,
  jsonb,
  text,
  timestamptz,
  timestamptz,
  text,
  text,
  boolean,
  boolean,
  text,
  text,
  text
) from public, anon;

grant execute on function public.publish_canvas_snapshot(
  text,
  text,
  integer,
  jsonb,
  text,
  timestamptz,
  timestamptz,
  text,
  text,
  boolean,
  boolean,
  text,
  text,
  text
) to authenticated;

create or replace function public.read_canvas_share(
  p_project_id text,
  p_token_hash text,
  p_password_digest text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_project_shared boolean;
  v_link_snapshot_id text;
  v_link_expires_at timestamptz;
  v_snapshot public.published_snapshots%rowtype;
  v_state jsonb;
  v_document jsonb;
  v_comments jsonb;
  v_result jsonb;
begin
  if p_token_hash is null
      or lower(trim(p_token_hash)) !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '42501', message =
      'Invalid or expired canvas share link';
  end if;
  if p_password_digest is not null
      and lower(trim(p_password_digest)) !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '42501', message =
      'Invalid or expired canvas share link';
  end if;

  select
    project.is_shared,
    link.published_snapshot_id,
    link.expires_at
  into
    v_project_shared,
    v_link_snapshot_id,
    v_link_expires_at
  from public.projects project
  join public.share_links link on link.project_id = project.id
  where project.id = p_project_id
    and link.token_hash = lower(trim(p_token_hash))
    and link.revoked_at is null
    and (link.expires_at is null or link.expires_at > now())
  limit 1;

  if not found or not coalesce(v_project_shared, false) then
    raise exception using errcode = '42501', message =
      'Invalid or expired canvas share link';
  end if;

  if v_link_snapshot_id is not null then
    select *
    into v_snapshot
    from public.published_snapshots snapshot
    where snapshot.id = v_link_snapshot_id
      and snapshot.project_id = p_project_id;

    if not found then
      raise exception using errcode = '42501', message =
        'Invalid or expired canvas share link';
    end if;
    if v_snapshot.access = 'private'
        or (v_snapshot.expires_at is not null
            and v_snapshot.expires_at <= now())
        or (v_link_expires_at is not null
            and v_link_expires_at <= now()) then
      raise exception using errcode = '42501', message =
        'Invalid or expired canvas share link';
    end if;

    if v_snapshot.access = 'password'
        and (p_password_digest is null
          or v_snapshot.password_digest <> lower(trim(p_password_digest))) then
      return jsonb_build_object(
        'requiresPassword', true,
        'snapshotId', v_snapshot.id
      );
    end if;

    return jsonb_build_object(
      'projectId', v_snapshot.project_id,
      'document', v_snapshot.document_data,
      'comments', '[]'::jsonb,
      'crdt', '{}'::jsonb,
      'snapshotId', v_snapshot.id,
      'version', v_snapshot.version,
      'access', v_snapshot.access,
      'downloadPolicy', v_snapshot.download_policy,
      'embedEnabled', v_snapshot.embed_enabled,
      'watermarkEnabled', v_snapshot.watermark_enabled
    );
  end if;

  select
    crdt.state_json,
    snapshot.document_data
  into
    v_state,
    v_document
  from public.projects project
  left join public.canvas_crdt_snapshots crdt
    on crdt.project_id = project.id
  left join public.canvas_snapshots snapshot
    on snapshot.project_id = project.id
  where project.id = p_project_id
  limit 1;

  if v_state -> 'document' is not null then
    v_document := v_state -> 'document';
    v_comments := coalesce(v_state -> 'comments', '[]'::jsonb);
  else
    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', comment.id,
          'feedbackThreadId', comment.feedback_thread_id,
          'nodeId', comment.node_id,
          'authorId', comment.author_id,
          'authorName', comment.author_name,
          'text', comment.text,
          'x', comment.x,
          'y', comment.y,
          'resolved', comment.resolved,
          'createdAt', comment.created_at,
          'editedAt', comment.edited_at,
          'replies', comment.replies,
          'mentions', comment.mentions,
          'reactions', comment.reactions,
          'attachments', comment.attachments,
          'labels', comment.labels,
          'assigneeId', comment.assignee_id,
          'assigneeName', comment.assignee_name,
          'dueDate', comment.due_date,
          'watchers', comment.watchers
        ) order by comment.created_at
      ),
      '[]'::jsonb
    )
    into v_comments
    from public.comments comment
    where comment.project_id = p_project_id;
  end if;

  if v_document is null then
    raise exception using errcode = '42501', message =
      'Invalid or expired canvas share link';
  end if;

  v_result := jsonb_build_object(
    'projectId', p_project_id,
    'document', v_document,
    'comments', coalesce(v_comments, '[]'::jsonb),
    'crdt', coalesce(v_state -> 'crdt', '{}'::jsonb)
  );
  return v_result;
end;
$$;

create or replace function public.read_canvas_share(
  p_project_id text,
  p_token_hash text
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.read_canvas_share(p_project_id, p_token_hash, null);
$$;

revoke execute on function public.read_canvas_share(text, text, text)
from public;
grant execute on function public.read_canvas_share(text, text, text)
to anon, authenticated;

revoke execute on function public.read_canvas_share(text, text)
from public;
grant execute on function public.read_canvas_share(text, text)
to anon, authenticated;
