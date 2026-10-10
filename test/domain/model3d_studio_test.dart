import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/domain/models/model3d_studio.dart';

void main() {
  test('Model3DPayload persists studio controls and diagnostics', () {
    final payload = Model3DPayload(
      artifactReference: 'varian-model3d://chair-0001',
      cameraBookmarks: const [
        Model3DCameraBookmark(id: 'front', label: 'Front', positionZ: 4),
      ],
      activeCameraBookmarkId: 'front',
      annotations: const [
        Model3DAnnotation(id: 'seat', text: 'Seat material', x: 0.2, y: 0.1),
      ],
      lightingPreset: Model3DLightingPreset.dramatic,
      snapshots: const [
        Model3DSnapshot(
          id: 'front-shot',
          cameraBookmarkId: 'front',
          assetId: 'snapshot-asset-front',
          artifactReference: 'varian-image://front-shot',
          width: 1024,
          height: 768,
        ),
      ],
    );

    final restored = Model3DPayload.fromJson(payload.toJson());

    expect(restored.cameraBookmarks.single.label, 'Front');
    expect(restored.activeCameraBookmarkId, 'front');
    expect(restored.annotations.single.text, 'Seat material');
    expect(restored.lightingPreset, Model3DLightingPreset.dramatic);
    expect(restored.snapshots.single.width, 1024);
    expect(restored.snapshots.single.assetId, 'snapshot-asset-front');
    expect(restored.diagnostics, isEmpty);
  });

  test('bookmark and annotation operations keep active references safe', () {
    final payload = Model3DPayload(
      artifactReference: 'varian-model3d://chair-0001',
      cameraBookmarks: const [Model3DCameraBookmark(id: 'front')],
      activeCameraBookmarkId: 'front',
    );

    final removed = payload.removeCameraBookmark('front');
    final updated = removed.upsertAnnotation(
      const Model3DAnnotation(id: 'note', text: 'Check edge'),
    );

    expect(removed.activeCameraBookmarkId, isNull);
    expect(updated.annotations.single.id, 'note');
    expect(updated.diagnostics, isEmpty);
  });

  test('diagnostics report broken active bookmark and duplicate IDs', () {
    final payload = Model3DPayload(
      cameraBookmarks: const [
        Model3DCameraBookmark(id: 'same'),
        Model3DCameraBookmark(id: 'same'),
      ],
      activeCameraBookmarkId: 'missing',
    );

    expect(payload.diagnostics, contains('GLB source is unavailable.'));
    expect(
      payload.diagnostics,
      contains('Camera bookmark IDs are duplicated.'),
    );
    expect(
      payload.diagnostics,
      contains('Active camera bookmark does not exist.'),
    );
  });
}
