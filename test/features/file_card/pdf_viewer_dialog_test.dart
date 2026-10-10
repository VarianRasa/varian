import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/pdf_viewer_dialog.dart';

void main() {
  Future<void> mountDialog(WidgetTester tester, Size viewport) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => PdfViewerDialog(
                  payload: FilePayload(
                    fileName: 'local-fixture.pdf',
                    fileExtension: 'PDF',
                    fileSizeText: '12 KB',
                  ),
                ),
              ),
              child: const Text('Open local PDF fixture'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open local PDF fixture'));
    await tester.pumpAndSettle();
  }

  testWidgets('compact PDF dialog wraps actions below file details', (
    tester,
  ) async {
    await mountDialog(tester, const Size(360, 640));

    expect(find.text('local-fixture.pdf'), findsOneWidget);
    expect(find.text('No PDF source data found.'), findsOneWidget);
    final fileName = tester.getRect(find.text('local-fixture.pdf'));
    final closeAction = tester.getRect(find.byTooltip('Close'));
    expect(closeAction.top, greaterThan(fileName.bottom));
    expect(closeAction.right, lessThanOrEqualTo(360));
    expect(find.byTooltip('Switch to Continuous Scroll'), findsOneWidget);
    expect(find.byTooltip('Open in External Application'), findsOneWidget);
    expect(find.byTooltip('Switch to Light Theme'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide PDF dialog keeps header actions beside file details', (
    tester,
  ) async {
    await mountDialog(tester, const Size(1100, 800));

    expect(find.text('local-fixture.pdf'), findsOneWidget);
    expect(find.text('No PDF source data found.'), findsOneWidget);
    final fileName = tester.getRect(find.text('local-fixture.pdf'));
    final closeAction = tester.getRect(find.byTooltip('Close'));
    expect(closeAction.left, greaterThan(fileName.right));
    expect(closeAction.right, lessThanOrEqualTo(1100));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Switch to Light Theme'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Switch to Dark Theme'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(PdfViewerDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
