import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/document_package.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/import/import_service.dart';

void main() {
  test('JSON package import exposes health and migration preview', () {
    final document = CanvasDocument(
      projectId: 'preview',
      nodes: [
        CanvasNode(
          id: 'node',
          type: NodeType.rectangle,
          x: 0,
          y: 0,
          width: 100,
          height: 80,
          payload: ShapePayload(),
        ),
      ],
      updatedAt: DateTime.utc(2026, 9, 13),
    );
    final raw = CanvasDocumentPackage(document: document).encode();

    final result = ImportService.importFromJson(raw);

    expect(result.isSuccess, isTrue);
    expect(result.packageHealth, isNotNull);
    expect(result.packageHealth!.checksum, isNotEmpty);
    expect(result.packageHealth!.isHealthy, isTrue);
    expect(result.migrationPreview?.canApply, isTrue);
    expect(result.nodes, hasLength(1));
  });

  test('raw legacy JSON exposes migrations without mutating the source', () {
    final source = <String, dynamic>{
      'schemaVersion': 1,
      'projectId': 'legacy',
      'nodes': const [],
      'edges': const [],
    };

    final result = ImportService.importFromJson(jsonEncode(source));

    expect(result.isSuccess, isTrue);
    expect(result.packageHealth, isNull);
    expect(result.migrationPreview?.sourceVersion, 1);
    expect(result.migrationPreview?.targetVersion, 4);
  });

  test('imports Markdown as editable text and CSV as a table', () {
    final markdown = ImportService.importFromMarkdown('# Heading\n\nBody');
    expect(markdown.isSuccess, isTrue);
    expect(markdown.nodes.single.type, NodeType.text);
    expect(markdown.lossReport?.isLossless, isTrue);

    final csv = ImportService.importFromCsv(
      'Name,Status\nCanvas,Active\nExport',
    );
    expect(csv.isSuccess, isTrue);
    expect(csv.nodes.single.type, NodeType.tableGrid);
    expect(csv.lossReport?.lossy, isNotEmpty);
  });

  test('preserves safe SVG and rejects active SVG content', () {
    final safe = ImportService.importFromSvg(
      '<svg xmlns="http://www.w3.org/2000/svg"><rect width="20" height="20"/></svg>',
    );
    expect(safe.isSuccess, isTrue);
    expect(safe.nodes.single.type, NodeType.fileCard);
    expect(safe.lossReport?.isLossless, isFalse);

    final unsafe = ImportService.importFromSvg(
      '<svg><script>alert(1)</script></svg>',
    );
    expect(unsafe.isSuccess, isFalse);
  });

  test(
    'file-byte import keeps unsupported formats as auditable attachments',
    () {
      final result = ImportService.importFromFileBytes(
        fileName: 'deck.pptx',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(result.isSuccess, isTrue);
      expect(result.nodes.single.type, NodeType.fileCard);
      expect(result.lossReport?.lossy, isNotEmpty);
    },
  );
}
