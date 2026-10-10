import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/pdf_annotation.dart';
import 'package:varian/features/assets/data/asset_service.dart';
import 'package:varian/features/canvas/presentation/painters/node_painter.dart';
import 'package:varian/features/canvas/presentation/widgets/pdf_viewer_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FileCard Suite & Payload Tests', () {
    test('FilePayload serialization and deserialization', () {
      final fixtureBase64 = base64Encode(utf8.encode('test'));
      final payload = FilePayload(
        fileName: 'Invoice_2026.pdf',
        fileExtension: 'PDF',
        fileSizeText: '450 KB',
        localPath: '/downloads/invoice.pdf',
        base64Data: fixtureBase64,
        remoteUrl: 'https://example.com/invoice.pdf',
        description: 'Quarterly financial report',
        customBadgeColor: const Color(0xFF10B981),
        backgroundColor: const Color(0xFF1E293B),
        borderColor: const Color(0xFF38BDF8),
        borderWidth: 2.0,
        cornerRadius: 12.0,
        hasShadow: true,
        shadowColor: const Color(0x66000000),
        shadowBlur: 10.0,
      );

      final json = payload.toJson();
      final restored = FilePayload.fromJson(json);

      expect(restored.fileName, equals('Invoice_2026.pdf'));
      expect(restored.fileExtension, equals('PDF'));
      expect(restored.fileSizeText, equals('450 KB'));
      // Runtime paths, inline bytes, and delivery URLs must not survive the
      // durable payload round trip.
      expect(restored.localPath, isNull);
      expect(restored.base64Data, isNull);
      expect(restored.remoteUrl, isNull);
      expect(restored.description, equals('Quarterly financial report'));
      expect(
        restored.customBadgeColor?.toARGB32(),
        equals(const Color(0xFF10B981).toARGB32()),
      );
      expect(
        restored.backgroundColor.toARGB32(),
        equals(const Color(0xFF1E293B).toARGB32()),
      );
      expect(
        restored.borderColor.toARGB32(),
        equals(const Color(0xFF38BDF8).toARGB32()),
      );
      expect(restored.borderWidth, equals(2.0));
      expect(restored.cornerRadius, equals(12.0));
      expect(restored.hasShadow, isTrue);
      expect(restored.shadowBlur, equals(10.0));
    });

    test('FilePayload persists and clears PDF annotations', () {
      final payload = FilePayload(
        fileName: 'review.pdf',
        pdfAnnotations: PdfAnnotationData(
          stickyNotes: [
            PdfStickyNote(
              id: 'note',
              pageNumber: 1,
              relativePosition: const Offset(0.5, 0.5),
              text: 'Review',
              color: Colors.amber,
              createdAt: DateTime.utc(2026),
            ),
          ],
        ),
      );

      final restored = FilePayload.fromJson(payload.toJson());

      expect(restored.pdfAnnotations.stickyNotes.single.text, 'Review');
      expect(
        payload.copyWith(clearPdfAnnotations: true).pdfAnnotations.isEmpty,
        isTrue,
      );
    });

    test('FilePayload copyWith works properly', () {
      final payload = FilePayload(fileName: 'Old.zip', fileExtension: 'ZIP');
      final updated = payload.copyWith(
        fileName: 'New.zip',
        fileSizeText: '12 MB',
        description: 'Archive file',
      );

      expect(updated.fileName, equals('New.zip'));
      expect(updated.fileExtension, equals('ZIP'));
      expect(updated.fileSizeText, equals('12 MB'));
      expect(updated.description, equals('Archive file'));
    });

    test(
      'AssetPickerResult calculates formattedSize and fileExt correctly',
      () {
        final resBytes = AssetPickerResult(name: 'data.xlsx', size: 1048576);
        expect(resBytes.formattedSize, equals('1.0 MB'));
        expect(resBytes.fileExt, equals('XLSX'));

        final resKb = AssetPickerResult(name: 'doc.txt', size: 2048);
        expect(resKb.formattedSize, equals('2.0 KB'));
        expect(resKb.fileExt, equals('TXT'));

        final resGb = AssetPickerResult(name: 'video.mp4', size: 1073741824);
        expect(resGb.formattedSize, equals('1.00 GB'));
      },
    );

    test('infers MIME types for common arbitrary files', () {
      const cases = {
        'report.pdf': 'application/pdf',
        'document.docx':
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'sheet.xlsx':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'slides.pptx':
            'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'document.odt': 'application/vnd.oasis.opendocument.text',
        'archive.zip': 'application/zip',
        'data.json': 'application/json',
        'page.html': 'text/html',
        'photo.gif': 'image/gif',
        'sound.flac': 'audio/flac',
        'movie.mov': 'video/quicktime',
        'unknown.bin': 'application/octet-stream',
      };

      for (final entry in cases.entries) {
        expect(inferAssetMimeType(entry.key), entry.value, reason: entry.key);
      }
    });

    testWidgets(
      'NodePainter renders FileCard with custom and default styling without exceptions',
      (tester) async {
        final node = CanvasNode(
          id: 'file-node-1',
          type: NodeType.fileCard,
          x: 50,
          y: 50,
          width: 260,
          height: 80,
          payload: FilePayload(
            fileName: 'Quarterly_Report_2026.docx',
            fileExtension: 'DOCX',
            fileSizeText: '2.8 MB',
            description: 'Document specification for review',
            hasShadow: true,
            borderWidth: 1.5,
            cornerRadius: 10.0,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CustomPaint(
                size: const Size(400, 300),
                painter: _TestFileCardPainter(node),
              ),
            ),
          ),
        );

        expect(find.byType(CustomPaint), findsWidgets);
      },
    );

    testWidgets(
      'PdfViewerScreen renders without errors for empty/fallback payload',
      (tester) async {
        final payload = FilePayload(
          fileName: 'Pendaftaran_Wisuda.pdf',
          fileExtension: 'PDF',
          fileSizeText: '1.2 MB',
        );

        await tester.pumpWidget(
          MaterialApp(home: PdfViewerScreen(payload: payload)),
        );

        await tester.pump();

        expect(find.text('Pendaftaran_Wisuda.pdf'), findsOneWidget);
        expect(find.text('Pendaftaran_Wisuda.pdf'), findsOneWidget);
      },
    );
  });
}

class _TestFileCardPainter extends CustomPainter {
  final CanvasNode node;
  _TestFileCardPainter(this.node);

  @override
  void paint(Canvas canvas, Size size) {
    NodePainter.paint(canvas, node);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
