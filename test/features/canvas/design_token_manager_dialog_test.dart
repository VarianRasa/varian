import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/canvas/presentation/widgets/design_token_manager_dialog.dart';

import '../../test_app.dart';

void main() {
  testWidgets('compact token manager stacks its list and editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(child: testApp(const DesignTokenManagerDialog())),
    );
    await tester.pumpAndSettle();

    final dialog = tester.widget<UiDialog>(find.byType(UiDialog));
    final dialogContext = tester.element(find.byType(UiDialog));
    expect(
      dialog.constraints!.maxWidth,
      AppResponsive.dialogWidth(dialogContext, preferred: 860),
    );
    expect(find.byType(VerticalDivider), findsNothing);
    final dialogBounds = tester.getRect(find.byType(Dialog));
    expect(dialogBounds.left, greaterThanOrEqualTo(0));
    expect(dialogBounds.top, greaterThanOrEqualTo(0));
    expect(dialogBounds.right, lessThanOrEqualTo(390));
    expect(dialogBounds.bottom, lessThanOrEqualTo(480));

    final compactList = find.descendant(
      of: find.byType(Dialog),
      matching: find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.height == 220,
      ),
    );
    expect(compactList, findsOneWidget);
    expect(tester.getSize(compactList).height, 220);
    final close = tester.getRect(find.byTooltip('Close design tokens'));
    expect(close.left, greaterThanOrEqualTo(dialogBounds.left));
    expect(close.right, lessThanOrEqualTo(dialogBounds.right));
    expect(close.top, greaterThanOrEqualTo(dialogBounds.top));
    expect(close.bottom, lessThanOrEqualTo(dialogBounds.bottom));

    final editorTitle = find.text('Create token');
    await tester.ensureVisible(editorTitle);
    await tester.pumpAndSettle();
    final editorBounds = tester.getRect(editorTitle);
    expect(editorBounds.left, greaterThanOrEqualTo(dialogBounds.left));
    expect(editorBounds.right, lessThanOrEqualTo(dialogBounds.right));
    expect(editorBounds.top, greaterThanOrEqualTo(dialogBounds.top));
    expect(editorBounds.bottom, lessThanOrEqualTo(dialogBounds.bottom));
    expect(tester.takeException(), isNull);
  });
  testWidgets('creates a token with modes and resolves it in the list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(child: testApp(const DesignTokenManagerDialog())),
    );
    await tester.pump();
    expect(find.byType(VerticalDivider), findsOneWidget);
    expect(
      tester.widget<VerticalDivider>(find.byType(VerticalDivider)).width,
      AppSpacing.xl,
    );
    final wideDialogBounds = tester.getRect(find.byType(Dialog));
    expect(wideDialogBounds.left, greaterThanOrEqualTo(0));
    expect(wideDialogBounds.top, greaterThanOrEqualTo(0));
    expect(wideDialogBounds.right, lessThanOrEqualTo(1024));
    expect(wideDialogBounds.bottom, lessThanOrEqualTo(768));
    final tokenListColumn = find.descendant(
      of: find.byType(Dialog),
      matching: find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.width == 300,
      ),
    );
    expect(tokenListColumn, findsOneWidget);
    final listBounds = tester.getRect(tokenListColumn);
    expect(listBounds.width, 300);
    expect(listBounds.left, greaterThanOrEqualTo(wideDialogBounds.left));
    expect(listBounds.right, lessThanOrEqualTo(wideDialogBounds.right));
    final editorBounds = tester.getRect(find.text('Create token'));
    expect(editorBounds.left, greaterThan(listBounds.right));
    expect(editorBounds.right, lessThanOrEqualTo(wideDialogBounds.right));
    final wideClose = tester.getRect(find.byTooltip('Close design tokens'));
    expect(wideClose.left, greaterThanOrEqualTo(wideDialogBounds.left));
    expect(wideClose.right, lessThanOrEqualTo(wideDialogBounds.right));
    expect(wideClose.top, greaterThanOrEqualTo(wideDialogBounds.top));
    expect(wideClose.bottom, lessThanOrEqualTo(wideDialogBounds.bottom));
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byKey(const ValueKey('token-id')),
      'color.brand.primary',
    );
    await tester.enterText(
      find.byKey(const ValueKey('token-name')),
      'Brand primary',
    );
    await tester.enterText(
      find.byKey(const ValueKey('token-value')),
      '#3366ff',
    );
    await tester.enterText(
      find.byKey(const ValueKey('token-modes')),
      'base, dark',
    );
    await tester.enterText(
      find.byKey(const ValueKey('token-mode-values')),
      'dark=#ffffff',
    );
    final saveButton = find.byKey(const ValueKey('save-token'));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('token-row-color.brand.primary')),
      findsOneWidget,
    );
    expect(find.textContaining('#3366ff'), findsOneWidget);
  });
}
