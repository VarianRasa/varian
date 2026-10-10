import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/document_conversion/document_conversion_screen.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/file_preview_router.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/file_preview_screen.dart';
import 'package:varian/features/canvas/presentation/widgets/pdf_viewer_screen.dart';
import '../../test_app.dart';

void main() {
  Widget app(FilePayload payload, {ExternalFileOpener? openExternal}) =>
      testApp(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  openFilePreview(context, payload, openExternal: openExternal),
              child: const Text('Open'),
            ),
          ),
        ),
      );

  testWidgets('routes PDF files to PdfViewerScreen', (tester) async {
    await tester.pumpWidget(
      app(FilePayload(fileName: 'guide.pdf', fileExtension: 'pdf')),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(PdfViewerScreen), findsOneWidget);
  });

  testWidgets('routes documents to DocumentConversionScreen', (tester) async {
    await tester.pumpWidget(
      app(FilePayload(fileName: 'report.docx', fileExtension: 'docx')),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(DocumentConversionScreen), findsOneWidget);
    expect(find.byType(FilePreviewScreen), findsNothing);
  });

  testWidgets('routes supported files to FilePreviewScreen', (tester) async {
    await tester.pumpWidget(
      app(FilePayload(fileName: 'notes.txt', fileExtension: 'txt')),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(FilePreviewScreen), findsOneWidget);
  });

  testWidgets('opens unsupported files externally', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      app(
        FilePayload(
          fileName: 'archive.zip',
          fileExtension: 'zip',
          base64Data: base64Encode([1, 2, 3]),
        ),
        openExternal: (bytes, fileName) async {
          expect(bytes, [1, 2, 3]);
          expect(fileName, 'archive.zip');
          opened = true;
          return true;
        },
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();

    expect(opened, isTrue);
    expect(find.byType(PdfViewerScreen), findsNothing);
    expect(find.byType(FilePreviewScreen), findsNothing);
  });
}
