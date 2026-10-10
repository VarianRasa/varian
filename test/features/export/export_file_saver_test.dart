import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/export/data/export_file_saver.dart';

void main() {
  test('sanitizes unsafe names while preserving the extension', () {
    expect(
      sanitizeExportFileName(r'folder/report:<draft>?.PDF'),
      'report__draft__.PDF',
    );
    expect(sanitizeExportFileName('CON.txt'), '_CON.txt');
    expect(sanitizeExportFileName('CON.report.txt'), '_CON.report.txt');
    expect(sanitizeExportFileName('name.txt. '), 'name.txt');
    expect(sanitizeExportFileName('...'), 'export');
  });

  test('passes sanitized picker arguments through', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    String? savedFileName;
    Uint8List? receivedBytes;
    String? savedMimeType;
    String? savedDialogTitle;

    final saver = ExportFileSaver(
      isWeb: false,
      saveFile:
          ({
            required String fileName,
            required Uint8List bytes,
            required String mimeType,
            String? dialogTitle,
          }) async {
            savedFileName = fileName;
            receivedBytes = bytes;
            savedMimeType = mimeType;
            savedDialogTitle = dialogTitle;
            return Uri.parse('file:///exports/report.pdf');
          },
    );

    final outcome = await saver.save(
      fileName: r'folder/report:<draft>?.pdf',
      bytes: bytes,
      mimeType: 'application/pdf',
      dialogTitle: 'Save export',
    );

    expect(outcome, ExportSaveOutcome.saved);
    expect(savedFileName, 'report__draft__.pdf');
    expect(receivedBytes, same(bytes));
    expect(savedMimeType, 'application/pdf');
    expect(savedDialogTitle, 'Save export');
  });

  test('treats a native null URI as cancellation', () async {
    final saver = ExportFileSaver(
      isWeb: false,
      saveFile:
          ({
            required String fileName,
            required Uint8List bytes,
            required String mimeType,
            String? dialogTitle,
          }) async => null,
    );

    final outcome = await saver.save(
      fileName: 'report.pdf',
      bytes: Uint8List(0),
      mimeType: 'application/pdf',
    );

    expect(outcome, ExportSaveOutcome.canceled);
  });

  test('treats a web null URI as success', () async {
    final saver = ExportFileSaver(
      isWeb: true,
      saveFile:
          ({
            required String fileName,
            required Uint8List bytes,
            required String mimeType,
            String? dialogTitle,
          }) async => null,
    );

    final outcome = await saver.save(
      fileName: 'report.pdf',
      bytes: Uint8List(0),
      mimeType: 'application/pdf',
    );

    expect(outcome, ExportSaveOutcome.saved);
  });

  test('propagates picker failures', () async {
    final saver = ExportFileSaver(
      saveFile:
          ({
            required String fileName,
            required Uint8List bytes,
            required String mimeType,
            String? dialogTitle,
          }) async {
            throw StateError('picker failed');
          },
    );

    await expectLater(
      saver.save(
        fileName: 'report.pdf',
        bytes: Uint8List(0),
        mimeType: 'application/pdf',
      ),
      throwsA(isA<StateError>()),
    );
  });
}
