import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/file_preview_type.dart';

void main() {
  group('normalizedFileExtension', () {
    test('normalizes explicit uppercase extensions', () {
      final payload = FilePayload(fileName: 'photo.PNG', fileExtension: 'PNG');

      expect(normalizedFileExtension(payload), 'png');
    });

    test('infers the extension from fileName when fileExtension is empty', () {
      final payload = FilePayload(
        fileName: 'report.final.JSON',
        fileExtension: '',
      );

      expect(normalizedFileExtension(payload), 'json');
    });
  });

  group('classifyFilePreview', () {
    final cases = <String, FilePreviewType>{
      'pdf': FilePreviewType.pdf,
      'png': FilePreviewType.image,
      'jpeg': FilePreviewType.image,
      'webp': FilePreviewType.image,
      'gif': FilePreviewType.image,
      'txt': FilePreviewType.text,
      'md': FilePreviewType.text,
      'json': FilePreviewType.text,
      'xml': FilePreviewType.text,
      'csv': FilePreviewType.text,
      'log': FilePreviewType.text,
      'dart': FilePreviewType.text,
      'js': FilePreviewType.text,
      'py': FilePreviewType.text,
      'mp3': FilePreviewType.audio,
      'wav': FilePreviewType.audio,
      'm4a': FilePreviewType.audio,
      'aac': FilePreviewType.audio,
      'ogg': FilePreviewType.audio,
      'mp4': FilePreviewType.video,
      'webm': FilePreviewType.video,
      'mov': FilePreviewType.video,
      'html': FilePreviewType.html,
      'htm': FilePreviewType.html,
      'doc': FilePreviewType.document,
      'docx': FilePreviewType.document,
      'rtf': FilePreviewType.document,
      'xls': FilePreviewType.document,
      'xlsx': FilePreviewType.document,
      'ppt': FilePreviewType.document,
      'pptx': FilePreviewType.document,
      'odt': FilePreviewType.document,
      'ods': FilePreviewType.document,
      'odp': FilePreviewType.document,
      'zip': FilePreviewType.external,
      'bin': FilePreviewType.external,
    };

    for (final MapEntry(key: extension, value: expected) in cases.entries) {
      test('classifies .$extension as ${expected.name}', () {
        final payload = FilePayload(
          fileName: 'sample.$extension',
          fileExtension: extension,
        );

        expect(classifyFilePreview(payload), expected);
      });
    }

    test('classifies an unknown extension as external', () {
      final payload = FilePayload(fileName: 'sample.xyz', fileExtension: 'xyz');

      expect(classifyFilePreview(payload), FilePreviewType.external);
    });
  });
}
