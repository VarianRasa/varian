import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/home/presentation/widgets/project_preview_gate.dart';

import '../../test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android preview defers local document load then renders empty state',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final store = DurableProjectStore(
        database: ProjectDurableDatabase(NativeDatabase.memory()),
      );
      addTearDown(store.close);
      final timestamp = DateTime.utc(2026, 10, 3);
      final project = LocalProjectMetadata(
        id: 'deferred-preview-fixture',
        name: 'Deferred preview fixture',
        createdAt: timestamp,
        updatedAt: timestamp,
      );

      await tester.pumpWidget(
        testApp(DeferredProjectPreview(project: project, durableStore: store)),
      );

      expect(find.text('EMPTY CANVAS'), findsNothing);
      await tester.pumpAndSettle();

      expect(find.text('EMPTY CANVAS'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );
}
