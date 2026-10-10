import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_services.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_surface.dart';
import '../../test_app.dart';

void main() {
  testWidgets('focus-mode exit control uses app surface tokens', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          CanvasEditorSurface(
            projectId: 'focus-mode-local-fixture',
            services: CanvasEditorServices.embedded,
            initialDocument: CanvasDocument(
              projectId: 'focus-mode-local-fixture',
              updatedAt: DateTime.utc(2026),
              navigation: const {'focusMode': true},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final exitButton = find.byTooltip('Exit focus mode');
    expect(exitButton, findsOneWidget);
    final surface = tester.widget<UiSurface>(
      find.ancestor(of: exitButton, matching: find.byType(UiSurface)).first,
    );
    expect(surface.padding, const EdgeInsets.all(AppSpacing.xxs));
    expect(surface.borderRadius, BorderRadius.circular(AppRadius.control));

    await tester.tap(exitButton);
    await tester.pump();
    expect(find.byTooltip('Exit focus mode'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
