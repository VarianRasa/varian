import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enforces collaboration room expiry in server RPCs', () {
    final sql = File(
      'supabase/migrations/20260908000001_collaboration_room_expiry.sql',
    ).readAsStringSync().toLowerCase();

    expect(sql, contains('add column if not exists expires_at timestamptz'));
    expect(sql, contains('p_expires_at timestamptz default null'));
    expect(sql, contains('p_expires_at <= now()'));
    expect(sql, contains('(expires_at is null or expires_at > now())'));
    expect(sql, contains("extensions.digest(generated_code, 'sha256')"));
    expect(
      sql,
      contains(
        'grant execute on function public.create_collaboration_room(text, text, timestamptz)',
      ),
    );
  });
}
