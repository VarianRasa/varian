import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps AI 3D jobs service-owned and protected by RLS', () {
    final sql = File(
      'supabase/migrations/20260910000000_create_ai_3d_jobs.sql',
    ).readAsStringSync().toLowerCase();

    expect(sql, contains('create table if not exists public.ai_3d_jobs'));
    expect(
      sql,
      contains('project_id text not null references public.projects(id)'),
    );
    expect(sql, contains('owner_subject uuid not null'));
    expect(sql, contains("capability in ('textto3d', 'imageto3d')"));
    expect(
      sql,
      contains('alter table public.ai_3d_jobs enable row level security'),
    );
    expect(
      sql,
      contains(
        'revoke all on public.ai_3d_jobs from public, anon, authenticated',
      ),
    );
    expect(sql, contains('grant all on public.ai_3d_jobs to service_role'));
    expect(
      sql,
      isNot(contains('grant all on public.ai_3d_jobs to authenticated')),
    );
  });
}
