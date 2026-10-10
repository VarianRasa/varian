import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/viewport.dart' as canvas_viewport;
import 'package:varian/features/canvas/domain/canvas_navigation.dart';
import 'package:varian/features/canvas/presentation/widgets/viewport_bookmarks_dialog.dart';

import '../../test_app.dart';

void main() {
  testWidgets('bookmark deletion remains usable in a short viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final bookmark = ViewportBookmark(
      id: 'bookmark-1',
      name: 'Home view',
      viewport: const canvas_viewport.Viewport(zoom: 1.25),
      selectedNodeIds: const [],
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    ViewportBookmark? deleted;

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          Builder(
            builder: (context) => UiButton(
              onPressed: () => showUiDialog<void>(
                context: context,
                builder: (_) => ViewportBookmarksDialog(
                  bookmarks: [bookmark],
                  onSelect: (_) {},
                  onRename: (value, name) async => value.copyWith(name: name),
                  onDelete: (value) async {
                    deleted = value;
                    return true;
                  },
                ),
              ),
              child: const Text('Open bookmarks'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open bookmarks'));
    await tester.pumpAndSettle();
    final dialog = tester.widget<UiDialog>(find.byType(UiDialog).first);
    final dialogContext = tester.element(find.byType(UiDialog).first);
    expect(
      dialog.constraints!.maxWidth,
      AppResponsive.dialogWidth(dialogContext, preferred: 520),
    );
    expect(
      dialog.constraints!.maxHeight,
      AppResponsive.dialogHeight(dialogContext, preferred: 560),
    );
    final dialogBounds = tester.getRect(find.byType(Dialog));
    expect(dialogBounds.left, greaterThanOrEqualTo(0));
    expect(dialogBounds.right, lessThanOrEqualTo(390));
    expect(dialogBounds.top, greaterThanOrEqualTo(0));
    expect(dialogBounds.bottom, lessThanOrEqualTo(390));
    final closeBounds = tester.getRect(find.byTooltip('Close bookmarks'));
    expect(closeBounds.left, greaterThanOrEqualTo(dialogBounds.left));
    expect(closeBounds.right, lessThanOrEqualTo(dialogBounds.right));
    expect(closeBounds.top, greaterThanOrEqualTo(dialogBounds.top));
    expect(closeBounds.bottom, lessThanOrEqualTo(dialogBounds.bottom));

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    final confirmationBounds = tester.getRect(find.byType(Dialog).last);
    expect(confirmationBounds.left, greaterThanOrEqualTo(0));
    expect(confirmationBounds.right, lessThanOrEqualTo(390));
    expect(confirmationBounds.top, greaterThanOrEqualTo(0));
    expect(confirmationBounds.bottom, lessThanOrEqualTo(390));
    for (final action in [find.text('Cancel').last, find.text('Delete').last]) {
      final actionBounds = tester.getRect(action);
      expect(actionBounds.left, greaterThanOrEqualTo(confirmationBounds.left));
      expect(actionBounds.right, lessThanOrEqualTo(confirmationBounds.right));
      expect(actionBounds.top, greaterThanOrEqualTo(confirmationBounds.top));
      expect(actionBounds.bottom, lessThanOrEqualTo(confirmationBounds.bottom));
    }
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(deleted, same(bookmark));
    expect(find.text('Home view'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
