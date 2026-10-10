-- Durable collaboration state for authenticated Canvas rooms.
-- This migration is additive. It does not rewrite the original public sync tables.

alter table public.projects
  add column if not exists owner_id uuid,
  add column if not exists updated_by uuid;

alter table public.canvas_snapshots
  add column if not exists revision bigint not null default 0,
  add column if not exists version_vector jsonb not null default '{}'::jsonb,
  add column if not exists updated_by uuid;

alter table public.comments
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists updated_by uuid,
  -- Collaboration snapshots include these review fields before the dedicated
  -- metadata migrations run later in the migration sequence.
  add column if not exists feedback_thread_id text,
  add column if not exists edited_at timestamptz;

create table if not exists public.workspace_members (
  project_id text not null references public.projects(id) on delete cascade,
  user_id uuid not null,
  role text not null check (role in ('owner', 'editor', 'commenter', 'viewer')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (project_id, user_id)
);

create table if not exists public.canvas_crdt_snapshots (
  project_id text primary key references public.projects(id) on delete cascade,
  state_json jsonb not null,
  version_vector jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid
);

create table if not exists public.canvas_crdt_operations (
  project_id text not null references public.projects(id) on delete cascade,
  op_id text not null,
  actor_id text not null,
  actor_counter bigint not null check (actor_counter > 0),
  dependencies jsonb not null default '{}'::jsonb,
  operation_json jsonb not null,
  auth_user_id uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (project_id, op_id),
  unique (project_id, actor_id, actor_counter)
);

create table if not exists public.canvas_collaboration_checkpoints (
  project_id text not null references public.projects(id) on delete cascade,
  user_id uuid not null,
  version_vector jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (project_id, user_id)
);

create table if not exists public.share_links (
  id uuid primary key default gen_random_uuid(),
  project_id text not null references public.projects(id) on delete cascade,
  token_hash text not null unique,
  role text not null default 'viewer' check (role = 'viewer'),
  expires_at timestamptz,
  revoked_at timestamptz,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now()
);

create index if not exists canvas_crdt_operations_project_created_idx
  on public.canvas_crdt_operations (project_id, created_at, op_id);
create index if not exists canvas_crdt_operations_project_actor_counter_idx
  on public.canvas_crdt_operations (project_id, actor_id, actor_counter);
create index if not exists workspace_members_user_project_idx
  on public.workspace_members (user_id, project_id);
create index if not exists share_links_project_active_idx
  on public.share_links (project_id, revoked_at, expires_at);

create or replace function public.project_role(p_project_id text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p.owner_id = auth.uid() then 'owner'
    else (
      select wm.role
      from public.workspace_members wm
      where wm.project_id = p.id
        and wm.user_id = auth.uid()
    )
  end
  from public.projects p
  where p.id = p_project_id;
$$;

create or replace function public.claim_canvas_project_ownership(p_project_id text)
returns public.projects
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.projects;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  update public.projects
  set owner_id = auth.uid(),
      updated_by = auth.uid(),
      updated_at = now()
  where id = p_project_id
    and owner_id is null
  returning * into result;

  if result.id is null then
    raise exception using errcode = '42501', message = 'Project ownership cannot be claimed';
  end if;
  return result;
end;
$$;

grant execute on function public.claim_canvas_project_ownership(text)
to authenticated;

create or replace function public.can_read_project(p_project_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
    and public.project_role(p_project_id) is not null;
$$;

create or replace function public.can_comment_project(p_project_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.project_role(p_project_id) in ('owner', 'editor', 'commenter');
$$;

create or replace function public.can_edit_project(p_project_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.project_role(p_project_id) in ('owner', 'editor');
$$;

create or replace function public.is_project_owner(p_project_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.project_role(p_project_id) = 'owner';
$$;

create or replace function public.set_canvas_member_role(
  p_project_id text,
  p_user_id uuid,
  p_role text
)
returns public.workspace_members
language plpgsql
security invoker
set search_path = public
as $$
declare
  result public.workspace_members;
begin
  if not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can manage members';
  end if;
  if p_user_id is null
      or p_role is null
      or p_user_id = auth.uid()
      or p_role not in ('editor', 'commenter', 'viewer') then
    raise exception using errcode = '22023', message = 'Invalid member role';
  end if;

  insert into public.workspace_members (project_id, user_id, role)
  values (p_project_id, p_user_id, p_role)
  on conflict (project_id, user_id) do update
    set role = excluded.role,
        updated_at = now()
  returning * into result;
  return result;
end;
$$;

grant execute on function public.set_canvas_member_role(text, uuid, text)
to authenticated;

create or replace function public.remove_canvas_member(
  p_project_id text,
  p_user_id uuid
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can manage members';
  end if;
  delete from public.workspace_members
  where project_id = p_project_id
    and user_id = p_user_id;
end;
$$;

grant execute on function public.remove_canvas_member(text, uuid)
to authenticated;

alter table public.workspace_members enable row level security;
alter table public.canvas_crdt_snapshots enable row level security;
alter table public.canvas_crdt_operations enable row level security;
alter table public.canvas_collaboration_checkpoints enable row level security;
alter table public.share_links enable row level security;

-- Remove the prototype's table-wide anonymous access before granting the
-- authenticated project-scoped policies below.
drop policy if exists projects_public_access on public.projects;
drop policy if exists canvas_snapshots_public_access on public.canvas_snapshots;
drop policy if exists comments_public_access on public.comments;
revoke all on public.projects from anon;
revoke all on public.canvas_snapshots from anon;
revoke all on public.comments from anon;

create policy projects_member_read on public.projects
  for select to authenticated
  using (public.can_read_project(id));

create policy projects_owner_insert on public.projects
  for insert to authenticated
  with check (owner_id = auth.uid());

create policy projects_owner_update on public.projects
  for update to authenticated
  using (public.is_project_owner(id))
  with check (public.is_project_owner(id));

create policy projects_owner_delete on public.projects
  for delete to authenticated
  using (public.is_project_owner(id));

create policy workspace_members_member_read on public.workspace_members
  for select to authenticated
  using (public.can_read_project(project_id));

create policy workspace_members_owner_write on public.workspace_members
  for all to authenticated
  using (public.is_project_owner(project_id))
  with check (public.is_project_owner(project_id));

create policy canvas_snapshots_member_read on public.canvas_snapshots
  for select to authenticated
  using (public.can_read_project(project_id));

create policy canvas_snapshots_editor_write on public.canvas_snapshots
  for all to authenticated
  using (public.can_edit_project(project_id))
  with check (public.can_edit_project(project_id));

create policy comments_member_read on public.comments
  for select to authenticated
  using (public.can_read_project(project_id));

create policy comments_commenter_write on public.comments
  for insert to authenticated
  with check (public.can_comment_project(project_id));

create policy comments_commenter_update on public.comments
  for update to authenticated
  using (public.can_comment_project(project_id))
  with check (public.can_comment_project(project_id));

create policy comments_editor_delete on public.comments
  for delete to authenticated
  using (public.can_edit_project(project_id));

create policy canvas_crdt_snapshot_member_read on public.canvas_crdt_snapshots
  for select to authenticated
  using (public.can_read_project(project_id));

create policy canvas_crdt_snapshot_editor_write on public.canvas_crdt_snapshots
  for all to authenticated
  using (public.can_edit_project(project_id))
  with check (public.can_edit_project(project_id));

create policy canvas_crdt_operation_member_read on public.canvas_crdt_operations
  for select to authenticated
  using (public.can_read_project(project_id));

create policy canvas_crdt_operation_editor_write on public.canvas_crdt_operations
  for insert to authenticated
  with check (
    public.can_edit_project(project_id)
    and auth_user_id = auth.uid()
  );

create policy collaboration_checkpoint_self_write on public.canvas_collaboration_checkpoints
  for all to authenticated
  using (user_id = auth.uid() and public.can_read_project(project_id))
  with check (user_id = auth.uid() and public.can_read_project(project_id));

create policy share_links_owner_read on public.share_links
  for select to authenticated
  using (public.is_project_owner(project_id));

create policy share_links_owner_write on public.share_links
  for all to authenticated
  using (public.is_project_owner(project_id))
  with check (public.is_project_owner(project_id));

revoke all on public.workspace_members from anon;
revoke all on public.canvas_crdt_snapshots from anon;
revoke all on public.canvas_crdt_operations from anon;
revoke all on public.canvas_collaboration_checkpoints from anon;
revoke all on public.share_links from anon;

grant select on public.projects to authenticated;
grant insert, update, delete on public.projects to authenticated;
grant select, insert, update, delete on public.workspace_members to authenticated;
grant select, insert, update, delete on public.canvas_snapshots to authenticated;
grant select, insert, update, delete on public.comments to authenticated;
grant select, insert, update, delete on public.canvas_crdt_snapshots to authenticated;
grant select, insert on public.canvas_crdt_operations to authenticated;
grant select, insert, update on public.canvas_collaboration_checkpoints to authenticated;
grant select, insert, update, delete on public.share_links to authenticated;

create or replace function public.append_canvas_crdt_operation(
  p_project_id text,
  p_operation jsonb
)
returns public.canvas_crdt_operations
language plpgsql
security invoker
set search_path = public
as $$
declare
  result public.canvas_crdt_operations;
  actor text;
  counter bigint;
  operation_id text;
  dependencies jsonb;
begin
  if not public.can_edit_project(p_project_id) then
    raise exception using errcode = '42501', message = 'Not authorized to edit project';
  end if;

  actor := p_operation #>> '{dot,actorId}';
  counter := nullif(p_operation #>> '{dot,counter}', '')::bigint;
  operation_id := p_operation ->> 'opId';
  dependencies := coalesce(p_operation -> 'dependencies', '{}'::jsonb);

  if actor is null or counter is null or counter <= 0 or operation_id is null then
    raise exception using errcode = '22023', message = 'Invalid CRDT operation envelope';
  end if;

  insert into public.canvas_crdt_operations (
    project_id,
    op_id,
    actor_id,
    actor_counter,
    dependencies,
    operation_json,
    auth_user_id
  ) values (
    p_project_id,
    operation_id,
    actor,
    counter,
    dependencies,
    p_operation,
    auth.uid()
  )
  on conflict (project_id, op_id) do update
    set op_id = excluded.op_id
  returning * into result;

  return result;
end;
$$;

grant execute on function public.append_canvas_crdt_operation(text, jsonb)
to authenticated;

create or replace function public.get_canvas_crdt_delta(
  p_project_id text,
  p_version_vector jsonb default '{}'::jsonb
)
returns table (
  snapshot jsonb,
  operation jsonb
)
language sql
security invoker
set search_path = public
as $$
  with current_snapshot as (
    select jsonb_build_object(
      'projectId', s.project_id,
      'state', s.state_json,
      'version', s.version_vector,
      'updatedAt', s.updated_at
    ) as snapshot
    from public.canvas_crdt_snapshots s
    where s.project_id = p_project_id
      and public.can_read_project(p_project_id)
  )
  select delta.snapshot, delta.operation
  from (
    select current_snapshot.snapshot, null::jsonb as operation, 0 as sort_order
    from current_snapshot
    union all
    select null::jsonb as snapshot, o.operation_json as operation, 1 as sort_order
    from public.canvas_crdt_operations o
    where o.project_id = p_project_id
      and public.can_read_project(p_project_id)
      and coalesce((p_version_vector ->> o.actor_id)::bigint, 0) < o.actor_counter
  ) as delta
  order by delta.sort_order, delta.operation;
$$;

grant execute on function public.get_canvas_crdt_delta(text, jsonb)
to authenticated;

create or replace function public.save_canvas_crdt_snapshot(
  p_project_id text,
  p_state_json jsonb,
  p_version_vector jsonb
)
returns public.canvas_crdt_snapshots
language plpgsql
security invoker
set search_path = public
as $$
declare
  result public.canvas_crdt_snapshots;
begin
  if not public.can_edit_project(p_project_id) then
    raise exception using errcode = '42501', message = 'Not authorized to compact project';
  end if;

  insert into public.canvas_crdt_snapshots (
    project_id,
    state_json,
    version_vector,
    updated_by
  ) values (
    p_project_id,
    p_state_json,
    p_version_vector,
    auth.uid()
  )
  on conflict (project_id) do update set
    state_json = excluded.state_json,
    version_vector = excluded.version_vector,
    updated_at = now(),
    updated_by = auth.uid()
  returning * into result;

  update public.canvas_collaboration_checkpoints
  set version_vector = p_version_vector,
      updated_at = now()
  where project_id = p_project_id
    and user_id = auth.uid();

  delete from public.canvas_crdt_operations operation_row
  where operation_row.project_id = p_project_id
    and exists (
      select 1
      from public.canvas_collaboration_checkpoints checkpoint
      where checkpoint.project_id = p_project_id
        and checkpoint.updated_at > now() - interval '30 days'
    )
    and not exists (
      select 1
      from public.canvas_collaboration_checkpoints checkpoint
      where checkpoint.project_id = p_project_id
        and checkpoint.updated_at > now() - interval '30 days'
        and coalesce(
          (checkpoint.version_vector ->> operation_row.actor_id)::bigint,
          0
        ) < operation_row.actor_counter
    );

  return result;
end;
$$;

grant execute on function public.save_canvas_crdt_snapshot(text, jsonb, jsonb)
to authenticated;

create or replace function public.create_canvas_share_link(
  p_project_id text,
  p_token_hash text,
  p_expires_at timestamptz default null
)
returns public.share_links
language plpgsql
security invoker
set search_path = public
as $$
declare
  result public.share_links;
begin
  if not public.is_project_owner(p_project_id) then
    raise exception using errcode = '42501', message = 'Only the project owner can share it';
  end if;
  if p_token_hash is null or length(trim(p_token_hash)) <> 64 then
    raise exception using errcode = '22023', message = 'Share token hash must be a SHA-256 digest';
  end if;

  update public.projects
  set is_shared = true,
      updated_at = now(),
      updated_by = auth.uid()
  where id = p_project_id;

  insert into public.share_links (
    project_id,
    token_hash,
    expires_at,
    created_by
  ) values (
    p_project_id,
    lower(trim(p_token_hash)),
    p_expires_at,
    auth.uid()
  ) returning * into result;

  return result;
end;
$$;

grant execute on function public.create_canvas_share_link(text, text, timestamptz)
to authenticated;

create or replace function public.revoke_canvas_share_link(p_link_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  update public.share_links link
  set revoked_at = now()
  where link.id = p_link_id
    and public.is_project_owner(link.project_id);
end;
$$;

grant execute on function public.revoke_canvas_share_link(uuid)
to authenticated;

-- The share route passes only a hash, never the raw link token. This is the
-- sole anonymous read path and returns no writable table access.
create or replace function public.read_canvas_share(
  p_project_id text,
  p_token_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if p_token_hash is null or length(trim(p_token_hash)) <> 64 then
    raise exception using errcode = '42501', message = 'Invalid or expired canvas share link';
  end if;

  with valid_share as (
    select
      project.id,
      crdt.state_json,
      snapshot.document_data
    from public.projects project
    join public.share_links link on link.project_id = project.id
    left join public.canvas_crdt_snapshots crdt
      on crdt.project_id = project.id
    left join public.canvas_snapshots snapshot
      on snapshot.project_id = project.id
    where project.id = p_project_id
      and project.is_shared
      and link.token_hash = lower(trim(p_token_hash))
      and link.revoked_at is null
      and (link.expires_at is null or link.expires_at > now())
    limit 1
  )
  select jsonb_build_object(
    'projectId', valid_share.id,
    'document', coalesce(
      valid_share.state_json -> 'document',
      valid_share.document_data
    ),
    'comments', case
      when valid_share.state_json -> 'document' is not null then coalesce(
        valid_share.state_json -> 'comments',
        '[]'::jsonb
      )
      else coalesce(
        (
          select jsonb_agg(
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
               'reactions', comment.reactions
             ) order by comment.created_at
          )
          from public.comments comment
          where comment.project_id = valid_share.id
        ),
        '[]'::jsonb
      )
    end,
    'crdt', coalesce(valid_share.state_json -> 'crdt', '{}'::jsonb)
  )
  into result
  from valid_share;

  if result is null or result -> 'document' is null then
    raise exception using errcode = '42501', message = 'Invalid or expired canvas share link';
  end if;
  return result;
end;
$$;

grant execute on function public.read_canvas_share(text, text)
to anon, authenticated;

revoke execute on function
  public.project_role(text),
  public.claim_canvas_project_ownership(text),
  public.can_read_project(text),
  public.can_comment_project(text),
  public.can_edit_project(text),
  public.is_project_owner(text),
  public.set_canvas_member_role(text, uuid, text),
  public.remove_canvas_member(text, uuid),
  public.append_canvas_crdt_operation(text, jsonb),
  public.get_canvas_crdt_delta(text, jsonb),
  public.save_canvas_crdt_snapshot(text, jsonb, jsonb),
  public.create_canvas_share_link(text, text, timestamptz),
  public.revoke_canvas_share_link(uuid)
from public;
