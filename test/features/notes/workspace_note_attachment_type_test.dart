import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/domain/workspace_note_attachments.dart';

void main() {
  test('detects only the approved attachment signatures', () {
    expect(
      detectWorkspaceNoteAttachmentType(
        Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      ),
      WorkspaceNoteAttachmentType.png,
    );
    expect(
      detectWorkspaceNoteAttachmentType(Uint8List.fromList([255, 216, 255, 0])),
      WorkspaceNoteAttachmentType.jpeg,
    );
    expect(
      detectWorkspaceNoteAttachmentType(Uint8List.fromList('GIF89a'.codeUnits)),
      WorkspaceNoteAttachmentType.gif,
    );
    expect(
      detectWorkspaceNoteAttachmentType(
        Uint8List.fromList([
          ...'RIFF'.codeUnits,
          0,
          0,
          0,
          0,
          ...'WEBP'.codeUnits,
        ]),
      ),
      WorkspaceNoteAttachmentType.webp,
    );
    expect(
      detectWorkspaceNoteAttachmentType(
        Uint8List.fromList('%PDF-1.7'.codeUnits),
      ),
      WorkspaceNoteAttachmentType.pdf,
    );
  });

  test('rejects unsupported and mismatched file signatures', () {
    expect(
      detectWorkspaceNoteAttachmentType(Uint8List.fromList('<svg/>'.codeUnits)),
      isNull,
    );
    expect(
      detectWorkspaceNoteAttachmentType(
        Uint8List.fromList([137, 80, 78, 71, 0, 0, 0, 0]),
      ),
      isNull,
    );
    expect(detectWorkspaceNoteAttachmentType(Uint8List(0)), isNull);
  });

  test('rejects files larger than 25 MiB before signature inspection', () {
    final bytes = Uint8List(25 * 1024 * 1024 + 1)
      ..setRange(0, 8, [137, 80, 78, 71, 13, 10, 26, 10]);

    expect(detectWorkspaceNoteAttachmentType(bytes), isNull);
  });
}
