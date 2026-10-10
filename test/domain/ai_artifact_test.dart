import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/ai_artifact.dart';

void main() {
  test('round trips a model artifact without persisting runtime path', () {
    const artifact = AIArtifact(
      kind: AIArtifactKind.model3d,
      path: r'C:\runtime\generated.glb',
      url: 'https://cdn.example.test/generated.glb',
      reference: 'projects/p1/models/generated.glb',
      fileName: 'generated.glb',
      mimeType: 'model/gltf-binary',
      byteLength: 2048,
      previewUrl: 'https://cdn.example.test/generated.png',
      provider: 'triposr',
    );

    final restored = AIArtifact.fromJson(artifact.toJson());

    expect(restored.kind, AIArtifactKind.model3d);
    expect(restored.path, isNull);
    expect(restored.url, isNull);
    expect(restored.reference, artifact.reference);
    expect(restored.fileName, artifact.fileName);
    expect(restored.mimeType, artifact.mimeType);
    expect(restored.byteLength, artifact.byteLength);
    expect(restored.previewUrl, isNull);
    expect(restored.provider, artifact.provider);
  });
}
