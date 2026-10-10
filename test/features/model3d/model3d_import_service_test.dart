import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/domain/models/model3d_studio.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/export/export_service.dart';
import 'package:varian/features/model3d/data/model3d_artifact_store_types.dart';
import 'package:varian/features/model3d/data/model3d_glb_compatibility.dart';
import 'package:varian/features/model3d/data/model3d_import_service.dart';
import 'package:varian/features/model3d/data/model3d_validation.dart';
import 'package:varian/features/search/search_service.dart';

String _testKey() => 'test-key';

Future<void> _authenticate(SupabaseClient client, String userId) async {
  final expiration =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
      1000;
  String encodePart(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final token =
      '${encodePart({'alg': 'HS256'})}.${encodePart({'sub': userId, 'exp': expiration})}.signature';
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'token_type': 'bearer',
      'expires_at': expiration,
      'expires_in': 3600,
      'refresh_token': 'refresh-token',
      'user': {
        'id': userId,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
      },
    }),
  );
}

void main() {
  test('validates a GLB header and sanitizes its file name', () {
    final bytes = _minimalGlb();

    expect(isValidGlbBytes(bytes), isTrue);
    expect(
      sanitizeModel3DFileName(r'..\\spaces:chair.obj'),
      'spaces_chair.glb',
    );
    expect(
      () => validateGlbBytes(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<Model3DValidationException>()),
    );
  });

  test('normalizes integer KHR texture transform values for three_js', () {
    final original = _glbWithIntegerTextureTransform();
    final normalized = normalizeModel3DGlbForThreeJs(original);
    expect(isValidGlbBytes(normalized), isTrue);
    final jsonLength = ByteData.sublistView(
      normalized,
    ).getUint32(12, Endian.little);
    final document =
        jsonDecode(utf8.decode(normalized.sublist(20, 20 + jsonLength)))
            as Map<String, dynamic>;
    final transform =
        document['materials'][0]['pbrMetallicRoughness']['baseColorTexture']['extensions']['KHR_texture_transform'];

    expect(
      (transform['offset'] as List).every((value) => value is double),
      isTrue,
    );
    expect(
      (transform['scale'] as List).every((value) => value is double),
      isTrue,
    );
    expect(transform['rotation'], isA<double>());
    expect(
      normalized.sublist(20 + jsonLength),
      original.sublist(
        20 + ByteData.sublistView(original).getUint32(12, Endian.little),
      ),
    );
  });

  test('leaves GLBs without texture transforms untouched', () {
    final bytes = _minimalGlb();

    expect(identical(normalizeModel3DGlbForThreeJs(bytes), bytes), isTrue);
  });

  test(
    'preserves the local GLB and skips cloud upload when owner is foreign',
    () async {
      var uploadRequests = 0;
      final client = SupabaseClient(
        'https://example.supabase.co',
        _testKey(),
        httpClient: MockClient((request) async {
          if (request.url.path.startsWith('/storage/v1/object/')) {
            uploadRequests++;
            fail('GLB upload must not occur before owner verification.');
          }
          expect(request.method, 'GET');
          expect(request.url.path, '/rest/v1/projects');
          expect(request.url.queryParameters['id'], 'eq.project-1');
          expect(request.url.queryParameters['select'], 'owner_id');
          return http.Response(
            jsonEncode({'owner_id': 'another-account'}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await _authenticate(client, 'model-user');
      final store = MemoryModel3DArtifactStore();

      final result =
          await Model3DImportService(
            artifactStore: store,
            syncService: SupabaseSyncService(client),
          ).importBytes(
            _minimalGlb(),
            fileName: 'chair.glb',
            projectId: 'project-1',
          );

      expect(result.storagePath, isNull);
      expect(await store.exists(result.artifact), isTrue);
      expect(await store.read(result.artifact), _minimalGlb());
      expect(uploadRequests, 0);
    },
  );

  test('imports GLB bytes into a durable artifact store', () async {
    final store = MemoryModel3DArtifactStore();
    final result = await Model3DImportService(
      artifactStore: store,
    ).importBytes(_minimalGlb(), fileName: 'chair.glb', projectId: 'project-1');

    expect(result.fileName, 'chair.glb');
    expect(result.artifact.isPersistent, isTrue);
    expect(await store.exists(result.artifact), isTrue);
    expect((await store.read(result.artifact))!.length, _minimalGlb().length);
  });

  test(
    'disposed handles cannot read embedded bytes but durable hydration survives',
    () async {
      final store = MemoryModel3DArtifactStore();
      final bytes = _minimalGlb();
      final artifact = await store.save(bytes);

      await store.dispose(artifact);

      expect(await store.read(artifact), isNull);
      final rehydrated = await store.hydrate(artifact.reference!);
      expect(rehydrated, isNotNull);
      expect(await store.read(rehydrated!), bytes);
    },
  );

  test('rejects non-GLB names before storing bytes', () async {
    final store = MemoryModel3DArtifactStore();

    await expectLater(
      Model3DImportService(
        artifactStore: store,
      ).importBytes(_minimalGlb(), fileName: 'chair.gltf'),
      throwsA(isA<Model3DValidationException>()),
    );
    expect(
      await store.exists(
        const Model3DArtifact(
          path: 'memory://0/chair.glb',
          reference: 'memory://0/chair.glb',
          fileName: 'chair.glb',
        ),
      ),
      isFalse,
    );
  });

  test(
    'accepts an uppercase GLB suffix and normalizes the file name',
    () async {
      final store = MemoryModel3DArtifactStore();

      final result = await Model3DImportService(
        artifactStore: store,
      ).importBytes(_minimalGlb(), fileName: 'chair.GLB');

      expect(result.fileName, 'chair.glb');
      expect(result.artifact.reference, startsWith('varian-model3d://'));
    },
  );

  test('filters transient runtime sources from serialized payload', () {
    final payload = Model3DPayload(
      modelPath: r'C:\runtime\chair.glb',
      modelUrl: 'blob:https://example.test/model',
      artifactReference: 'memory://model-1',
      isTemporary: true,
    );

    final json = payload.toJson();

    expect(json['modelPath'], isNull);
    expect(json['modelUrl'], isNull);
    expect(json['artifactReference'], isNull);
  });

  test('imports a remote GLB into the durable artifact store', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://cdn.example.test/chair.glb');
      return http.Response.bytes(
        _minimalGlb(),
        200,
        headers: {'content-type': 'model/gltf-binary'},
      );
    });
    final store = MemoryModel3DArtifactStore();

    final result = await Model3DImportService(artifactStore: store)
        .importRemoteUrl(
          'https://cdn.example.test/chair.glb',
          client: client,
          fileName: 'chair.glb',
        );

    expect(result.fileName, 'chair.glb');
    expect(result.byteLength, _minimalGlb().length);
    expect(await store.exists(result.artifact), isTrue);
  });

  test('round trips a model asset manifest without runtime paths', () {
    final now = DateTime.utc(2026, 9, 24);
    final document = CanvasDocument(
      projectId: 'project-1',
      assets: DocumentAssetManifest(
        entries: {
          'model-1': DocumentAsset(
            id: 'model-1',
            kind: DocumentAssetKind.model3d,
            storage: DocumentAssetStorage.local,
            name: 'chair.glb',
            mimeType: 'model/gltf-binary',
            sizeBytes: 24,
            durableReference: 'varian-model3d://chair-asset',
            localPath: r'C:\\runtime\\chair.glb',
            remoteUrl: 'https://cdn.example/chair.glb?token=secret',
            createdAt: now,
            updatedAt: now,
          ),
        },
      ),
      updatedAt: now,
    );

    final restored = CanvasDocument.fromJson(document.toPersistenceJson());
    final asset = restored.assets['model-1'];
    expect(asset, isNotNull);
    expect(asset!.durableReference, 'varian-model3d://chair-asset');
    expect(asset.localPath, isNull);
    expect(asset.remoteUrl, isNull);
  });

  test('round trips a model node payload without runtime paths', () {
    final node = CanvasNode(
      id: 'model-1',
      type: NodeType.model3d,
      x: 10,
      y: 20,
      width: 320,
      height: 240,
      payload: Model3DPayload(
        fileName: 'chair.glb',
        fileSizeText: '24 B',
        storagePath: 'project-1/models3d/chair.glb',
        modelPath: r'C:\\private\\chair.glb',
        artifactReference: r'C:\\app-data\\chair.glb',
        autoRotate: true,
      ),
    );

    final restored = CanvasNode.fromJson(node.toJson());
    final payload = restored.payload as Model3DPayload;

    expect(restored.type, NodeType.model3d);
    expect(payload.fileName, 'chair.glb');
    expect(payload.storagePath, 'project-1/models3d/chair.glb');
    expect(payload.modelPath, isNull);
    expect(payload.artifactReference, isNull);
    expect(payload.autoRotate, isTrue);
  });

  test(
    'round trips all model inspector settings and preserves legacy defaults',
    () {
      final original = Model3DPayload(
        viewportMode: Model3DViewportMode.threeDAndTwoD,
        renderMode: Model3DRenderMode.noPostProcessing,
        materialChannel: Model3DMaterialChannel.clearCoatNormalMap,
        geometryMode: Model3DGeometryMode.vertexNormals,
        wireframeColor: 0xFF22C55E,
        doubleSided: true,
        uvChecker: true,
        transparentBackground: true,
      );
      final restored = Model3DPayload.fromJson(original.toJson());
      final legacy = Model3DPayload.fromJson({'fileName': 'legacy.glb'});

      expect(restored.viewportMode, original.viewportMode);
      expect(restored.renderMode, original.renderMode);
      expect(restored.materialChannel, original.materialChannel);
      expect(restored.geometryMode, original.geometryMode);
      expect(restored.wireframeColor, original.wireframeColor);
      expect(restored.doubleSided, isTrue);
      expect(restored.uvChecker, isTrue);
      expect(restored.inspectorSelection, Model3DInspectorSelection.uvChecker);
      expect(restored.transparentBackground, isTrue);
      expect(legacy.viewportMode, Model3DViewportMode.threeD);
      expect(legacy.renderMode, Model3DRenderMode.finalRender);
      expect(legacy.materialChannel, Model3DMaterialChannel.baseColor);
      expect(legacy.geometryMode, Model3DGeometryMode.none);
      expect(legacy.transparentBackground, isFalse);
    },
  );

  test('infers a single visual selection for legacy payload fields', () {
    final uv = Model3DPayload.fromJson({
      'renderMode': 'noPostProcessing',
      'materialChannel': 'roughness',
      'geometryMode': 'wireframe',
      'uvChecker': true,
    });
    final geometry = Model3DPayload.fromJson({'geometryMode': 'vertexNormals'});
    final render = Model3DPayload.fromJson({'renderMode': 'noPostProcessing'});

    expect(uv.inspectorSelection, Model3DInspectorSelection.uvChecker);
    expect(
      geometry.inspectorSelection,
      Model3DInspectorSelection.vertexNormals,
    );
    expect(
      render.inspectorSelection,
      Model3DInspectorSelection.noPostProcessing,
    );
  });

  test('persists a snapshot manifest identity across payload round trips', () {
    const snapshot = Model3DSnapshot(
      id: 'snapshot-1',
      assetId: 'snapshot-asset-1',
      artifactReference: 'varian-image://snapshotasset',
      width: 640,
      height: 480,
    );

    final restored = Model3DSnapshot.fromJson(snapshot.toJson());

    expect(restored.assetId, 'snapshot-asset-1');
    expect(restored.artifactReference, 'varian-image://snapshotasset');
    expect(restored.width, 640);
    expect(restored.height, 480);
  });

  test('searches and exports model metadata without runtime sources', () {
    final node = CanvasNode(
      id: 'model-2',
      type: NodeType.model3d,
      x: 0,
      y: 0,
      width: 320,
      height: 240,
      payload: Model3DPayload(
        fileName: 'chair.glb',
        fileSizeText: '24 B',
        modelPath: r'C:\\private\\chair.glb',
        artifactReference: r'C:\\app-data\\chair.glb',
      ),
    );
    final document = CanvasDocument(
      projectId: 'project-1',
      nodes: [node],
      updatedAt: DateTime(2026, 1, 1),
    );

    final results = SearchService.searchNodes(document.nodes, 'chair');
    final svg = ExportService.exportVectorSvg(document);
    final markdown = ExportService.exportMarkdown(document);

    expect(results.single.title, 'chair.glb');
    expect(results.single.icon, Icons.view_in_ar_outlined);
    expect(svg, contains('chair.glb'));
    expect(markdown, contains('**3D Model:** chair.glb'));
    expect(svg, isNot(contains('C:\\private')));
  });
}

Uint8List _glbWithIntegerTextureTransform() {
  final json = jsonEncode({
    'asset': {'version': '2.0'},
    'extensionsUsed': ['KHR_texture_transform'],
    'materials': [
      {
        'pbrMetallicRoughness': {
          'baseColorTexture': {
            'index': 0,
            'extensions': {
              'KHR_texture_transform': {
                'offset': [0, 1],
                'rotation': 0,
                'scale': [1, 1],
              },
            },
          },
        },
      },
    ],
  });
  final jsonBytes = Uint8List.fromList(utf8.encode(json));
  final paddedJsonLength = (jsonBytes.length + 3) & ~3;
  const binaryBytes = <int>[1, 2, 3, 4];
  final binaryLength = 8 + binaryBytes.length;
  final totalLength = 12 + 8 + paddedJsonLength + binaryLength;
  final output = Uint8List(totalLength);
  final header = ByteData.sublistView(output)
    ..setUint32(0, 0x46546C67, Endian.little)
    ..setUint32(4, 2, Endian.little)
    ..setUint32(8, totalLength, Endian.little)
    ..setUint32(12, paddedJsonLength, Endian.little)
    ..setUint32(16, 0x4E4F534A, Endian.little);
  output.setRange(20, 20 + jsonBytes.length, jsonBytes);
  for (
    var index = 20 + jsonBytes.length;
    index < 20 + paddedJsonLength;
    index++
  ) {
    output[index] = 0x20;
  }
  final binaryOffset = 20 + paddedJsonLength;
  header
    ..setUint32(binaryOffset, binaryBytes.length, Endian.little)
    ..setUint32(binaryOffset + 4, 0x004E4942, Endian.little);
  output.setRange(binaryOffset + 8, output.length, binaryBytes);
  return output;
}

Uint8List _minimalGlb() {
  final bytes = Uint8List(24);
  final data = ByteData.sublistView(bytes);
  data.setUint32(0, 0x46546C67, Endian.little);
  data.setUint32(4, 2, Endian.little);
  data.setUint32(8, bytes.length, Endian.little);
  data.setUint32(12, 4, Endian.little);
  data.setUint32(16, 0x4E4F534A, Endian.little);
  bytes.setRange(20, 24, <int>[0x7B, 0x7D, 0x20, 0x20]);
  return bytes;
}
