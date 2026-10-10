import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/document_preview_parser.dart';

void main() {
  Uint8List zipped(Map<String, String> files) {
    final archive = Archive();
    for (final entry in files.entries) {
      final bytes = utf8.encode(entry.value);
      archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  test('extracts paragraphs and table cells from DOCX', () {
    final bytes = zipped({
      'word/document.xml': '''
        <w:document xmlns:w="word">
          <w:body>
            <w:p><w:r><w:t>Judul Dokumen</w:t></w:r></w:p>
            <w:tbl><w:tr>
              <w:tc><w:p><w:r><w:t>Nama</w:t></w:r></w:p></w:tc>
              <w:tc><w:p><w:r><w:t>Nilai</w:t></w:r></w:p></w:tc>
            </w:tr></w:tbl>
          </w:body>
        </w:document>
      ''',
    });

    final preview = parseDocumentPreview(bytes, 'docx');

    expect(preview.sections, contains('Judul Dokumen'));
    expect(preview.sections, contains('Nama | Nilai'));
  });

  test('rejects corrupt office documents safely', () {
    expect(
      () => parseDocumentPreview(Uint8List.fromList([1, 2, 3]), 'docx'),
      throwsFormatException,
    );
  });

  test('rejects archive entries with traversal paths', () {
    final bytes = zipped({'../outside.xml': '<root>unsafe</root>'});

    expect(() => parseDocumentPreview(bytes, 'docx'), throwsFormatException);
  });

  test('rejects archives with oversized expanded entries', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile(
          'word/document.xml',
          maxDocumentArchiveEntryBytes + 1,
          List<int>.filled(maxDocumentArchiveEntryBytes + 1, 0),
        ),
      );
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

    expect(() => parseDocumentPreview(bytes, 'docx'), throwsFormatException);
  });
}
