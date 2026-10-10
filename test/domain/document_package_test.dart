import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/document_migrations.dart';
import 'package:varian/domain/models/document_package.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';

void main() {
  test('migrates schema v1 documents to the current contract', () {
    final document = CanvasDocument.fromJson({
      'schemaVersion': 1,
      'projectId': 'legacy',
      'nodes': const [],
      'edges': const [],
      'updatedAt': '2026-09-11T00:00:00.000Z',
    });

    expect(document.schemaVersion, DocumentMigrations.currentVersion);
    expect(document.assets.items, isEmpty);
    expect(document.navigation, isEmpty);
  });

  test('migrates schema v3 documents with a navigation container', () {
    final document = CanvasDocument.fromJson({
      'schemaVersion': 3,
      'projectId': 'v3',
      'nodes': const [],
      'edges': const [],
    });

    expect(document.schemaVersion, DocumentMigrations.currentVersion);
    expect(document.navigation, isEmpty);
  });

  test('round trips document assets through a project package', () {
    final now = DateTime.utc(2026, 9, 11);
    final asset = DocumentAsset(
      id: 'asset-1',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.remote,
      name: 'hero.png',
      mimeType: 'image/png',
      sizeBytes: 42,
      checksum: 'sha256:abc',
      remoteUrl: 'https://cdn.example.test/hero.png',
      durableReference: 'project/assets/hero.png',
      createdAt: now,
      updatedAt: now,
    );
    final document = CanvasDocument(
      projectId: 'project',
      assets: DocumentAssetManifest(entries: {asset.id: asset}),
      updatedAt: now,
    );

    final restored = CanvasDocumentPackage.decode(
      CanvasDocumentPackage(document: document).encode(),
    );

    expect(CanvasDocumentPackage.packageVersion, 2);
    expect(restored.document.schemaVersion, DocumentMigrations.currentVersion);
    expect(restored.assets['asset-1']?.checksum, 'sha256:abc');
    expect(restored.document.assets['asset-1']?.remoteUrl, isNull);
    expect(
      restored.document.assets['asset-1']?.durableReference,
      'project/assets/hero.png',
    );
  });

  test('package envelopes redact runtime asset delivery values', () {
    final now = DateTime.utc(2026, 9, 11);
    final document = CanvasDocument(
      projectId: 'project',
      nodes: [
        CanvasNode(
          id: 'file-node',
          type: NodeType.fileCard,
          x: 0,
          y: 0,
          width: 320,
          height: 180,
          payload: FilePayload(
            fileName: 'report.pdf',
            artifactReference: 'varian-file://fileartifact1',
            storagePath: 'project/assets/report.pdf',
            localPath: r'C:\\runtime\\report.pdf',
            base64Data: 'c2VjcmV0',
            remoteUrl: 'https://cdn.example.test/report.pdf?token=secret',
          ),
        ),
      ],
      updatedAt: now,
    );

    final encoded = CanvasDocumentPackage(document: document).encode();

    expect(encoded, contains('varian-file://fileartifact1'));
    expect(encoded, isNot(contains('C:\\\\runtime\\\\report.pdf')));
    expect(encoded, isNot(contains('c2VjcmV0')));
    expect(encoded, isNot(contains('cdn.example.test')));
    expect(encoded, isNot(contains('token=secret')));
  });

  test('reads package version one using the version two reader', () {
    final package = CanvasDocumentPackage.decode(
      '{"format":"varian.canvas.package","packageVersion":1,"document":{"projectId":"legacy","nodes":[],"edges":[]},"assets":{"version":1,"items":[]}}',
    );

    expect(package.document.projectId, 'legacy');
  });

  test('rejects a document schema newer than the app supports', () {
    expect(
      () => CanvasDocument.fromJson({
        'schemaVersion': 999,
        'projectId': 'future',
        'nodes': const [],
        'edges': const [],
      }),
      throwsA(isA<DocumentSchemaException>()),
    );
  });
}
