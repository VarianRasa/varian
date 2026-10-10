import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/legacy_project_migration_scheduler.dart';

void main() {
  testWidgets('starts legacy migration only after the first frame', (
    tester,
  ) async {
    var firstFrameBuilt = false;
    var migrationStarted = false;

    scheduleLegacyProjectMigration(() async {
      expect(firstFrameBuilt, isTrue);
      migrationStarted = true;
    });
    expect(migrationStarted, isFalse);

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          firstFrameBuilt = true;
          return const SizedBox.shrink();
        },
      ),
    );

    expect(firstFrameBuilt, isTrue);
    expect(migrationStarted, isFalse);

    await tester.idle();
    expect(migrationStarted, isTrue);
  });
}
