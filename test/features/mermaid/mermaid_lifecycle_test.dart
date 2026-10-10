import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/state/document_edges_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/presentation/widgets/nested_board_editor_host.dart';
import 'package:varian/features/mermaid/domain/mermaid_renderer.dart';

const _asyncFixture = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <g id="Alice" data-id="Alice"><rect x="10" y="10" width="20" height="20" /></g>
  <g id="Bob" data-id="Bob"><rect x="70" y="70" width="20" height="20" /></g>
  <path id="edge-Alice-Bob" data-edge="true" data-from="Alice" data-to="Bob" d="M30 20 L70 80" />
</svg>
''';

class _LifecycleRenderer implements MermaidRenderer {
  int renderCalls = 0;
  Completer<MermaidRenderResult>? pendingRender;
  String svg = _asyncFixture;

  @override
  String get rendererVersion => 'lifecycle-test-renderer';

  @override
  Future<MermaidValidationResult> validate(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) async =>
      const MermaidValidationResult.valid(diagramType: 'sequencediagram');

  @override
  Future<MermaidRenderResult> render(
    String source, {
    MermaidRenderConfig config = const MermaidRenderConfig(),
  }) {
    renderCalls++;
    final pending = pendingRender;
    if (pending != null) return pending.future;
    return Future.value(
      MermaidRenderResult(svg: svg, diagramType: 'sequencediagram'),
    );
  }
}

void main() {
  CanvasNode mermaidSource({
    String source = 'flowchart TD\n  A[Start] --> B[End]',
  }) => CanvasNode(
    id: 'mermaid-source',
    type: NodeType.mermaid,
    x: 100,
    y: 200,
    width: 480,
    height: 320,
    zIndex: 3,
    payload: MermaidPayload(source: source),
  );

  CanvasNode cachedMermaidSource() {
    final source = mermaidSource();
    final payload = source.payload as MermaidPayload;
    final config = MermaidRenderConfig(
      theme: payload.theme,
      direction: payload.direction,
      overrides: payload.config,
    );
    return source.copyWith(
      payload: payload.copyWith(
        cachedSvg: _asyncFixture,
        cachedSvgRevision: payload.sourceRevision,
        cachedSvgConfigKey: config.cacheKey,
        rendererVersion: 'lifecycle-test-renderer',
      ),
    );
  }

  CanvasNode unrelatedNode() => CanvasNode(
    id: 'unrelated-node',
    type: NodeType.rectangle,
    x: 800,
    y: 100,
    width: 120,
    height: 80,
    zIndex: 1,
    payload: ShapePayload(label: 'Unrelated'),
  );

  CanvasEdge unrelatedEdge() => const CanvasEdge(
    id: 'unrelated-edge',
    sourceNodeId: 'unrelated-node',
    targetNodeId: 'unrelated-node',
  );

  ProviderContainer containerFor({
    required List<CanvasNode> nodes,
    List<CanvasEdge> edges = const [],
    MermaidRenderer? mermaidRenderer,
  }) {
    final container = ProviderContainer(
      overrides: [
        documentNodesProvider.overrideWith(
          (ref) => DocumentNodesNotifier(
            ref,
            initialNodes: nodes,
            mermaidRenderer: mermaidRenderer ?? _LifecycleRenderer(),
          ),
        ),
      ],
    );
    container.read(documentEdgesProvider.notifier).setEdges(edges);
    return container;
  }

  test('imported native Mermaid graphs retain lifecycle ownership', () {
    final source = cachedMermaidSource();
    final sourceContainer = containerFor(nodes: [source]);
    addTearDown(sourceContainer.dispose);
    expect(
      sourceContainer
          .read(documentNodesProvider.notifier)
          .convertMermaidNode(source.id)
          .isSuccess,
      isTrue,
    );

    final originalNodes = sourceContainer.read(documentNodesProvider);
    final originalEdges = sourceContainer.read(documentEdgesProvider);
    final imported = NestedDocumentCodec.parse(
      jsonEncode({
        'nodes': originalNodes.map((node) => node.toJson()).toList(),
        'edges': originalEdges.map((edge) => edge.toJson()).toList(),
      }),
    );
    final importedSource = imported.nodes.firstWhere(
      (node) => node.type == NodeType.mermaid,
    );
    final importedPayload = importedSource.payload as MermaidPayload;

    final editContainer = containerFor(
      nodes: imported.nodes,
      edges: imported.edges,
    );
    addTearDown(editContainer.dispose);
    final editableNode = editContainer
        .read(documentNodesProvider)
        .firstWhere((node) => importedPayload.nativeNodeIds.contains(node.id));
    editContainer
        .read(documentNodesProvider.notifier)
        .updateNode(editableNode.copyWith(x: editableNode.x + 12));
    expect(
      (editContainer
                  .read(documentNodesProvider)
                  .firstWhere((node) => node.id == importedSource.id)
                  .payload
              as MermaidPayload)
          .conversionStatus,
      MermaidConversionStatus.nativeEdited,
    );

    final deleteContainer = containerFor(
      nodes: imported.nodes,
      edges: imported.edges,
    );
    addTearDown(deleteContainer.dispose);
    deleteContainer.read(documentNodesProvider.notifier).deleteNodes([
      importedPayload.nativeNodeIds.first,
    ]);
    final afterDelete =
        deleteContainer
                .read(documentNodesProvider)
                .firstWhere((node) => node.id == importedSource.id)
                .payload
            as MermaidPayload;
    expect(afterDelete.nativeNodeIds, hasLength(1));
    expect(afterDelete.nativeEdgeIds, isEmpty);

    final lifecycleContainer = containerFor(
      nodes: imported.nodes,
      edges: imported.edges,
    );
    addTearDown(lifecycleContainer.dispose);
    final notifier = lifecycleContainer.read(documentNodesProvider.notifier);
    expect(notifier.regenerateMermaidNode(importedSource.id).isSuccess, isTrue);
    expect(
      lifecycleContainer
          .read(documentNodesProvider)
          .where((node) => node.mermaidSourceId == importedSource.id),
      hasLength(importedPayload.nativeNodeIds.length),
    );
    expect(lifecycleContainer.read(documentEdgesProvider), hasLength(1));

    expect(notifier.revertMermaidToSource(importedSource.id).isSuccess, isTrue);
    expect(lifecycleContainer.read(documentNodesProvider), [
      lifecycleContainer
          .read(documentNodesProvider)
          .singleWhere((node) => node.id == importedSource.id),
    ]);
    expect(lifecycleContainer.read(documentEdgesProvider), isEmpty);
  });

  test(
    'async conversion renders rich Mermaid and commits atomically',
    () async {
      final source = mermaidSource(
        source: 'sequenceDiagram\n  Alice->>Bob: Hello',
      );
      final renderer = _LifecycleRenderer();
      final unrelated = unrelatedNode();
      final unrelatedConnector = unrelatedEdge();
      final container = containerFor(
        nodes: [source, unrelated],
        edges: [unrelatedConnector],
        mermaidRenderer: renderer,
      );
      addTearDown(container.dispose);
      final notifier = container.read(documentNodesProvider.notifier);

      final result = await notifier.convertMermaidNodeAsync(source.id);

      expect(result.isSuccess, isTrue);
      expect(renderer.renderCalls, 1);
      final storedSource = container
          .read(documentNodesProvider)
          .firstWhere((node) => node.id == source.id);
      final payload = storedSource.payload as MermaidPayload;
      expect(storedSource.visible, isFalse);
      expect(payload.renderMode, MermaidRenderMode.native);
      expect(payload.diagramType, 'sequencediagram');
      expect(payload.nativeNodeIds, hasLength(2));
      expect(payload.nativeEdgeIds, hasLength(1));
      expect(container.read(documentNodesProvider), contains(unrelated));
      expect(
        container.read(documentEdgesProvider),
        contains(unrelatedConnector),
      );
      expect(container.read(historyProvider).undoStack, hasLength(1));

      notifier.undo();
      expect(container.read(documentNodesProvider), [source, unrelated]);
      expect(container.read(documentEdgesProvider), [unrelatedConnector]);

      notifier.redo();
      expect(
        (container
                    .read(documentNodesProvider)
                    .firstWhere((node) => node.id == source.id)
                    .payload
                as MermaidPayload)
            .nativeEdgeIds,
        hasLength(1),
      );
    },
  );

  test(
    'async conversion persists a fresh rendered SVG for later reuse',
    () async {
      final source = mermaidSource(
        source: 'sequenceDiagram\n  Alice->>Bob: Hello',
      );
      final renderer = _LifecycleRenderer();
      final container = containerFor(
        nodes: [source],
        mermaidRenderer: renderer,
      );
      addTearDown(container.dispose);
      final notifier = container.read(documentNodesProvider.notifier);

      final first = await notifier.convertMermaidNodeAsync(source.id);
      expect(first.isSuccess, isTrue);
      expect(renderer.renderCalls, 1);
      final converted = container
          .read(documentNodesProvider)
          .firstWhere((node) => node.id == source.id);
      final convertedPayload = converted.payload as MermaidPayload;
      expect(convertedPayload.cachedSvg, _asyncFixture);
      expect(convertedPayload.cachedSvgRevision, 0);
      expect(convertedPayload.cachedSvgConfigKey, isNotNull);
      expect(convertedPayload.rendererVersion, renderer.rendererVersion);

      expect(notifier.revertMermaidToSource(source.id).isSuccess, isTrue);
      final second = await notifier.convertMermaidNodeAsync(source.id);

      expect(second.isSuccess, isTrue);
      expect(renderer.renderCalls, 1);
    },
  );

  test(
    'async regeneration replaces native edits from the cached SVG atomically',
    () async {
      final source = mermaidSource(
        source: 'sequenceDiagram\n  Alice->>Bob: Hello',
      );
      final renderer = _LifecycleRenderer();
      final container = containerFor(
        nodes: [source],
        mermaidRenderer: renderer,
      );
      addTearDown(container.dispose);
      final notifier = container.read(documentNodesProvider.notifier);

      expect(
        (await notifier.convertMermaidNodeAsync(source.id)).isSuccess,
        isTrue,
      );
      final convertedSource = container
          .read(documentNodesProvider)
          .firstWhere((node) => node.id == source.id);
      final payload = convertedSource.payload as MermaidPayload;
      final generated = container
          .read(documentNodesProvider)
          .firstWhere((node) => payload.nativeNodeIds.contains(node.id));
      notifier.updateNode(generated.copyWith(x: generated.x + 40));

      final result = await notifier.regenerateMermaidNodeAsync(source.id);

      expect(result.isSuccess, isTrue);
      expect(renderer.renderCalls, 1);
      expect(
        container
            .read(documentNodesProvider)
            .where((node) => node.mermaidSourceId == source.id),
        hasLength(2),
      );
      expect(
        container
            .read(documentNodesProvider)
            .where((node) => node.id == generated.id)
            .single
            .x,
        isNot(greaterThan(generated.x)),
      );
      final regeneratedPayload =
          container
                  .read(documentNodesProvider)
                  .firstWhere((node) => node.id == source.id)
                  .payload
              as MermaidPayload;
      expect(
        regeneratedPayload.conversionStatus,
        MermaidConversionStatus.converted,
      );
      expect(container.read(historyProvider).undoStack, hasLength(3));
    },
  );

  test(
    'async conversion falls back to rendering when the cache identity is stale',
    () async {
      const config = MermaidRenderConfig();
      final source =
          mermaidSource(
            source: 'sequenceDiagram\n  Alice->>Bob: Hello',
          ).copyWith(
            payload: MermaidPayload(
              source: 'sequenceDiagram\n  Alice->>Bob: Hello',
              cachedSvg: _asyncFixture,
              cachedSvgRevision: 0,
              cachedSvgConfigKey: config.cacheKey,
              rendererVersion: 'old-renderer',
            ),
          );
      final renderer = _LifecycleRenderer();
      final container = containerFor(
        nodes: [source],
        mermaidRenderer: renderer,
      );
      addTearDown(container.dispose);

      final result = await container
          .read(documentNodesProvider.notifier)
          .convertMermaidNodeAsync(source.id);

      expect(result.isSuccess, isTrue);
      expect(renderer.renderCalls, 1);
      expect(
        (container
                    .read(documentNodesProvider)
                    .firstWhere((node) => node.id == source.id)
                    .payload
                as MermaidPayload)
            .rendererVersion,
        renderer.rendererVersion,
      );
    },
  );

  test(
    'async conversion rejects generated ID conflicts without mutation',
    () async {
      final source = mermaidSource(
        source: 'sequenceDiagram\n  Alice->>Bob: Hello',
      );
      final conflicting = unrelatedNode().copyWith(
        id: '${source.id}__mermaid_node_0',
      );
      final renderer = _LifecycleRenderer();
      final container = containerFor(
        nodes: [source, conflicting],
        mermaidRenderer: renderer,
      );
      addTearDown(container.dispose);

      final result = await container
          .read(documentNodesProvider.notifier)
          .convertMermaidNodeAsync(source.id);

      expect(result.isSuccess, isFalse);
      expect(result.diagnostic?.code, 'MERMAID_ID_CONFLICT');
      expect(container.read(documentNodesProvider), [source, conflicting]);
      expect(container.read(documentEdgesProvider), isEmpty);
      expect(container.read(historyProvider).undoStack, isEmpty);
    },
  );

  test(
    'async conversion reuses a matching cached SVG without rendering',
    () async {
      const config = MermaidRenderConfig();
      final source =
          mermaidSource(
            source: 'sequenceDiagram\n  Alice->>Bob: Hello',
          ).copyWith(
            payload: MermaidPayload(
              source: 'sequenceDiagram\n  Alice->>Bob: Hello',
              cachedSvg: _asyncFixture,
              cachedSvgRevision: 0,
              cachedSvgConfigKey: config.cacheKey,
              rendererVersion: 'lifecycle-test-renderer',
            ),
          );
      final renderer = _LifecycleRenderer();
      final container = containerFor(
        nodes: [source],
        mermaidRenderer: renderer,
      );
      addTearDown(container.dispose);

      final result = await container
          .read(documentNodesProvider.notifier)
          .convertMermaidNodeAsync(source.id);

      expect(result.isSuccess, isTrue);
      expect(renderer.renderCalls, 0);
    },
  );

  test(
    'async conversion rejects duplicate and stale requests atomically',
    () async {
      final source = mermaidSource(
        source: 'sequenceDiagram\n  Alice->>Bob: Hello',
      );
      final renderer = _LifecycleRenderer()
        ..pendingRender = Completer<MermaidRenderResult>();
      final container = containerFor(
        nodes: [source],
        mermaidRenderer: renderer,
      );
      addTearDown(container.dispose);
      final notifier = container.read(documentNodesProvider.notifier);

      final first = notifier.convertMermaidNodeAsync(source.id);
      expect(
        container.read(mermaidConversionInFlightProvider),
        contains(source.id),
      );
      final duplicate = await notifier.convertMermaidNodeAsync(source.id);
      expect(duplicate.isSuccess, isFalse);
      expect(duplicate.diagnostic?.code, 'CONVERSION_IN_PROGRESS');

      final updatedPayload = (source.payload as MermaidPayload).updateSource(
        'sequenceDiagram\n  Alice->>Bob: Changed',
      );
      notifier.updateMermaidSource(source.id, updatedPayload);
      renderer.pendingRender!.complete(
        const MermaidRenderResult(
          svg: _asyncFixture,
          diagramType: 'sequencediagram',
        ),
      );

      final stale = await first;
      expect(stale.isSuccess, isFalse);
      expect(stale.diagnostic?.code, 'STALE_CONVERSION');
      expect(container.read(mermaidConversionInFlightProvider), isEmpty);
      expect(container.read(documentNodesProvider), hasLength(1));
      expect(container.read(documentEdgesProvider), isEmpty);
      expect(container.read(historyProvider).undoStack, hasLength(1));
    },
  );

  test('failed async conversion preserves the document and history', () async {
    final source = mermaidSource(
      source: 'sequenceDiagram\n  Alice->>Bob: Hello',
    );
    final renderer = _LifecycleRenderer()
      ..svg = '<svg><script>x</script></svg>';
    final container = containerFor(nodes: [source], mermaidRenderer: renderer);
    addTearDown(container.dispose);
    final notifier = container.read(documentNodesProvider.notifier);

    final result = await notifier.convertMermaidNodeAsync(source.id);

    expect(result.isSuccess, isFalse);
    expect(result.diagnostic, isNotNull);
    expect(container.read(documentNodesProvider), [source]);
    expect(container.read(documentEdgesProvider), isEmpty);
    expect(container.read(historyProvider).undoStack, isEmpty);
  });

  test('converts and undoes the complete native graph atomically', () {
    final source = cachedMermaidSource();
    final unrelated = unrelatedNode();
    final unrelatedConnector = unrelatedEdge();
    final container = containerFor(
      nodes: [source, unrelated],
      edges: [unrelatedConnector],
    );
    addTearDown(container.dispose);
    final notifier = container.read(documentNodesProvider.notifier);

    final result = notifier.convertMermaidNode(source.id);

    expect(result.isSuccess, isTrue);
    final convertedNodes = container.read(documentNodesProvider);
    final convertedSource = convertedNodes.firstWhere(
      (node) => node.id == source.id,
    );
    final convertedPayload = convertedSource.payload as MermaidPayload;
    expect(convertedSource.visible, isFalse);
    expect(convertedPayload.renderMode, MermaidRenderMode.native);
    expect(
      convertedPayload.conversionStatus,
      MermaidConversionStatus.converted,
    );
    expect(
      convertedNodes
          .where((node) => convertedPayload.nativeNodeIds.contains(node.id))
          .every((node) => node.mermaidSourceId == source.id),
      isTrue,
    );
    expect(
      container
          .read(documentEdgesProvider)
          .where((edge) => convertedPayload.nativeEdgeIds.contains(edge.id))
          .every((edge) => edge.mermaidSourceId == source.id),
      isTrue,
    );
    expect(convertedNodes.where((node) => node.id == unrelated.id), [
      unrelated,
    ]);
    expect(container.read(documentEdgesProvider), contains(unrelatedConnector));
    expect(container.read(historyProvider).undoStack, hasLength(1));

    notifier.undo();

    expect(container.read(documentNodesProvider), [source, unrelated]);
    expect(container.read(documentEdgesProvider), [unrelatedConnector]);
    expect(container.read(historyProvider).redoStack, hasLength(1));

    notifier.redo();

    expect(
      container
          .read(documentNodesProvider)
          .where((node) => node.id == source.id),
      hasLength(1),
    );
    expect(
      (container
                  .read(documentNodesProvider)
                  .firstWhere((node) => node.id == source.id)
                  .payload
              as MermaidPayload)
          .nativeNodeIds,
      isNotEmpty,
    );
    expect(container.read(documentEdgesProvider), contains(unrelatedConnector));
  });

  test(
    'marks native edits and regenerate discards them in one undoable step',
    () {
      final source = cachedMermaidSource();
      final container = containerFor(nodes: [source]);
      addTearDown(container.dispose);
      final notifier = container.read(documentNodesProvider.notifier);

      expect(notifier.convertMermaidNode(source.id).isSuccess, isTrue);
      final converted = container
          .read(documentNodesProvider)
          .firstWhere((node) => node.id == source.id);
      final payload = converted.payload as MermaidPayload;
      final generated = container
          .read(documentNodesProvider)
          .firstWhere((node) => payload.nativeNodeIds.contains(node.id));

      notifier.updateNode(generated.copyWith(x: generated.x + 40));
      expect(
        (container
                    .read(documentNodesProvider)
                    .firstWhere((node) => node.id == source.id)
                    .payload
                as MermaidPayload)
            .conversionStatus,
        MermaidConversionStatus.nativeEdited,
      );

      final editedX = container
          .read(documentNodesProvider)
          .firstWhere((node) => node.id == generated.id)
          .x;
      expect(notifier.regenerateMermaidNode(source.id).isSuccess, isTrue);
      final regeneratedNode = container
          .read(documentNodesProvider)
          .firstWhere((node) => node.id == generated.id);
      expect(regeneratedNode.x, isNot(editedX));
      expect(
        (container
                    .read(documentNodesProvider)
                    .firstWhere((node) => node.id == source.id)
                    .payload
                as MermaidPayload)
            .conversionStatus,
        MermaidConversionStatus.converted,
      );

      notifier.undo();
      expect(
        container
            .read(documentNodesProvider)
            .firstWhere((node) => node.id == generated.id)
            .x,
        editedX,
      );
      expect(
        (container
                    .read(documentNodesProvider)
                    .firstWhere((node) => node.id == source.id)
                    .payload
                as MermaidPayload)
            .conversionStatus,
        MermaidConversionStatus.nativeEdited,
      );
    },
  );

  test(
    'revert removes native objects and restores source preview through history',
    () {
      final source = cachedMermaidSource();
      final container = containerFor(nodes: [source]);
      addTearDown(container.dispose);
      final notifier = container.read(documentNodesProvider.notifier);

      expect(notifier.convertMermaidNode(source.id).isSuccess, isTrue);
      expect(notifier.revertMermaidToSource(source.id).isSuccess, isTrue);
      expect(container.read(documentNodesProvider), hasLength(1));
      final revertedSource = container.read(documentNodesProvider).single;
      expect(revertedSource.id, source.id);
      expect(revertedSource.visible, isTrue);
      expect(
        (revertedSource.payload as MermaidPayload).renderMode,
        MermaidRenderMode.sourcePreview,
      );
      expect((revertedSource.payload as MermaidPayload).nativeNodeIds, isEmpty);
      expect(container.read(documentEdgesProvider), isEmpty);

      notifier.undo();
      final restoredNativeSource = container
          .read(documentNodesProvider)
          .firstWhere((node) => node.id == source.id);
      expect(restoredNativeSource.visible, isFalse);
      expect(
        (restoredNativeSource.payload as MermaidPayload).renderMode,
        MermaidRenderMode.native,
      );
      expect(container.read(documentNodesProvider).length, greaterThan(1));

      notifier.redo();
      expect(container.read(documentNodesProvider), hasLength(1));
      final redoneSource = container.read(documentNodesProvider).single;
      expect(redoneSource.id, source.id);
      expect(redoneSource.visible, isTrue);
      expect(
        (redoneSource.payload as MermaidPayload).renderMode,
        MermaidRenderMode.sourcePreview,
      );
    },
  );

  test('editing native source removes generated objects and is undoable', () {
    final source = cachedMermaidSource();
    final container = containerFor(nodes: [source]);
    addTearDown(container.dispose);
    final notifier = container.read(documentNodesProvider.notifier);

    expect(notifier.convertMermaidNode(source.id).isSuccess, isTrue);
    final nativePayload =
        container
                .read(documentNodesProvider)
                .firstWhere((node) => node.id == source.id)
                .payload
            as MermaidPayload;
    final updatedPayload = nativePayload.updateSource(
      'flowchart LR\n  X[New] --> Y[Source]',
    );

    notifier.updateMermaidSource(source.id, updatedPayload);

    expect(container.read(documentNodesProvider), hasLength(1));
    final updatedSource = container.read(documentNodesProvider).single;
    expect(updatedSource.visible, isTrue);
    expect((updatedSource.payload as MermaidPayload).source, contains('New'));
    expect(container.read(documentEdgesProvider), isEmpty);

    notifier.undo();
    expect(container.read(documentNodesProvider).length, greaterThan(1));
    expect(
      (container
                  .read(documentNodesProvider)
                  .firstWhere((node) => node.id == source.id)
                  .payload
              as MermaidPayload)
          .renderMode,
      MermaidRenderMode.native,
    );
  });

  test(
    'deleting a Mermaid source removes its native graph as one history step',
    () {
      final source = cachedMermaidSource();
      final container = containerFor(nodes: [source]);
      addTearDown(container.dispose);
      final notifier = container.read(documentNodesProvider.notifier);

      expect(notifier.convertMermaidNode(source.id).isSuccess, isTrue);
      notifier.deleteNodes([source.id]);

      expect(container.read(documentNodesProvider), isEmpty);
      expect(container.read(documentEdgesProvider), isEmpty);
      expect(container.read(historyProvider).undoStack, hasLength(2));

      notifier.undo();
      expect(container.read(documentNodesProvider).length, greaterThan(1));
      expect(
        container
            .read(documentNodesProvider)
            .firstWhere((node) => node.id == source.id)
            .visible,
        isFalse,
      );

      notifier.redo();
      expect(container.read(documentNodesProvider), isEmpty);
    },
  );

  test(
    'deleting a generated node keeps the source linked to remaining native content',
    () {
      final source = cachedMermaidSource();
      final container = containerFor(nodes: [source]);
      addTearDown(container.dispose);
      final notifier = container.read(documentNodesProvider.notifier);

      expect(notifier.convertMermaidNode(source.id).isSuccess, isTrue);
      final convertedSource = container
          .read(documentNodesProvider)
          .firstWhere((node) => node.id == source.id);
      final payload = convertedSource.payload as MermaidPayload;
      final deletedNativeId = payload.nativeNodeIds.first;

      notifier.deleteNodes([deletedNativeId]);

      final remainingSource = container
          .read(documentNodesProvider)
          .firstWhere((node) => node.id == source.id);
      final remainingPayload = remainingSource.payload as MermaidPayload;
      expect(remainingPayload.renderMode, MermaidRenderMode.native);
      expect(
        remainingPayload.conversionStatus,
        MermaidConversionStatus.nativeEdited,
      );
      expect(remainingPayload.nativeNodeIds, hasLength(1));
      expect(remainingPayload.nativeEdgeIds, isEmpty);
      expect(container.read(documentNodesProvider), hasLength(2));
      expect(container.read(documentEdgesProvider), isEmpty);

      notifier.undo();
      expect(container.read(documentNodesProvider), hasLength(3));
      expect(container.read(documentEdgesProvider), hasLength(1));
      expect(
        (container
                    .read(documentNodesProvider)
                    .firstWhere((node) => node.id == source.id)
                    .payload
                as MermaidPayload)
            .nativeNodeIds,
        hasLength(2),
      );
    },
  );

  test(
    'deleting a native Mermaid edge updates source metadata and is undoable',
    () {
      final source = cachedMermaidSource();
      final container = containerFor(nodes: [source]);
      addTearDown(container.dispose);
      final notifier = container.read(documentNodesProvider.notifier);

      expect(notifier.convertMermaidNode(source.id).isSuccess, isTrue);
      final convertedSource = container
          .read(documentNodesProvider)
          .firstWhere((node) => node.id == source.id);
      final payload = convertedSource.payload as MermaidPayload;
      final nativeEdgeId = payload.nativeEdgeIds.single;

      notifier.deleteEdges([nativeEdgeId]);

      final editedSource = container
          .read(documentNodesProvider)
          .firstWhere((node) => node.id == source.id);
      final editedPayload = editedSource.payload as MermaidPayload;
      expect(editedPayload.renderMode, MermaidRenderMode.native);
      expect(
        editedPayload.conversionStatus,
        MermaidConversionStatus.nativeEdited,
      );
      expect(editedPayload.nativeEdgeIds, isEmpty);
      expect(container.read(documentEdgesProvider), isEmpty);

      notifier.undo();
      final restoredSource = container
          .read(documentNodesProvider)
          .firstWhere((node) => node.id == source.id);
      expect(
        (restoredSource.payload as MermaidPayload).conversionStatus,
        MermaidConversionStatus.converted,
      );
      expect(container.read(documentEdgesProvider), hasLength(1));
    },
  );

  test('ignores forged Mermaid ownership metadata during source deletion', () {
    final source = mermaidSource().copyWith(
      visible: false,
      payload: MermaidPayload(
        source: 'flowchart TD\n  A[Start] --> B[End]',
        renderMode: MermaidRenderMode.native,
        conversionStatus: MermaidConversionStatus.converted,
        nativeNodeIds: const ['unrelated-node'],
        nativeEdgeIds: const ['unrelated-edge'],
      ),
    );
    final unrelated = unrelatedNode();
    final connector = unrelatedEdge();
    final container = containerFor(
      nodes: [source, unrelated],
      edges: [connector],
    );
    addTearDown(container.dispose);
    final notifier = container.read(documentNodesProvider.notifier);

    notifier.deleteNodes([source.id]);

    expect(container.read(documentNodesProvider), [unrelated]);
    expect(container.read(documentEdgesProvider), [connector]);
  });

  test('failed conversion leaves nodes, edges, and history unchanged', () {
    final source = mermaidSource(
      source: 'flowchart TD\n  subgraph Unsafe\n    A[Hidden]\n  end',
    );
    final unrelated = unrelatedNode();
    final connector = unrelatedEdge();
    final container = containerFor(
      nodes: [source, unrelated],
      edges: [connector],
    );
    addTearDown(container.dispose);
    final notifier = container.read(documentNodesProvider.notifier);

    final result = notifier.convertMermaidNode(source.id);

    expect(result.isSuccess, isFalse);
    expect(container.read(documentNodesProvider), [source, unrelated]);
    expect(container.read(documentEdgesProvider), [connector]);
    expect(container.read(historyProvider).undoStack, isEmpty);
  });
}
