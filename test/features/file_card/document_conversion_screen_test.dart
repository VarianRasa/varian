import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/assets/data/file_artifact_store_types.dart';
import 'package:varian/features/canvas/presentation/widgets/document_conversion/document_conversion_models.dart';
import 'package:varian/features/canvas/presentation/widgets/document_conversion/document_conversion_screen.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/transient_file_source_resolver.dart';
import 'package:varian/features/canvas/presentation/widgets/pdf_viewer_screen.dart';
import '../../test_app.dart';

void main() {
  testWidgets('replaces conversion screen with PDF viewer on success', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        DocumentConversionScreen(
          payload: FilePayload(
            fileName: 'report.docx',
            fileExtension: 'docx',
            fileSizeText: '1 MB',
          ),
          service: _SuccessService(),
          fileArtifactStore: MemoryFileArtifactStore(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(PdfViewerScreen), findsOneWidget);
    final viewer = tester.widget<PdfViewerScreen>(find.byType(PdfViewerScreen));
    expect(viewer.payload.fileName, 'report.pdf');
    expect(viewer.payload.artifactReference, startsWith('varian-file://'));
    expect(viewer.payload.localPath, isNull);
    expect(viewer.payload.base64Data, isNull);
  });

  testWidgets('conversion failure actions fit a compact viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      testApp(
        DocumentConversionScreen(
          payload: FilePayload(fileName: 'report.docx', fileExtension: 'docx'),
          service: _FailureService(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Document preview unavailable'), findsOneWidget);
    for (final action in ['RETRY', 'OPEN EXTERNALLY']) {
      final rect = tester.getRect(find.text(action));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(480));
    }
    expect(
      tester.getRect(find.byTooltip('Back')).bottom,
      lessThanOrEqualTo(480),
    );
    expect(tester.takeException(), isNull);
  });
}

class _SuccessService implements DocumentConversionService {
  @override
  Future<DocumentConversionResult> convertToPdf(
    FilePayload payload, {
    TransientFileSourceResolver? sourceResolver,
  }) async => DocumentConversionResult(
    pdfBytes: Uint8List.fromList('%PDF- test'.codeUnits),
    fromCache: true,
  );
}

class _FailureService implements DocumentConversionService {
  @override
  Future<DocumentConversionResult> convertToPdf(
    FilePayload payload, {
    TransientFileSourceResolver? sourceResolver,
  }) {
    throw const DocumentConversionFailure(
      DocumentConversionFailureCode.converterUnavailable,
      'LibreOffice is unavailable.',
    );
  }
}
