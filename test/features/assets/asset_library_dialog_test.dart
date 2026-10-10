import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/assets/presentation/asset_library_dialog.dart';
import 'package:varian/features/canvas/utils/canvas_image_cache.dart';

import '../../test_app.dart';

void main() {
  final image = CanvasNode(
    id: 'image-1',
    type: NodeType.image,
    x: 0,
    y: 0,
    width: 100,
    height: 100,
    name: 'Hero image',
    payload: ImagePayload(
      assetId: 'hero-image',
      imageArtifactReference: 'varian-image://hero-image',
    ),
  );
  final file = CanvasNode(
    id: 'file-1',
    type: NodeType.fileCard,
    x: 0,
    y: 0,
    width: 100,
    height: 100,
    payload: FilePayload(
      fileName: 'Brand guide.pdf',
      fileExtension: 'PDF',
      description: 'Brand reference',
      assetId: 'brand-file',
      artifactReference: 'varian-file://brand-file',
    ),
  );
  final model = CanvasNode(
    id: 'model-1',
    type: NodeType.model3d,
    x: 0,
    y: 0,
    width: 100,
    height: 100,
    payload: Model3DPayload(
      fileName: 'Chair.glb',
      artifactReference: 'varian-model3d://chair12345',
    ),
  );

  test('filters hidden, unsupported, and source-less nodes', () {
    final result = filterAssetLibraryNodes([
      image,
      file,
      model,
      CanvasNode(
        id: 'hidden',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        visible: false,
        payload: ImagePayload(url: 'https://cdn.example.com/hidden.png'),
      ),
      CanvasNode(
        id: 'empty',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: ImagePayload(),
      ),
      CanvasNode(
        id: 'text',
        type: NodeType.text,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: TextPayload(text: 'Not an asset'),
      ),
    ]);

    expect(result.map((node) => node.id), ['image-1', 'file-1', 'model-1']);
  });

  test('shows reloaded assets that retain only durable references', () {
    final durableOnly = [
      CanvasNode(
        id: 'reloaded-image',
        type: NodeType.image,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: ImagePayload(
          assetId: 'image-asset',
          imageArtifactReference: 'varian-image://image-asset1',
        ),
      ),
      CanvasNode(
        id: 'reloaded-file',
        type: NodeType.fileCard,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: FilePayload(
          fileName: 'Brief.pdf',
          assetId: 'file-asset',
          artifactReference: 'varian-file://file-asset1',
        ),
      ),
      CanvasNode(
        id: 'reloaded-audio',
        type: NodeType.audioCard,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: AudioPayload(
          trackName: 'Voiceover.mp3',
          assetId: 'audio-asset',
          audioArtifactReference: 'varian-media://durable/${'a' * 64}/original',
        ),
      ),
    ];

    final result = filterAssetLibraryNodes(durableOnly);

    expect(result.map((node) => node.id), [
      'reloaded-image',
      'reloaded-file',
      'reloaded-audio',
    ]);
  });

  test(
    'does not expose a runtime-only media node as a durable library asset',
    () {
      final runtimeOnly = CanvasNode(
        id: 'runtime-only-audio',
        type: NodeType.audioCard,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        payload: AudioPayload(
          trackName: 'Transient.mp3',
          audioPath: r'C:\\runtime\\audio.mp3',
          audioUrl: 'https://cdn.example.com/audio.mp3',
        ),
      );

      expect(filterAssetLibraryNodes([runtimeOnly]), isEmpty);
    },
  );

  test('searches metadata and applies type filters', () {
    expect(filterAssetLibraryNodes([image, file], query: 'BRAND'), [file]);
    expect(
      filterAssetLibraryNodes([
        image,
        file,
      ], type: AssetLibraryTypeFilter.images),
      [image],
    );
    expect(
      filterAssetLibraryNodes([
        image,
        file,
        model,
      ], type: AssetLibraryTypeFilter.models3d),
      [model],
    );
  });

  testWidgets('asset library dialog fits compact viewport bounds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      testApp(AssetLibraryDialog(nodes: [image], onInsert: (_) {})),
    );
    await tester.pumpAndSettle();

    final dialog = tester.widget<UiDialog>(find.byType(UiDialog));
    expect(dialog.constraints!.maxWidth, 296);
    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(480));
    expect(find.text('ASSET LIBRARY'), findsOneWidget);
    expect(find.text('Hero image'), findsOneWidget);
    final assetRow = find.ancestor(
      of: find.byKey(ValueKey('asset-library-thumbnail-${image.id}')),
      matching: find.byType(UiSurface),
    );
    expect(assetRow, findsWidgets);
    await tester.ensureVisible(assetRow.first);
    final assetRowRect = tester.getRect(assetRow.first);
    final insertAction = find.byKey(const ValueKey('asset-insert-image-1'));
    await tester.ensureVisible(insertAction);
    final insertRect = tester.getRect(insertAction);
    expect(assetRowRect.left, greaterThanOrEqualTo(dialogRect.left));
    expect(assetRowRect.right, lessThanOrEqualTo(dialogRect.right));
    expect(insertRect.right, lessThanOrEqualTo(dialogRect.right));
    expect(insertRect.bottom, lessThanOrEqualTo(dialogRect.bottom));

    expect(tester.takeException(), isNull);
  });
  testWidgets('renders assets and invokes insert callback', (tester) async {
    CanvasNode? inserted;
    await tester.pumpWidget(
      testApp(
        AssetLibraryDialog(
          nodes: [image, file],
          onInsert: (node) => inserted = node,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ASSET LIBRARY'), findsOneWidget);
    expect(find.text('Hero image'), findsOneWidget);
    expect(find.text('Brand guide.pdf'), findsOneWidget);
    for (final node in [image, file]) {
      final thumbnail = tester.widget<Container>(
        find.byKey(ValueKey('asset-library-thumbnail-${node.id}')),
      );
      expect(
        tester.getSize(
          find.byKey(ValueKey('asset-library-thumbnail-${node.id}')),
        ),
        const Size(56, 56),
      );
      final border = (thumbnail.decoration! as BoxDecoration).border! as Border;
      expect(border.top.width, AppBorder.thin);
    }

    final insertAction = find.byKey(const ValueKey('asset-insert-image-1'));
    await tester.ensureVisible(insertAction);
    await tester.tap(insertAction);
    await tester.pumpAndSettle();

    expect(inserted?.id, 'image-1');
  });

  testWidgets('hides insert actions in read-only mode', (tester) async {
    await tester.pumpWidget(
      testApp(AssetLibraryDialog(nodes: [image], readOnly: true)),
    );
    await tester.pump();

    expect(find.text('Hero image'), findsOneWidget);
    expect(find.text('Insert'), findsNothing);
  });

  testWidgets(
    'removes the fallback cache listener when a row switches caches',
    (tester) async {
      final scopedCache = CanvasImageCache.scoped();
      addTearDown(scopedCache.dispose);
      final singleton = CanvasImageCache.instance;
      singleton.clear();

      await tester.pumpWidget(testApp(AssetLibraryDialog(nodes: [image])));
      await tester.pump();
      expect(singleton.debugListenerCount, 1);

      await tester.pumpWidget(
        testApp(AssetLibraryDialog(nodes: [image], imageCache: scopedCache)),
      );
      await tester.pump();

      expect(singleton.debugListenerCount, 0);
      expect(scopedCache.debugListenerCount, 1);
    },
  );

  testWidgets('reloads a recycled row when its image source changes', (
    tester,
  ) async {
    final scopedCache = CanvasImageCache.scoped();
    addTearDown(scopedCache.dispose);
    final first = image.copyWith(
      payload: ImagePayload(
        imageArtifactReference: 'varian-image://first-image',
      ),
    );
    final second = image.copyWith(
      payload: ImagePayload(
        imageArtifactReference: 'varian-image://second-image',
      ),
    );

    await tester.pumpWidget(
      testApp(AssetLibraryDialog(nodes: [first], imageCache: scopedCache)),
    );
    await tester.pump();
    expect(scopedCache.debugListenerCount, 1);

    await tester.pumpWidget(
      testApp(AssetLibraryDialog(nodes: [second], imageCache: scopedCache)),
    );
    await tester.pump();

    expect(scopedCache.debugListenerCount, 1);
  });

  testWidgets('shows durable manifest records and filters them by tag', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 9, 11);
    final manifestAsset = DocumentAsset(
      id: 'manifest-image',
      kind: DocumentAssetKind.image,
      storage: DocumentAssetStorage.remote,
      name: 'Brand hero',
      mimeType: 'image/png',
      remoteUrl: 'https://cdn.example.com/brand.png',
      durableReference: 'asset://brand-hero',
      folderId: 'brand',
      tags: const ['approved'],
      createdAt: now,
      updatedAt: now,
    );
    await tester.pumpWidget(
      testApp(
        AssetLibraryDialog(
          nodes: [image],
          manifest: DocumentAssetManifest(
            entries: {manifestAsset.id: manifestAsset},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('DURABLE ASSET MANIFEST'), findsOneWidget);
    expect(find.text('Brand hero'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('asset-manifest-tag-filter')),
      'missing',
    );
    await tester.pump();
    expect(find.text('Brand hero'), findsNothing);
  });
}
