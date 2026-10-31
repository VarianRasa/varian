import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20261021150000_workspace_note_attachments.sql',
  ).readAsStringSync().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  test(
    'creates a dedicated private bucket with a strict size and MIME limit',
    () {
      expect(migration, contains("values ( 'workspace-note-assets'"));
      expect(migration, contains('false, 26214400'));
      expect(migration, contains("'image/png'"));
      expect(migration, contains("'image/jpeg'"));
      expect(migration, contains("'image/gif'"));
      expect(migration, contains("'image/webp'"));
      expect(migration, contains("'application/pdf'"));
      expect(
        migration,
        contains('create table public.workspace_note_attachments'),
      );
    },
  );

  test('derives owner- and project-bound paths from stable IDs', () {
    expect(
      migration,
      contains(
        'create or replace function public.workspace_note_attachment_path',
      ),
    );
    expect(migration, contains("'private/' || p_owner_user_id::text"));
    expect(
      migration,
      contains("'project/' || encode(convert_to(p_project_id, 'utf8'), 'hex')"),
    );
    expect(
      migration,
      contains('storage_path = public.workspace_note_attachment_path'),
    );
  });

  test('enforces same-scope Notes access and pending-only direct uploads', () {
    expect(migration, contains('enable row level security'));
    expect(migration, contains('public.workspace_note_can_read'));
    expect(migration, contains('public.workspace_note_can_edit'));
    expect(migration, contains('workspace_note_attachment_storage_can_read'));
    expect(migration, contains('workspace_note_attachment_storage_can_upload'));
    expect(migration, contains("status = 'pending_upload'"));
    expect(migration, contains('create_workspace_note_attachment'));
  });

  test('records durable rehome jobs and prevents deleting a project early', () {
    expect(migration, contains('workspace_note_attachment_rehome_jobs'));
    expect(migration, contains('workspace_note_attachment_rehome_items'));
    expect(migration, contains('claim_workspace_note_attachment_rehome_jobs'));
    expect(
      migration,
      contains('mark_workspace_note_attachment_rehome_item_verified'),
    );
    expect(migration, contains('commit_workspace_note_attachment_rehome'));
    expect(migration, contains('workspace_note_attachment_rehome_cleanup'));
    expect(
      migration,
      contains(
        'create or replace function public.rehome_workspace_notes_before_project_delete()',
      ),
    );
    expect(migration, contains('return null;'));
  });

  test('supports authorized and retryable attachment deletion', () {
    expect(migration, contains("'deleting'"));
    expect(migration, contains('workspace_note_attachment_storage_can_delete'));
    expect(migration, contains('begin_workspace_note_attachment_delete'));
    expect(migration, contains('finish_workspace_note_attachment_delete'));
    expect(migration, contains("status = 'deleting'"));
  });

  test('resumes cleanup-stage failures without restarting the copy phase', () {
    expect(migration, contains('resume_status text'));
    expect(migration, contains("when v_job_status = 'cleanup' then 'cleanup'"));
    expect(migration, contains('resume_status = case when v_attempt >= 8'));
    expect(migration, contains("status = coalesce(resume_status, 'copying')"));
    expect(migration, contains("status in ('copying', 'cleanup')"));
  });

  test('limits verification and state-changing RPCs to the trusted worker', () {
    expect(migration, contains("auth.role() <> 'service_role'"));
    expect(migration, contains('get_workspace_note_attachment_pending_upload'));
    expect(migration, contains('finalize_workspace_note_attachment_upload'));
    expect(
      migration,
      contains(
        'revoke all on function public.finalize_workspace_note_attachment_upload(uuid, uuid, text, bigint, text)',
      ),
    );
    expect(
      migration,
      contains(
        'grant execute on function public.finalize_workspace_note_attachment_upload(uuid, uuid, text, bigint, text)',
      ),
    );
  });

  test('guards attachment metadata when either Note scope field changes', () {
    final guard = migration
        .split(
          'create or replace function public.workspace_note_attachment_scope_change_guard()',
        )
        .last
        .split('\$function\$;')
        .first;
    expect(guard, contains('new.project_id is distinct from old.project_id'));
    expect(guard, contains('new.owner_user_id is distinct from old.owner_user_id'));
    expect(guard, contains('a.project_id is distinct from new.project_id'));
    expect(guard, contains('a.owner_user_id is distinct from new.owner_user_id'));
    expect(guard, contains('workspace_note_attachment_rehome_required'));
  });

  test('returns pending and retryable status for cloud project deletion', () {
    expect(
      migration,
      contains('create or replace function public.request_workspace_note_project_delete'),
    );
    expect(migration, contains('returns table (status text, job_id uuid)'));
    expect(
      migration,
      contains('retry_workspace_note_attachment_rehome(uuid)'),
    );
    expect(migration, contains("job_kind = 'project_delete'"));
    expect(migration, contains("status = 'complete'"));
  });

  test('schedules the worker through Vault-backed pg_cron and pg_net', () {
    expect(migration, contains('create extension if not exists pg_cron'));
    expect(migration, contains('create extension if not exists pg_net'));
    expect(migration, contains('create extension if not exists supabase_vault'));
    expect(migration, contains('cron.schedule('));
    expect(migration, contains("'notes-attachment-rehome'"));
    expect(migration, contains('vault.decrypted_secrets'));
    expect(migration, contains('notes_attachment_project_url'));
    expect(migration, contains('notes_attachment_worker_secret'));
    expect(migration, contains('net.http_post'));
    expect(migration, contains('x-notes-attachment-worker-secret'));
  });
}
