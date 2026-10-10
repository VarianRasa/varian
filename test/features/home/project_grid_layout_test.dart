import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/home/presentation/home_screen.dart';
import 'package:varian/features/home/presentation/widgets/project_grid_layout.dart';

import '../../test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('rejects zero and unbounded grid widths', () {
    expect(hasUsableProjectGridWidth(0), isFalse);
    expect(hasUsableProjectGridWidth(-1), isFalse);
    expect(hasUsableProjectGridWidth(double.infinity), isFalse);
    expect(hasUsableProjectGridWidth(240), isTrue);
  });

  testWidgets(
    'keeps the project grid out of zero-width layout while the home view is constrained',
    (tester) async {
      final timestamp = DateTime.utc(2026, 9, 18, 12);
      final project = LocalProjectMetadata(
        id: 'zero-width-project',
        name: 'Zero width project',
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      SharedPreferences.setMockInitialValues({
        'ccs_local_projects_list': jsonEncode([project.toJson()]),
      });

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            const SizedBox(width: 0, height: 640, child: HomeScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keeps project cards out of the first startup frame', (
    tester,
  ) async {
    final timestamp = DateTime.utc(2026, 9, 18, 12);
    final project = LocalProjectMetadata(
      id: 'first-frame-project',
      name: 'First frame project',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    SharedPreferences.setMockInitialValues({
      'ccs_local_projects_list': jsonEncode([project.toJson()]),
    });

    await tester.pumpWidget(ProviderScope(child: testApp(const HomeScreen())));

    expect(find.byKey(const ValueKey('project-grid-active')), findsNothing);

    await tester.pump();
    expect(find.byKey(const ValueKey('project-grid-active')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
