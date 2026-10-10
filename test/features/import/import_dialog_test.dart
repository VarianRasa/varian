import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/data/artifacts/artifact_store_bundle.dart';
import 'package:varian/features/ai/data/image_artifact_store_types.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/document_package.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/state/document_assets_provider.dart';
import 'package:varian/features/canvas/state/document_edges_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/import/import_merge_planner.dart';
import 'package:varian/features/import/presentation/import_dialog.dart';

import '../../test_app.dart';

void main() {
  test('import single-flight gate shares the active operation', () async {
    final gate = ImportSingleFlight();
    final release = Completer<void>();
    var calls = 0;

    final first = gate.run(() async {
      calls++;
      await release.future;
    });
    final second = gate.run(() async {
      calls++;
    });

    expect(identical(first, second), isTrue);
    expect(calls, 1);
    release.complete();
    await first;
    expect(gate.isActive, isFalse);
  });

  testWidgets('preserves the nearest artifact store bundle in dialogs', (
    tester,
  ) async {
    final imageStore = MemoryImageArtifactStore();
    final bundle = ArtifactStoreBundle(imageArtifactStore: imageStore);
    final container = ProviderContainer(
      overrides: [artifactStoreBundleProvider.overrideWithValue(bundle)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const _DialogLauncher()),
      ),
    );
    await tester.tap(find.text('Open import dialog'));
    await tester.pumpAndSettle();

    expect(
      ProviderScope.containerOf(
        tester.element(find.byType(ImportDialog)),
        listen: false,
      ).read(artifactStoreBundleProvider).imageArtifactStore,
      same(imageStore),
    );
  });

  testWidgets('import dialog stays within compact viewport bounds', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 480);
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const _DialogLauncher()),
      ),
    );
    await tester.tap(find.text('Open import dialog'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<UiDialog>(find.byType(UiDialog));
    expect(dialog.constraints!.maxWidth, 336);
    expect(dialog.constraints!.maxHeight, 456);
    final dialogRect = tester.getRect(find.byType(Dialog));
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(360));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(480));
    final preview = tester.getRect(find.text('Preview Import'));
    expect(preview.left, greaterThanOrEqualTo(dialogRect.left));
    expect(preview.right, lessThanOrEqualTo(dialogRect.right));
    expect(preview.bottom, lessThanOrEqualTo(dialogRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('previews JSON before applying it to canvas state', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final rawJson = CanvasDocumentPackage(
      document: CanvasDocument(
        projectId: 'import-dialog-test',
        nodes: [_node('node')],
        updatedAt: DateTime.utc(2026, 9, 13),
      ),
    ).encode();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const _DialogLauncher()),
      ),
    );

    await tester.tap(find.text('Open import dialog'));
    await tester.pumpAndSettle();
    final canvasJsonTab = find.text('CANVAS JSON');
    await tester.ensureVisible(canvasJsonTab);
    await tester.pumpAndSettle();
    await tester.tap(canvasJsonTab);
    await tester.pumpAndSettle();

    final editor = find.byType(TextField).last;
    await tester.enterText(editor, rawJson);
    await tester.tap(find.text('Preview Import'));
    await tester.pumpAndSettle();

    expect(find.text('IMPORT PREVIEW'), findsOneWidget);
    expect(container.read(documentNodesProvider), isEmpty);

    await tester.tap(find.text('Import Nodes'));
    await tester.pumpAndSettle();

    expect(container.read(documentNodesProvider), hasLength(1));
    expect(find.text('IMPORT DIAGRAM / DOCUMENT'), findsNothing);
  });
  testWidgets('picked JSON previews before changing canvas nodes', (
    tester,
  ) async {
    final importedPackage = CanvasDocumentPackage(
      document: CanvasDocument(
        projectId: 'picked-file-test',
        nodes: [_node('picked-file-node')],
        updatedAt: DateTime.utc(2026, 10, 2),
      ),
    ).encode();
    final previousPicker = FilePickerPlatform.instance;
    final picker = _FakeImportPicker(
      _FakeImportFile(
        'picked.json',
        Uint8List.fromList(utf8.encode(importedPackage)),
      ),
    );
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previousPicker);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const _DialogLauncher()),
      ),
    );
    await tester.tap(find.text('Open import dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Import file'));
    await tester.pumpAndSettle();

    expect(picker.pickCalls, 1);
    expect(find.text('IMPORT PREVIEW'), findsOneWidget);
    expect(find.text('1 node(s) • 0 edge(s) • 0 asset(s)'), findsOneWidget);
    expect(find.text('Import Nodes'), findsOneWidget);
    expect(container.read(documentNodesProvider), isEmpty);
  });

  testWidgets('canceling the file picker leaves the import dialog unchanged', (
    tester,
  ) async {
    final previousPicker = FilePickerPlatform.instance;
    final picker = _FakeImportPicker(null);
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previousPicker);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const _DialogLauncher()),
      ),
    );
    await tester.tap(find.text('Open import dialog'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Import file'));
    await tester.pumpAndSettle();

    expect(picker.pickCalls, 1);
    expect(find.text('IMPORT PREVIEW'), findsNothing);
    expect(find.text('Preview Import'), findsOneWidget);
    expect(container.read(documentNodesProvider), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid import taps publish the preview only once', (
    tester,
  ) async {
    final rawJson = CanvasDocumentPackage(
      document: CanvasDocument(
        projectId: 'import-single-flight-test',
        nodes: [_node('single-flight-node')],
        updatedAt: DateTime.utc(2026, 9, 26),
      ),
    ).encode();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const _DialogLauncher()),
      ),
    );
    await tester.tap(find.text('Open import dialog'));
    await tester.pumpAndSettle();
    final canvasJsonTab = find.text('CANVAS JSON');
    await tester.ensureVisible(canvasJsonTab);
    await tester.pumpAndSettle();
    await tester.tap(canvasJsonTab);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, rawJson);
    await tester.tap(find.text('Preview Import'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import Nodes'));
    await tester.tap(find.text('Import Nodes'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(container.read(documentNodesProvider), hasLength(1));
  });

  testWidgets('rejects import publication in read-only ownership', (
    tester,
  ) async {
    final rawJson = CanvasDocumentPackage(
      document: CanvasDocument(
        projectId: 'read-only-import-test',
        nodes: [_node('read-only-node')],
        updatedAt: DateTime.utc(2026, 9, 26),
      ),
    ).encode();
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: testApp(const _DialogLauncher(readOnly: true)),
      ),
    );
    await tester.tap(find.text('Open import dialog'));
    await tester.pumpAndSettle();
    final canvasJsonTab = find.text('CANVAS JSON');
    await tester.ensureVisible(canvasJsonTab);
    await tester.pumpAndSettle();
    await tester.tap(canvasJsonTab);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, rawJson);
    await tester.tap(find.text('Preview Import'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import Nodes'));
    await tester.pumpAndSettle();

    expect(container.read(documentNodesProvider), isEmpty);
    expect(find.text('IMPORT DIAGRAM / DOCUMENT'), findsOneWidget);
  });

  testWidgets(
    'publishes imported asset collisions without overwriting existing assets',
    (tester) async {
      final now = DateTime.utc(2026, 9, 26);
      final existingAsset = DocumentAsset(
        id: 'shared-asset',
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.local,
        name: 'existing.png',
        mimeType: 'image/png',
        durableReference: 'varian-image://existing',
        createdAt: now,
        updatedAt: now,
      );
      final importedAsset = DocumentAsset(
        id: existingAsset.id,
        kind: DocumentAssetKind.image,
        storage: DocumentAssetStorage.local,
        name: 'imported.png',
        mimeType: 'image/png',
        durableReference: 'varian-image://imported',
        createdAt: now,
        updatedAt: now,
      );
      final importedManifest = DocumentAssetManifest(
        entries: {importedAsset.id: importedAsset},
      );
      final rawJson = CanvasDocumentPackage(
        document: CanvasDocument(
          projectId: 'import-collision-test',
          nodes: [
            CanvasNode(
              id: 'imported-image-node',
              type: NodeType.image,
              x: 0,
              y: 0,
              width: 120,
              height: 80,
              payload: ImagePayload(assetId: importedAsset.id),
            ),
          ],
          assets: importedManifest,
          updatedAt: now,
        ),
        assets: importedManifest,
      ).encode();
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(documentAssetsProvider.notifier)
          .setManifest(
            DocumentAssetManifest(entries: {existingAsset.id: existingAsset}),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: testApp(const _DialogLauncher()),
        ),
      );
      await tester.tap(find.text('Open import dialog'));
      await tester.pumpAndSettle();
      final canvasJsonTab = find.text('CANVAS JSON');
      await tester.ensureVisible(canvasJsonTab);
      await tester.pumpAndSettle();
      await tester.tap(canvasJsonTab);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, rawJson);
      await tester.tap(find.text('Preview Import'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import Nodes'));
      await tester.pumpAndSettle();

      final importedNode = container.read(documentNodesProvider).single;
      final remappedId = (importedNode.payload as ImagePayload).assetId;
      expect(remappedId, isNotNull);
      expect(remappedId, isNot('shared-asset'));
      expect(
        container.read(documentAssetsProvider)['shared-asset']!.name,
        'existing.png',
      );
      expect(
        container.read(documentAssetsProvider)[remappedId!]!.name,
        'imported.png',
      );
      expect(find.text('IMPORT DIAGRAM / DOCUMENT'), findsNothing);
    },
  );
}

CanvasNode _node(String id, {double x = 0}) => CanvasNode(
  id: id,
  type: NodeType.rectangle,
  x: x,
  y: 0,
  width: 120,
  height: 80,
  payload: ShapePayload(),
);

final class _FakeImportPicker extends FilePickerPlatform {
  _FakeImportPicker(this.file);

  final PlatformFile? file;
  int pickCalls = 0;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    pickCalls++;
    return file;
  }
}

final class _FakeImportFile extends PlatformFile {
  _FakeImportFile(this.name, this.bytes);

  @override
  final String name;
  final Uint8List bytes;

  @override
  Uri get uri => Uri.parse('memory:///$name');

  @override
  XFile get xFile => XFile.fromData(bytes, name: name);

  @override
  int lengthSync() => bytes.length;

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

class _DialogLauncher extends StatelessWidget {
  const _DialogLauncher({this.readOnly = false});

  final bool readOnly;

  @override
  Widget build(BuildContext context) => UiButton(
    onPressed: () => showUiDialog<void>(
      context: context,
      builder: (_) => ImportDialog(
        projectId: 'import-dialog-test',
        readOnly: readOnly,
        onImport: (result) async {
          final currentNodes = ProviderScope.containerOf(
            context,
            listen: false,
          ).read(documentNodesProvider);
          final currentEdges = ProviderScope.containerOf(
            context,
            listen: false,
          ).read(documentEdgesProvider);
          final currentAssets = ProviderScope.containerOf(
            context,
            listen: false,
          ).read(documentAssetsProvider);
          final plan = ImportMergePlanner.plan(
            importedNodes: result.nodes,
            importedEdges: result.edges,
            existingNodeIds: currentNodes.map((node) => node.id),
            existingEdgeIds: currentEdges.map((edge) => edge.id),
            existingAssets: currentAssets,
            importedAssets: result.assets,
            collisionPrefix: 'test-import',
          );
          final container = ProviderScope.containerOf(context, listen: false);
          container.read(documentNodesProvider.notifier).setNodes([
            ...currentNodes,
            ...plan.nodes,
          ]);
          container.read(documentEdgesProvider.notifier).setEdges([
            ...currentEdges,
            ...plan.edges,
          ]);
          container
              .read(documentAssetsProvider.notifier)
              .setManifest(plan.assets);
        },
      ),
    ),
    child: const Text('Open import dialog'),
  );
}
