import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Runs legacy project migration at idle priority after the local shell has
/// completed its first frame, so migration work cannot compete with the first
/// project-library layout or its post-frame loads.
void scheduleLegacyProjectMigration(Future<void> Function() migration) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      SchedulerBinding.instance.scheduleTask<void>(
        migration,
        Priority.idle,
        debugLabel: 'legacy project migration',
      ),
    );
  });
}
