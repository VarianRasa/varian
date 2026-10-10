alter table public.comments
  add column if not exists attachments jsonb not null default '[]'::jsonb,
  add column if not exists labels jsonb not null default '[]'::jsonb,
  add column if not exists assignee_id text,
  add column if not exists assignee_name text,
  add column if not exists due_date timestamptz,
  add column if not exists watchers jsonb not null default '[]'::jsonb;

create index if not exists comments_project_unresolved_idx
  on public.comments (project_id, resolved, created_at);

create index if not exists comments_project_due_date_idx
  on public.comments (project_id, due_date)
  where due_date is not null;

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
              'reactions', comment.reactions,
              'attachments', comment.attachments,
              'labels', comment.labels,
              'assigneeId', comment.assignee_id,
              'assigneeName', comment.assignee_name,
              'dueDate', comment.due_date,
              'watchers', comment.watchers
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
