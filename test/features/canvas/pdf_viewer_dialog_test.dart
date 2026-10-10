import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/canvas/presentation/widgets/pdf_viewer_dialog.dart';

void main() {
  testWidgets('PDF viewer controls stay available at compact width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewerDialog(
          payload: FilePayload(
            fileName: 'guide.pdf',
            fileExtension: 'pdf',
            fileSizeText: '1 KB',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dialogBounds = tester.getRect(find.byType(Dialog));
    expect(dialogBounds, const Rect.fromLTWH(0, 0, 320, 640));
    final surfaces = find.byType(UiSurface);
    expect(surfaces, findsNWidgets(2));
    final headerBounds = tester.getRect(surfaces.first);
    final footerBounds = tester.getRect(surfaces.last);
    expect(headerBounds.top, dialogBounds.top);
    expect(headerBounds.left, dialogBounds.left);
    expect(headerBounds.right, lessThanOrEqualTo(dialogBounds.right));
    expect(footerBounds.bottom, dialogBounds.bottom);
    expect(footerBounds.left, dialogBounds.left);
    expect(footerBounds.right, lessThanOrEqualTo(dialogBounds.right));

    for (final action in [
      find.byTooltip('Switch to Continuous Scroll'),
      find.byTooltip('Open in External Application'),
      find.byTooltip('Switch to Light Theme'),
      find.byTooltip('Close'),
    ]) {
      final bounds = tester.getRect(action);
      expect(bounds.left, greaterThanOrEqualTo(headerBounds.left));
      expect(bounds.right, lessThanOrEqualTo(headerBounds.right));
      expect(bounds.top, greaterThanOrEqualTo(headerBounds.top));
      expect(bounds.bottom, lessThanOrEqualTo(headerBounds.bottom));
    }
    for (final action in [
      find.byTooltip('Previous Page'),
      find.byTooltip('Next Page'),
      find.text('Reset'),
    ]) {
      final bounds = tester.getRect(action);
      expect(bounds.left, greaterThanOrEqualTo(footerBounds.left));
      expect(bounds.right, lessThanOrEqualTo(footerBounds.right));
      expect(bounds.top, greaterThanOrEqualTo(footerBounds.top));
      expect(bounds.bottom, lessThanOrEqualTo(footerBounds.bottom));
    }
    expect(tester.takeException(), isNull);
  });
}
