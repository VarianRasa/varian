import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/meeting/data/meeting_configuration.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final readme = _read('README.md');
  final supabaseConfig = _read('supabase/config.toml');
  final meetingTokenFunction = _read(
    'supabase/functions/meeting-token/index.ts',
  );
  final meetingRemovalFunction = _read(
    'supabase/functions/meeting-remove-participant/index.ts',
  );
  final releaseGate = _read('tool/video_meeting_platform_matrix.ps1');
  final serverEnvironmentNames = <String>[
    'LIVEKIT_URL',
    'LIVEKIT_API_KEY',
    'LIVEKIT_API_SECRET',
    'ALLOWED_ORIGINS',
  ];

  test(
    'documents both meeting functions and their server environment contract',
    () {
      for (final functionName in [
        'meeting-token',
        'meeting-remove-participant',
      ]) {
        expect(readme, contains(functionName));
        expect(releaseGate, contains(functionName));
        expect(
          supabaseConfig,
          contains('[functions.$functionName]\nverify_jwt = false'),
        );
      }

      for (final name in serverEnvironmentNames) {
        expect(readme, contains(name));
        expect(supabaseConfig, contains(name));
        expect(meetingTokenFunction, contains(name));
        expect(meetingRemovalFunction, contains(name));
      }
      expect(readme, contains('Bearer authentication'));
    },
  );

  test(
    'release gate checks both function files without printing environment values',
    () {
      expect(releaseGate, contains('meeting-token/index.ts'));
      expect(releaseGate, contains('meeting-remove-participant/index.ts'));
      expect(releaseGate, contains('Get-ProcessEnvironmentValue'));
      expect(releaseGate, isNot(contains('Write-Output \$value')));
      expect(releaseGate, isNot(contains('Write-Host \$value')));
      expect(releaseGate, contains('never prints environment values'));
    },
  );

  test(
    'documents client-safe meeting defines and disabled-by-default behavior',
    () {
      expect(readme, contains(MeetingConfiguration.featureFlagEnvironmentKey));
      expect(readme, contains(MeetingConfiguration.providerUrlEnvironmentKey));
      expect(
        readme,
        contains(MeetingConfiguration.participantLimitEnvironmentKey),
      );
      expect(readme, contains('disabled by default'));
      expect(readme, contains('tool/video_meeting_platform_matrix.ps1'));
    },
  );
}
