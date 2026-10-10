import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _migration() => File(
  'supabase/migrations/20260915070000_create_meeting_sessions.sql',
).readAsStringSync().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

void main() {
  test('defines the isolated meeting session table and durable constraints', () {
    final sql = _migration();
    expect(sql, contains('create table public.meeting_sessions'));
    expect(sql, contains('id uuid primary key'));
    expect(
      sql,
      contains(
        'project_id text not null references public.projects(id) on delete cascade',
      ),
    );
    expect(sql, contains('created_by uuid not null'));
    expect(sql, contains("provider text not null default 'livekit'"));
    expect(sql, contains("check (provider = 'livekit')"));
    expect(sql, contains('provider_room_name text not null unique'));
    expect(sql, contains("status text not null default 'active'"));
    expect(sql, contains("check (status in ('active', 'ended'))"));
    expect(sql, contains('created_at timestamptz not null default now()'));
    expect(sql, contains('ended_at timestamptz'));
    expect(
      sql,
      contains(
        "ended_reason text check (ended_reason is null or ended_reason in ('host_ended', 'room_revoked', 'expired', 'admin_ended'))",
      ),
    );
    expect(sql, contains('max_participants integer not null default 8'));
    expect(sql, contains('check (max_participants between 2 and 8)'));
    expect(
      sql,
      contains(
        "status = 'active' and ended_at is null and ended_reason is null",
      ),
    );
    expect(
      sql,
      contains(
        "status = 'ended' and ended_at is not null and ended_reason is not null",
      ),
    );
    expect(sql, contains("where status = 'active'"));
    expect(sql, contains('create unique index'));
    expect(sql, contains('on public.meeting_sessions (project_id)'));
  });

  test('enables RLS and revokes direct table access', () {
    final sql = _migration();
    expect(
      sql,
      contains('alter table public.meeting_sessions enable row level security'),
    );
    expect(
      sql,
      contains(
        'revoke all on table public.meeting_sessions from public, anon, authenticated',
      ),
    );
    expect(
      sql,
      contains(
        'grant select on table public.meeting_sessions to authenticated',
      ),
    );
    expect(
      sql,
      contains(
        'create policy meeting_sessions_select_member on public.meeting_sessions for select to authenticated using (public.project_role(project_id) is not null)',
      ),
    );
    expect(
      sql,
      contains(
        'alter publication supabase_realtime add table public.meeting_sessions',
      ),
    );
  });

  test('creates authenticated-only secure RPCs', () {
    final sql = _migration();
    for (final function in [
      'public.create_meeting_session',
      'public.join_meeting_session',
      'public.end_meeting_session',
    ]) {
      expect(sql, contains('create or replace function $function('));
      expect(sql, contains('security definer'));
      expect(sql, contains('set search_path = public'));
      expect(sql, contains('revoke all on function $function'));
      expect(sql, contains('grant execute on function $function'));
    }
    expect(sql, contains('auth.uid() is null'));
  });

  test('enforces owner, membership, and bounded creation rules', () {
    final sql = _migration();
    expect(sql, contains('public.is_project_owner(p_project_id)'));
    expect(sql, contains('p_max_participants is null'));
    expect(sql, contains('p_max_participants < 2'));
    expect(sql, contains('p_max_participants > 8'));
    expect(
      sql,
      contains('public.project_role(session_row.project_id) is null'),
    );
    expect(
      sql,
      contains("gen_random_uuid(), p_project_id, auth.uid(), 'livekit'"),
    );
    expect(
      sql,
      contains("'meeting-' || replace(gen_random_uuid()::text, '-', '')"),
    );
  });

  test('requires an active project member when the creator ends a meeting', () {
    final sql = _migration();
    expect(
      sql,
      contains(
        "session_row.created_by = auth.uid() and public.project_role(session_row.project_id) is not null",
      ),
    );
  });

  test(
    'distinguishes authorized ended sessions without revealing them to non-members',
    () {
      final sql = _migration();
      expect(sql, contains("errcode = 'p0003'"));
      expect(
        sql,
        contains(
          "if public.project_role(session_row.project_id) is null then raise exception",
        ),
      );
      expect(
        sql,
        contains("if session_row.status = 'ended' then raise exception"),
      );
    },
  );

  test('keeps create and end operations idempotent with controlled reasons', () {
    final sql = _migration();
    expect(
      sql,
      contains("where project_id = p_project_id and status = 'active'"),
    );
    expect(
      sql,
      contains("on conflict (project_id) where status = 'active' do nothing"),
    );
    expect(
      sql,
      contains(
        "p_reason not in ('host_ended', 'room_revoked', 'expired', 'admin_ended')",
      ),
    );
    expect(sql, contains('created_by = auth.uid()'));
    expect(sql, contains("status = 'ended'"));
    expect(sql, contains('ended_at = now()'));
    expect(sql, contains('ended_reason = p_reason'));
  });

  test('returns only session data and does not alter collaboration tables', () {
    final sql = _migration();
    expect(sql, contains('returns jsonb'));
    expect(sql, contains('return to_jsonb(session_row)'));
    expect(sql, isNot(contains('access_token')));
    expect(sql, isNot(contains('api_secret')));
    expect(sql, isNot(contains('sdp')));
    expect(sql, isNot(contains('ice_candidate')));
    expect(sql, isNot(contains('alter table public.comments')));
    expect(sql, isNot(contains('canvas_crdt')));
    expect(sql, isNot(contains('screen_tracking')));
  });
}
