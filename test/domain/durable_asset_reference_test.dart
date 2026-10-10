import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/durable_asset_reference.dart';
import 'package:varian/domain/models/node_payload.dart';

void main() {
  test('keeps stable paths and rejects public delivery URLs', () {
    expect(
      durableAssetReference('project-1/library/image.png'),
      'project-1/library/image.png',
    );
    expect(durableAssetReference('https://cdn.example/image.png'), isNull);
    expect(durableAssetReference('http://cdn.example/image.png'), isNull);
    expect(
      durableAssetReference('https://storage.example/object.png?token=runtime'),
      isNull,
    );
  });

  test('DocumentAsset omits transient delivery references', () {
    final asset = DocumentAsset(
      id: 'asset-1',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.remote,
      name: 'Image',
      mimeType: 'image/png',
      remoteUrl: 'https://storage.example/object.png?token=runtime',
      durableReference: 'project-1/library/image.png',
      thumbnailReference: 'data:image/png;base64,AA==',
      createdAt: DateTime.utc(2026, 9, 23),
      updatedAt: DateTime.utc(2026, 9, 23),
    );
    final json = asset.toJson();
    expect(json['remoteUrl'], isNull);
    expect(json['durableReference'], 'project-1/library/image.png');
    expect(json['thumbnailReference'], isNull);
  });

  test('accepts only durable media artifact references', () {
    final checksum = 'a' * 64;
    final reference = 'varian-media://durable/$checksum/original';

    expect(validMediaArtifactReference(reference), reference);
    expect(
      validMediaArtifactReference('varian-media://cache/$checksum/original'),
      isNull,
    );
    expect(
      validMediaArtifactReference(
        'varian-media://durable/${'a' * 63}/original',
      ),
      isNull,
    );
    expect(validMediaArtifactReference('$reference?token=runtime'), isNull);

    final audioAsset = DocumentAsset(
      id: 'audio-asset',
      kind: DocumentAssetKind.audio,
      storage: DocumentAssetStorage.local,
      name: 'Track',
      mimeType: 'audio/mpeg',
      durableReference: reference,
      thumbnailReference: reference,
      createdAt: DateTime.utc(2026, 9, 24),
      updatedAt: DateTime.utc(2026, 9, 24),
    );
    expect(audioAsset.toPersistenceJson()['durableReference'], reference);
    expect(audioAsset.toPersistenceJson()['thumbnailReference'], reference);
  });

  test(
    'AudioPayload persists its owned reference but not runtime delivery',
    () {
      final reference = 'varian-media://durable/${'b' * 64}/original';
      final payload = AudioPayload(
        storagePath: 'project-1/audio/track.mp3',
        audioArtifactReference: reference,
        audioPath: r'C:\\runtime\\track.mp3',
        audioUrl: 'https://cdn.example/track.mp3?token=runtime',
      );

      final json = payload.toJson();
      final restored = AudioPayload.fromJson(json);

      expect(json['audioArtifactReference'], reference);
      expect(json, isNot(contains('audioPath')));
      expect(json, isNot(contains('audioUrl')));
      expect(restored.audioArtifactReference, reference);
      expect(restored.audioPath, isNull);
      expect(restored.audioUrl, isNull);
    },
  );

  test('FilePayload preserves its stable identity and owned reference', () {
    final payload = FilePayload(
      assetId: 'file-asset',
      artifactReference: 'varian-file://fileasset',
      storagePath: 'project-1/files/brief.txt',
      localPath: r'C:\\runtime\\brief.txt',
      base64Data: 'c2hvdWxkLW5vdC1wZXJzaXN0',
      remoteUrl: 'https://cdn.example/brief.txt?token=runtime',
    );

    final json = payload.toJson();
    final restored = FilePayload.fromJson(json);

    expect(json['assetId'], 'file-asset');
    expect(json['artifactReference'], 'varian-file://fileasset');
    expect(json['storagePath'], 'project-1/files/brief.txt');
    expect(json, isNot(contains('localPath')));
    expect(json, isNot(contains('base64Data')));
    expect(json, isNot(contains('remoteUrl')));
    expect(restored.assetId, 'file-asset');
    expect(restored.artifactReference, 'varian-file://fileasset');
    expect(restored.storagePath, 'project-1/files/brief.txt');
    expect(restored.localPath, isNull);
    expect(restored.base64Data, isNull);
    expect(restored.remoteUrl, isNull);
  });

  test('FilePayload does not rehydrate a legacy runtime remoteUrl', () {
    final restored = FilePayload.fromJson({
      'assetId': 'file-asset',
      'artifactReference': 'varian-file://fileasset',
      'storagePath': 'project-1/files/brief.txt',
      'remoteUrl': 'project-1/files/legacy-remote.txt',
    });

    expect(restored.remoteUrl, isNull);
  });

  test('AudioPayload copyWith can clear durable and runtime sources', () {
    final payload = AudioPayload(
      storagePath: 'project-1/audio/track.mp3',
      audioArtifactReference: 'varian-media://durable/${'c' * 64}/original',
      audioPath: r'C:\\runtime\\track.mp3',
      audioUrl: 'https://cdn.example/track.mp3?token=runtime',
    );

    final cleared = payload.copyWith(
      storagePath: null,
      audioArtifactReference: null,
      audioPath: null,
      audioUrl: null,
    );

    expect(cleared.storagePath, isNull);
    expect(cleared.audioArtifactReference, isNull);
    expect(cleared.audioPath, isNull);
    expect(cleared.audioUrl, isNull);
  });
}
