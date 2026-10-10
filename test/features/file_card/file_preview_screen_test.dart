import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/file_preview_screen.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/file_preview_type.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import '../../test_app.dart';

const _minimalPngBytes = <int>[
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  0,
  0,
  0,
  13,
  73,
  72,
  68,
  82,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  1,
  8,
  4,
  0,
  0,
  0,
  181,
  28,
  12,
  2,
  0,
  0,
  0,
  11,
  73,
  68,
  65,
  84,
  120,
  218,
  99,
  100,
  248,
  15,
  0,
  1,
  5,
  1,
  1,
  39,
  24,
  227,
  102,
  0,
  0,
  0,
  0,
  73,
  69,
  78,
  68,
  174,
  66,
  96,
  130,
];

void main() {
  Widget screen(FilePayload payload, FilePreviewType type) =>
      testApp(FilePreviewScreen(payload: payload, previewType: type));

  testWidgets('shows file metadata in the app bar', (tester) async {
    await tester.pumpWidget(
      screen(
        FilePayload(
          fileName: 'notes.txt',
          fileExtension: 'TXT',
          fileSizeText: '12 KB',
          base64Data: base64Encode(utf8.encode('hello')),
        ),
        FilePreviewType.text,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('TXT • 12 KB'), findsOneWidget);
  });

  testWidgets('shows an error when no source is available', (tester) async {
    await tester.pumpWidget(
      screen(
        FilePayload(fileName: 'missing.txt', fileExtension: 'txt'),
        FilePreviewType.text,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preview unavailable'), findsOneWidget);
    expect(find.text('No usable file source was found.'), findsOneWidget);
  });

  testWidgets('renders a base64 image in an interactive viewer', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(
        FilePayload(
          fileName: 'pixel.png',
          fileExtension: 'png',
          base64Data: base64Encode(_minimalPngBytes),
        ),
        FilePreviewType.image,
      ),
    );
    await tester.pump();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.semanticLabel, 'pixel.png');
  });

  testWidgets('renders UTF-8 text with search and copy controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(
        FilePayload(
          fileName: 'unicode.txt',
          fileExtension: 'txt',
          base64Data: base64Encode(utf8.encode('Halo dunia — 你好')),
        ),
        FilePreviewType.text,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Halo dunia — 你好'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byTooltip('Search text'), findsOneWidget);
    expect(find.byTooltip('Copy text'), findsOneWidget);
  });

  testWidgets('renders DOCX content inside the app', (tester) async {
    final xml = utf8.encode('''
      <w:document xmlns:w="word"><w:body>
        <w:p><w:r><w:t>Proposal Skripsi</w:t></w:r></w:p>
      </w:body></w:document>
    ''');
    final archive = Archive()
      ..addFile(ArchiveFile('word/document.xml', xml.length, xml));
    final bytes = ZipEncoder().encode(archive);

    await tester.pumpWidget(
      screen(
        FilePayload(
          fileName: 'proposal.docx',
          fileExtension: 'docx',
          base64Data: base64Encode(bytes),
        ),
        FilePreviewType.document,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Proposal Skripsi'), findsOneWidget);
    expect(find.text('OPEN EXTERNALLY'), findsOneWidget);
  });

  testWidgets('shows an external fallback action for unsupported files', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(
        FilePayload(
          fileName: 'archive.zip',
          fileExtension: 'zip',
          remoteUrl: 'https://example.com/archive.zip',
        ),
        FilePreviewType.external,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preview unavailable'), findsOneWidget);
    expect(find.text('OPEN EXTERNALLY'), findsOneWidget);
  });

  testWidgets('malformed base64 falls back to readable localPath', (
    tester,
  ) async {
    final tempDir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('preview_test_'),
    ))!;
    final tempFile = File('${tempDir.path}/fallback.txt');
    await tester.runAsync(
      () => tempFile.writeAsString('recovered from local path'),
    );

    try {
      await tester.pumpWidget(
        screen(
          FilePayload(
            fileName: 'broken_base64.txt',
            fileExtension: 'txt',
            base64Data: 'not-valid-base64@@@',
            localPath: tempFile.path,
          ),
          FilePreviewType.text,
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('recovered from local path'), findsOneWidget);
    } finally {
      await tester.runAsync(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
    }
  });

  testWidgets('missing localPath falls back to remoteUrl', (tester) async {
    await tester.pumpWidget(
      screen(
        FilePayload(
          fileName: 'missing_local.png',
          fileExtension: 'png',
          localPath: '/non/existent/path/photo.png',
          remoteUrl: 'https://example.com/photo.png',
        ),
        FilePreviewType.image,
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('displays banner when text exceeds 1MB limit', (tester) async {
    final hugeText = 'A' * ((1024 * 1024) + 128);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      screen(
        FilePayload(
          fileName: 'large.log',
          fileExtension: 'log',
          base64Data: base64Encode(utf8.encode(hugeText)),
        ),
        FilePreviewType.text,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(UiAlert), findsOneWidget);
    expect(find.text('Preview limited to the first 1 MB.'), findsOneWidget);
    expect(find.text('OPEN FULL FILE'), findsOneWidget);
    final alertRect = tester.getRect(find.byType(UiAlert));
    expect(alertRect.left, greaterThanOrEqualTo(0));
    expect(alertRect.right, lessThanOrEqualTo(320));
    expect(alertRect.top, greaterThanOrEqualTo(0));
    expect(alertRect.bottom, lessThanOrEqualTo(568));
    for (final action in [
      find.byTooltip('Back'),
      find.byTooltip('Search text'),
      find.byTooltip('Copy text'),
      find.text('OPEN FULL FILE'),
    ]) {
      final rect = tester.getRect(action);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(568));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid remote URL shows fallback error without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(
        FilePayload(
          fileName: 'invalid_remote.html',
          fileExtension: 'html',
          remoteUrl: 'ftp://not-supported-scheme.com',
        ),
        FilePreviewType.html,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preview unavailable'), findsOneWidget);
  });

  testWidgets(
    'image decoding failure shows fallback with external open option',
    (tester) async {
      await tester.pumpWidget(
        screen(
          FilePayload(
            fileName: 'corrupt.jpg',
            fileExtension: 'jpg',
            base64Data: base64Encode(utf8.encode('this is not an image')),
            remoteUrl: 'https://example.com/corrupt.jpg',
          ),
          FilePreviewType.image,
        ),
      );
      await tester.pumpAndSettle();

      // Image widget triggers error builder
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.errorBuilder, isNotNull);

      final errorWidget = image.errorBuilder!(
        tester.element(find.byType(Image)),
        Object(),
        null,
      );
      await tester.pumpWidget(testApp(Scaffold(body: errorWidget)));
      await tester.pumpAndSettle();

      expect(find.text('The preview could not be rendered.'), findsOneWidget);
      expect(find.text('OPEN EXTERNALLY'), findsOneWidget);
    },
  );
}
