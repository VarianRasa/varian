import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/drawing_paper/presentation/dialogs/paper_template_dialog.dart';

import '../../test_app.dart';

void main() {
  testWidgets('paper preset dialog and footer fit a compact viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          PaperTemplateDialog(onSelected: (_) {}),
          data: AppTheme.darkTheme,
          materialTheme: AppTheme.darkTheme,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dialog = tester.widget<UiDialog>(find.byType(UiDialog));
    expect(dialog.constraints!.maxWidth, 296);
    expect(dialog.constraints!.maxHeight, 456);
    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(480));
    final createAction = find.text('Create Paper on Canvas');
    await tester.ensureVisible(createAction);
    final actionRect = tester.getRect(createAction);
    expect(actionRect.left, greaterThanOrEqualTo(dialogRect.left));
    expect(actionRect.right, lessThanOrEqualTo(dialogRect.right));
    expect(actionRect.bottom, lessThanOrEqualTo(dialogRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('paper preset cards keep finite layout constraints', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          PaperTemplateDialog(onSelected: (_) {}),
          data: AppTheme.darkTheme,
          materialTheme: AppTheme.darkTheme,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(1024));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(768));
    final firstCard = tester.getRect(
      find.bySemanticsLabel('A4 Portrait paper preset'),
    );
    final secondCard = tester.getRect(
      find.bySemanticsLabel('A4 Landscape paper preset'),
    );
    final thirdCard = tester.getRect(
      find.bySemanticsLabel('A5 Notebook paper preset'),
    );
    expect(secondCard.left, greaterThan(firstCard.right));
    expect(thirdCard.top, greaterThan(firstCard.bottom));
    expect(firstCard.left, greaterThanOrEqualTo(dialogRect.left));
    expect(secondCard.right, lessThanOrEqualTo(dialogRect.right));
    expect(thirdCard.right, lessThanOrEqualTo(dialogRect.right));
    expect(find.text('New Drawing Paper'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creating paper returns the selected preset payload', (
    tester,
  ) async {
    DrawingPaperPayload? createdPaper;
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          PaperTemplateDialog(onSelected: (payload) => createdPaper = payload),
          data: AppTheme.darkTheme,
          materialTheme: AppTheme.darkTheme,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('A4 Landscape paper preset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create Paper on Canvas'));
    await tester.pumpAndSettle();

    expect(createdPaper, isNotNull);
    expect(createdPaper!.presetName, 'A4 Landscape');
    expect(createdPaper!.dpi, 300);
    expect(createdPaper!.pixelWidth, 3508);
    expect(createdPaper!.pixelHeight, 2480);
    expect(createdPaper!.paperColor, Colors.white);
    expect(find.byType(UiDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
