import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/vector_path_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/vector_path_tools_dialog.dart';

import '../../test_app.dart';

void main() {
  testWidgets(
    'empty path keeps unsafe actions disabled and returns insert action',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      VectorPathToolAction? result;

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            Builder(
              builder: (context) => UiButton(
                onPressed: () async {
                  result = await showUiDialog<VectorPathToolAction>(
                    context: context,
                    builder: (_) => VectorPathToolsDialog(
                      payload: VectorPathPayload(),
                      hasBooleanTarget: false,
                    ),
                  );
                },
                child: const Text('Open vector path tools'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open vector path tools'));
      await tester.pumpAndSettle();
      final dialogPadding = tester.widget<Padding>(
        find
            .ancestor(
              of: find.text('Vector path tools'),
              matching: find.byType(Padding),
            )
            .first,
      );
      expect(dialogPadding.padding, const EdgeInsets.all(AppSpacing.md));

      final removeAction = find.ancestor(
        of: find.text('Remove last anchor'),
        matching: find.byType(UiButton),
      );
      expect(tester.widget<UiButton>(removeAction.first).onPressed, isNull);
      await tester.tap(find.text('Insert midpoint anchor'));
      await tester.pumpAndSettle();

      expect(result, VectorPathToolAction.insertAnchor);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('boolean section heading inherits the Material body role', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => UiButton(
              onPressed: () => showUiDialog<void>(
                context: context,
                builder: (_) => VectorPathToolsDialog(
                  payload: VectorPathPayload(),
                  hasBooleanTarget: true,
                ),
              ),
              child: const Text('Open vector path tools'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open vector path tools'));
    await tester.pumpAndSettle();

    final headingPadding = tester.widget<Padding>(
      find
          .ancestor(
            of: find.text('Boolean with the other selected vector'),
            matching: find.byType(Padding),
          )
          .first,
    );
    expect(
      headingPadding.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
    );
    final heading = find.text('Boolean with the other selected vector');
    final theme = Theme.of(tester.element(heading));
    expect(
      tester.widget<Text>(heading).style,
      theme.textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600),
    );
    expect(tester.takeException(), isNull);
  });
}
