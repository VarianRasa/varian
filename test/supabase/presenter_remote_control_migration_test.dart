import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _migration(String name) =>
    File('supabase/migrations/$name').readAsStringSync().toLowerCase();

void main() {
  test(
    'enforces presenter remote consent, role, expiry, revoke, and idempotency',
    () {
      final sql = _migration(
        '20260911000000_create_presenter_remote_control.sql',
      );
      final expiryFix = _migration(
        '20260912000000_fix_presenter_remote_session_expiry.sql',
      );
      final combined = '$sql\n$expiryFix';

      expect(combined, contains('presenter_remote_sessions'));
      expect(combined, contains('presenter_remote_commands'));
      expect(combined, contains('consent_granted'));
      expect(combined, contains('expires_at <= now()'));
      expect(combined, contains('revoked_at is not null'));
      expect(
        combined,
        contains('only project editors can create presenter remote sessions'),
      );
      expect(
        combined,
        contains('only the project owner can grant owner presenter control'),
      );
      expect(
        combined,
        contains('only the session owner can revoke presenter remote control'),
      );
      expect(
        combined,
        contains('only the remote controller can send this command'),
      );
      expect(
        combined,
        contains('on conflict (session_id, command_id) do nothing'),
      );
      expect(
        combined,
        contains(
          'grant execute on function public.append_presenter_remote_command',
        ),
      );
      expect(
        combined,
        contains(
          'revoke execute on function public.append_presenter_remote_command',
        ),
      );
      expect(combined, contains('from public, anon'));
    },
  );
}
