import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/features/collaboration/domain/crdt_engine.dart';

DocumentAsset _asset({String id = 'asset-1', String name = 'Board image'}) =>
    DocumentAsset(
      id: id,
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.remote,
      name: name,
      mimeType: 'image/png',
      remoteUrl: 'https://cdn.example/$id.png',
      durableReference: 'assets-project/$id/source.png',
      tags: const ['brand', 'hero'],
      folderId: 'marketing',
      version: 2,
      createdAt: DateTime.utc(2026, 9, 11),
      updatedAt: DateTime.utc(2026, 9, 11),
    );

void main() {
  test('CRDT session rejects an invalid initial asset manifest', () {
    final asset = _asset();
    final document = CanvasDocument(
      projectId: 'invalid-initial-assets',
      assets: DocumentAssetManifest(entries: {'wrong-key': asset}),
      updatedAt: DateTime.utc(2026, 9, 27),
    );

    expect(
      () => CrdtDocumentSession.fromDocument(document, actorId: 'owner'),
      throwsFormatException,
    );
  });

  test('CRDT snapshot restore rejects a mismatched manifest key in state', () {
    final document = CanvasDocument(
      projectId: 'invalid-state-assets',
      updatedAt: DateTime.utc(2026, 9, 27),
    );
    final assetJson = _asset().toPersistenceJson();
    final state = {
      'assets': {'wrong-key': assetJson},
    };

    expect(
      () => CrdtDocumentSession.fromSnapshot(
        document: document,
        actorId: 'guest',
        version: CrdtVersionVector(),
        state: state,
      ),
      throwsFormatException,
    );
  });

  test('CRDT snapshot restore rejects an invalid base asset manifest', () {
    final asset = _asset();
    final document = CanvasDocument(
      projectId: 'invalid-snapshot-assets',
      assets: DocumentAssetManifest(entries: {'wrong-key': asset}),
      updatedAt: DateTime.utc(2026, 9, 27),
    );

    expect(
      () => CrdtDocumentSession.fromSnapshot(
        document: document,
        actorId: 'guest',
        version: CrdtVersionVector(),
      ),
      throwsFormatException,
    );
  });

  test('asset manifest changes converge through CRDT operations', () {
    final document = CanvasDocument(
      projectId: 'assets-project',
      assets: DocumentAssetManifest(entries: {'asset-1': _asset()}),
      updatedAt: DateTime.utc(2026, 9, 11),
    );
    final owner = CrdtDocumentSession.fromDocument(document, actorId: 'owner');
    final guest = CrdtDocumentSession.fromDocument(document, actorId: 'guest');

    final operation = owner.upsertAsset(_asset(name: 'Updated image'));
    expect(guest.applyRemote(operation), CrdtApplyStatus.applied);
    expect(guest.document.assets['asset-1']?.name, 'Updated image');

    final delete = owner.deleteAsset('asset-1');
    expect(guest.applyRemote(delete), CrdtApplyStatus.applied);
    expect(guest.document.assets['asset-1'], isNull);
  });

  test(
    'asset upsert rejects an identity different from the operation target',
    () {
      final document = CanvasDocument(
        projectId: 'asset-target-mismatch',
        updatedAt: DateTime.utc(2026, 9, 27),
      );
      final owner = CrdtDocumentSession.fromDocument(
        document,
        actorId: 'owner',
      );
      final guest = CrdtDocumentSession.fromDocument(
        document,
        actorId: 'guest',
      );
      final operation = owner.upsertAsset(_asset(id: 'asset-1'));
      final tampered = CrdtOperation.create(
        projectId: operation.projectId,
        dot: operation.dot,
        dependencies: operation.dependencies,
        kind: operation.kind,
        targetId: 'other-asset',
        value: operation.value,
      );

      expect(guest.applyRemote(tampered), CrdtApplyStatus.rejected);
      expect(guest.document.assets.entries, isEmpty);
    },
  );

  test('asset dots survive snapshot round trips', () {
    final document = CanvasDocument(
      projectId: 'assets-snapshot',
      updatedAt: DateTime.utc(2026, 9, 11),
    );
    final source = CrdtDocumentSession.fromDocument(document, actorId: 'owner');
    source.upsertAsset(_asset());
    final restored = CrdtDocumentSession.fromSnapshot(
      document: document,
      actorId: 'guest',
      version: source.version,
      state: source.snapshotState(),
    );

    expect(restored.document.assets['asset-1']?.remoteUrl, isNull);
    expect(
      restored.document.assets['asset-1']?.durableReference,
      'assets-project/asset-1/source.png',
    );
    expect(restored.version, source.version);
  });

  test(
    'asset manifest supports search, duplicate detection, relink, and replace',
    () {
      final original = _asset();
      final duplicate = _asset(
        id: 'asset-2',
        name: 'Duplicate',
      ).copyWith(checksum: 'sha256:abc');
      final manifest = DocumentAssetManifest(
        entries: {
          original.id: original.copyWith(checksum: 'sha256:abc'),
          duplicate.id: duplicate,
        },
      );

      expect(manifest.search(query: 'hero'), hasLength(2));
      expect(manifest.search(folderId: 'marketing'), hasLength(2));
      expect(
        manifest.findDuplicate(original.copyWith(checksum: 'sha256:abc'))?.id,
        'asset-2',
      );

      final relinked = manifest.relink(
        'asset-1',
        durableReference: 'varian-image://assetv222',
        localPath: 'C:/assets/asset-1.png',
      );
      expect(relinked['asset-1']?.durableReference, 'varian-image://assetv222');

      final replacement = relinked.replace(
        'asset-1',
        _asset(id: 'replacement', name: 'Updated image'),
      );
      expect(replacement['asset-1']?.name, 'Updated image');
      expect(replacement['asset-1']?.version, 4);
    },
  );
}
