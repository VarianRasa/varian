import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/data/artifacts/artifact_store_bundle.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/durable_asset_reference.dart';
import 'package:varian/features/ai/data/image_artifact_store.dart';
import 'package:varian/features/ai/data/video_artifact_store.dart';
import 'package:varian/features/assets/data/asset_service.dart';
import 'package:varian/features/assets/data/file_artifact_store.dart';
import 'package:varian/features/assets/data/image_relink_service.dart';
import 'package:varian/features/canvas/state/autosave_controller.dart';
import 'package:varian/features/canvas/state/design_token_provider.dart';
import 'package:varian/features/canvas/state/document_edges_provider.dart';
import 'package:varian/features/canvas/state/document_assets_provider.dart';
import 'package:varian/features/canvas/domain/document_asset_registry.dart';
import 'package:varian/features/canvas/utils/frame_presets.dart';
import 'package:varian/features/canvas/presentation/dialogs/frame_preset_dialog.dart';
import 'package:varian/features/canvas/presentation/widgets/color_picker_dialog.dart';
import 'package:varian/features/canvas/domain/rich_text_editing.dart';
import 'package:varian/features/canvas/presentation/widgets/table_matrix_editor_modal.dart';
import 'package:varian/features/canvas/presentation/widgets/todo_list_editor_modal.dart';
import 'package:varian/features/canvas/presentation/widgets/column_card_editor_modal.dart';
import 'package:varian/features/canvas/presentation/widgets/nested_board_screen.dart';
import 'package:varian/features/canvas/presentation/widgets/component_editor_modal.dart';
import 'package:varian/features/canvas/presentation/widgets/sketch_card_editor_dialog.dart';
import 'package:varian/features/canvas/presentation/widgets/annotation_pin_editor_dialog.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/file_preview_router.dart';
import 'package:varian/features/document/presentation/document_editor_screen.dart';
import 'package:varian/features/document/utils/document_paper_presets.dart';
import 'package:varian/features/canvas/utils/canvas_image_cache.dart';
import 'package:varian/features/canvas/utils/canvas_storage_resolver_provider.dart';
import 'package:varian/features/media/image_crop_screen.dart';
import 'package:varian/features/media/embed_webview_screen.dart';
import 'package:varian/features/media/embed_url_service.dart';
import 'package:varian/features/media/map_location_service.dart';
import 'package:varian/features/media/map_viewer_screen.dart';
import 'package:varian/features/media/media_timeline_editor_dialog.dart';
import 'package:varian/features/media/data/media_artifact_store.dart';
import 'package:varian/features/media/state/media_processing_provider.dart';
import 'package:varian/features/presentation/prototype_interaction_editor_dialog.dart';
import 'package:varian/features/link_card/domain/link_url_policy.dart';
import 'package:varian/features/link_card/presentation/link_card_inspector.dart';
import 'package:varian/features/link_card/state/link_preview_controller.dart';
import '../../../../domain/models/component_payload.dart';
import '../../../../domain/models/drawing_payload.dart';
import '../../../../domain/models/model3d_payload.dart';
import '../../../model3d/presentation/model3d_inspector.dart';
import '../../../../domain/models/node.dart';
import '../../../../domain/models/node_payload.dart';
import '../../../../domain/models/media_timeline.dart';
import '../../../mermaid/domain/mermaid_conversion.dart';
import '../../../../domain/models/rich_text.dart';
import '../../../../domain/models/vector_path_payload.dart';
import '../../../history/history_provider.dart';
import '../../state/document_nodes_provider.dart';
import '../../state/selection_provider.dart';
import '../../domain/canvas_precision.dart';
import '../../utils/align_engine.dart';

class _InspectorTextField extends StatefulWidget {
  final String value;
  final String? label;
  final String? hint;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const _InspectorTextField({
    required this.value,
    this.label,
    this.hint,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  @override
  State<_InspectorTextField> createState() => _InspectorTextFieldState();
}

class _InspectorTextFieldState extends State<_InspectorTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _syncingController = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode()..addListener(_syncWhenUnfocused);
  }

  @override
  void didUpdateWidget(covariant _InspectorTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncWhenUnfocused();
  }

  void _syncWhenUnfocused() {
    if (_focusNode.hasFocus || _controller.text == widget.value) return;
    _syncingController = true;
    try {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    } finally {
      _syncingController = false;
    }
  }

  void _handleChanged(String value) {
    if (!_syncingController) widget.onChanged?.call(value);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_syncWhenUnfocused)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UiTextField(
    controller: _controller,
    focusNode: _focusNode,
    label: widget.label,
    hint: widget.hint,
    minLines: widget.minLines,
    maxLines: widget.maxLines,
    keyboardType: widget.keyboardType,
    onChanged: _handleChanged,
    onSubmitted: widget.onSubmitted,
  );
}

class _InspectorNumberInput extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _InspectorNumberInput({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final text = value % 1 == 0
        ? value.toInt().toString()
        : value.toStringAsFixed(1);

    void parse(String raw) {
      final parsed = double.tryParse(raw);
      if (parsed != null) onChanged(parsed);
    }

    return _InspectorTextField(
      value: text,
      label: label,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: parse,
      onSubmitted: parse,
    );
  }
}

class _InspectorSelect<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  const _InspectorSelect({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final items = <String, T>{
      for (final option in options) option.$2: option.$1,
    };
    final selectedValue = items.values.contains(value) ? value : null;

    return UiSelect<T>(
      label: label,
      value: selectedValue,
      hint: options.isEmpty ? 'No options' : 'Select $label',
      items: items,
      enabled: options.isNotEmpty,
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}

typedef ArtifactOperationCurrent =
    bool Function({
      required int generation,
      required String projectId,
      required String? accountId,
    });

class InspectorPanel extends ConsumerWidget {
  final String projectId;
  final double width;
  final int Function()? beginArtifactOperation;
  final ArtifactOperationCurrent? artifactOperationCurrent;
  final ValueChanged<CanvasNode>? onResetModel3d;
  final ValueChanged<CanvasNode>? onRetryModel3d;
  final Future<void> Function(CanvasNode node)? onReplaceModel3d;
  final ValueChanged<CanvasNode>? onEditMermaid;
  final ValueChanged<CanvasNode>? onEditChartData;
  final ImageArtifactStore? imageArtifactStore;
  final FileArtifactStore? fileArtifactStore;
  final VideoArtifactStore? videoArtifactStore;
  final MediaArtifactStore? mediaArtifactStore;
  final CanvasImageCache? imageCache;

  CanvasImageCache _cache() => imageCache ?? CanvasImageCache.instance;

  ImageArtifactStore _imageStore(WidgetRef ref) =>
      imageArtifactStore ??
      ref.read(artifactStoreBundleProvider).imageArtifactStore;

  FileArtifactStore _fileStore(WidgetRef ref) =>
      fileArtifactStore ??
      ref.read(artifactStoreBundleProvider).fileArtifactStore;

  VideoArtifactStore _videoStore(WidgetRef ref) =>
      videoArtifactStore ??
      ref.read(artifactStoreBundleProvider).videoArtifactStore;

  MediaArtifactStore _mediaStore(WidgetRef ref) =>
      mediaArtifactStore ??
      ref.read(artifactStoreBundleProvider).mediaArtifactStore;

  String? _validatedImageStoragePath(WidgetRef ref, String? rawPath) {
    final value = rawPath?.trim();
    if (value == null || value.isEmpty || value != rawPath) return null;
    final resolver = ref.read(canvasStorageResolverProvider(projectId));
    return resolver.parseReference(path: value, projectId: projectId)?.path;
  }

  void _upsertDocumentAsset(
    WidgetRef ref, {
    required String assetId,
    required DocumentAssetKind kind,
    required String name,
    required String mimeType,
    required String? artifactReference,
    required String? storagePath,
    required int? declaredSize,
    required Uint8List? bytes,
  }) {
    final existing = ref.read(documentAssetsProvider)[assetId];
    final asset = buildDocumentAsset(
      id: assetId,
      kind: kind,
      name: name,
      mimeType: mimeType,
      artifactReference: artifactReference,
      storagePath: storagePath,
      declaredSize: declaredSize,
      bytes: bytes,
      existing: existing,
    );
    if (asset != null) {
      ref.read(documentAssetsProvider.notifier).upsert(asset);
    }
  }

  String _imageAssetId(WidgetRef ref, CanvasNode node, ImagePayload payload) =>
      stableDocumentAssetId(
        candidate: payload.assetId,
        manifest: ref.read(documentAssetsProvider),
        nodes: ref.read(documentNodesProvider),
        ownerNodeId: node.id,
      );

  String _mediaAssetId(WidgetRef ref, CanvasNode node, String? candidate) =>
      stableDocumentAssetId(
        candidate: candidate,
        manifest: ref.read(documentAssetsProvider),
        nodes: ref.read(documentNodesProvider),
        ownerNodeId: node.id,
      );

  const InspectorPanel({
    super.key,
    this.projectId = 'default',
    this.width = 280,
    this.beginArtifactOperation,
    this.artifactOperationCurrent,
    this.onResetModel3d,
    this.onRetryModel3d,
    this.onReplaceModel3d,
    this.onEditMermaid,
    this.onEditChartData,
    this.imageArtifactStore,
    this.fileArtifactStore,
    this.videoArtifactStore,
    this.mediaArtifactStore,
    this.imageCache,
  });

  int _beginArtifactOperation() => beginArtifactOperation?.call() ?? 0;

  bool _isArtifactOperationCurrent({
    required int generation,
    required String? accountId,
  }) {
    final checker = artifactOperationCurrent;
    if (checker == null) return true;
    return checker(
      generation: generation,
      projectId: projectId,
      accountId: accountId,
    );
  }

  CanvasNode? _currentNode(WidgetRef ref, String nodeId) {
    for (final candidate in ref.read(documentNodesProvider)) {
      if (candidate.id == nodeId) return candidate;
    }
    return null;
  }

  CanvasNode? _currentReplacementNode({
    required WidgetRef ref,
    required CanvasNode capturedNode,
    required int generation,
    required String? accountId,
  }) {
    if (!_isArtifactOperationCurrent(
      generation: generation,
      accountId: accountId,
    )) {
      return null;
    }
    final current = _currentNode(ref, capturedNode.id);
    if (current == null ||
        !canCommitDocumentAssetReplacement(
          capturedNode: capturedNode,
          currentNode: current,
          operationProjectId: projectId,
          currentProjectId: projectId,
          expectedAccountId: accountId,
          currentAccountId: ref.read(supabaseSyncServiceProvider).currentUserId,
        )) {
      return null;
    }
    return current;
  }

  Widget _mapNumberField(
    String label,
    double value,
    bool Function(double) validator,
    ValueChanged<double> onValid,
  ) => _buildNumberInput(label, value, (parsed) {
    if (validator(parsed)) onValid(parsed);
  });

  MediaTimeline _videoTimeline(VideoPayload payload) =>
      payload.mediaTimeline ??
      MediaTimeline(
        sourceDurationMs:
            payload.durationMs ?? parseMediaDurationMs(payload.durationText),
        caption: payload.caption,
      );

  MediaTimeline _audioTimeline(AudioPayload payload) =>
      payload.mediaTimeline ??
      MediaTimeline(
        sourceDurationMs:
            (payload.durationSeconds ??
                parseMediaDurationMs(payload.durationText) ~/ 1000) *
            1000,
        playbackSpeed: payload.playbackSpeed,
      );

  Future<void> _editMediaTimeline(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
    MediaTimeline timeline,
    String title,
    NodePayload Function(MediaTimeline) payloadWithTimeline,
  ) async {
    final edited = await showUiDialog<MediaTimeline>(
      context: context,
      builder: (_) => MediaTimelineEditorDialog(
        initialTimeline: timeline,
        mediaTitle: title,
      ),
    );
    if (edited == null || !context.mounted) return;
    final updatedNode = node.copyWith(payload: payloadWithTimeline(edited));
    ref.read(documentNodesProvider.notifier).updateNode(updatedNode);
    unawaited(_processMediaTimeline(ref, updatedNode, edited, context));
  }

  Future<void> _processMediaTimeline(
    WidgetRef ref,
    CanvasNode node,
    MediaTimeline timeline,
    BuildContext context,
  ) async {
    final sourceKey = _mediaSourceKey(node);
    if (sourceKey == null) return;
    final inputChecksum = sha256
        .convert(utf8.encode('$sourceKey|${jsonEncode(timeline.toJson())}'))
        .toString();
    final isVideo = node.payload is VideoPayload;
    final artifactKinds = isVideo
        ? const [
            MediaArtifactKind.proxy,
            MediaArtifactKind.thumbnail,
            MediaArtifactKind.waveform,
            MediaArtifactKind.preview,
            MediaArtifactKind.export,
          ]
        : const [
            MediaArtifactKind.proxy,
            MediaArtifactKind.waveform,
            MediaArtifactKind.preview,
            MediaArtifactKind.export,
          ];
    try {
      final processed = await ref
          .read(mediaProcessingCoordinatorProvider)
          .processTimeline(
            id: 'media-${node.id}-${inputChecksum.substring(0, 16)}',
            sourceKey: sourceKey,
            inputChecksum: inputChecksum,
            timeline: timeline,
            artifactKinds: artifactKinds,
            storagePolicy: MediaStoragePolicy.cache,
            maxAttempts: 2,
            metadata: {'sourceMimeType': isVideo ? 'video/mp4' : 'audio/mpeg'},
          );
      final current = ref
          .read(documentNodesProvider)
          .where((candidate) => candidate.id == node.id)
          .firstOrNull;
      if (current == null) return;
      final nextPayload = current.payload is VideoPayload
          ? (current.payload as VideoPayload).copyWith(mediaTimeline: processed)
          : current.payload is AudioPayload
          ? (current.payload as AudioPayload).copyWith(mediaTimeline: processed)
          : null;
      if (nextPayload != null) {
        ref
            .read(documentNodesProvider.notifier)
            .updateNode(current.copyWith(payload: nextPayload));
      }
    } catch (error) {
      if (context.mounted) {
        showUiToast(
          context,
          'Media processing failed: $error',
          variant: UiToastVariant.error,
        );
      }
    }
  }

  String? _mediaSourceKey(CanvasNode node) {
    final source = switch (node.payload) {
      VideoPayload payload =>
        payload.videoArtifactReference ?? payload.videoPath ?? payload.videoUrl,
      AudioPayload payload =>
        payload.audioArtifactReference ?? payload.audioPath ?? payload.audioUrl,
      _ => null,
    };
    final trimmed = source?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  String _audioMimeTypeForFileName(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    return switch (extension) {
      'aac' => 'audio/aac',
      'flac' => 'audio/flac',
      'm4a' => 'audio/mp4',
      'ogg' => 'audio/ogg',
      'wav' => 'audio/wav',
      _ => 'audio/mpeg',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.appTokens;
    final selectedIds = ref.watch(selectionProvider);
    final nodes = ref.watch(documentNodesProvider);
    final edges = ref.watch(documentEdgesProvider);

    Widget emptySelection() => Container(
      width: width,
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(
          left: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
        ),
      ),
      child: const UiEmptyState(
        icon: Icons.tune_outlined,
        title: 'NO SELECTION',
        message: 'Pick an element to adjust parameters',
      ),
    );

    if (selectedIds.isEmpty) {
      return emptySelection();
    }

    // Check if selected element is a Smart Connector Edge
    final selectedEdgeMatch = edges
        .where((e) => e.id == selectedIds.first)
        .toList();
    if (selectedEdgeMatch.isNotEmpty) {
      final selectedEdge = selectedEdgeMatch.first;
      return Container(
        width: width,
        padding: const EdgeInsets.all(AppSpacing.page),
        decoration: BoxDecoration(
          color: tokens.panel,
          border: Border(
            left: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
          ),
        ),
        child: ListView(
          children: [
            _buildConnectorHeader(context, ref, selectedEdge),
            Divider(color: tokens.panelBorder, height: AppSpacing.xl),
            _buildConnectorControls(context, ref, selectedEdge),
          ],
        ),
      );
    }

    final selectedNode = nodes
        .where((n) => n.id == selectedIds.first)
        .firstOrNull;
    if (selectedNode == null) return emptySelection();

    final isMultiSelection = selectedIds.length > 1;
    final selectedNodeCount = nodes
        .where((node) => selectedIds.contains(node.id))
        .length;
    final selectedFrame =
        !isMultiSelection && selectedNode.type == NodeType.frame
        ? selectedNode
        : null;
    final hasFrameChildren =
        selectedFrame != null &&
        nodes.any((node) => node.parentId == selectedFrame.id);
    final mermaidSource = !isMultiSelection
        ? nodes.where((candidate) {
            if (candidate.type != NodeType.mermaid ||
                candidate.payload is! MermaidPayload) {
              return false;
            }
            final payload = candidate.payload as MermaidPayload;
            return candidate.id == selectedNode.id ||
                payload.nativeNodeIds.contains(selectedNode.id);
          }).firstOrNull
        : null;

    return Container(
      width: width,
      padding: const EdgeInsets.all(AppSpacing.page),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(
          left: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
        ),
      ),
      child: ListView(
        children: [
          if (isMultiSelection) ...[
            _buildMultiSelectHeader(context, ref, selectedIds.toList()),
            Divider(color: tokens.panelBorder, height: AppSpacing.pageWide),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Container(
                    key: const ValueKey('inspector-node-type-chip'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.panelElevated,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: tokens.panelBorder,
                        width: AppBorder.thin,
                      ),
                    ),
                    child: Text(
                      selectedNode.type.name.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
                UiIconButton(
                  tooltip: selectedNode.locked
                      ? 'Unlock object'
                      : 'Lock object',
                  icon: selectedNode.locked ? Icons.lock : Icons.lock_open,
                  onPressed: () {
                    ref
                        .read(documentNodesProvider.notifier)
                        .updateNode(
                          selectedNode.copyWith(locked: !selectedNode.locked),
                        );
                  },
                ),
                UiIconButton(
                  tooltip: 'Object History',
                  icon: Icons.history,
                  onPressed: () =>
                      _showNodeHistoryDialog(context, ref, selectedNode),
                ),
              ],
            ),
            Divider(color: tokens.panelBorder, height: AppSpacing.pageWide),
          ],
          _buildTidyBoardSection(
            context,
            ref,
            selectedIds.toList(),
            selectedNodeCount: selectedNodeCount,
            selectedFrame: selectedFrame,
            hasFrameChildren: hasFrameChildren,
          ),
          Divider(color: tokens.panelBorder, height: AppSpacing.pageWide),
          if (mermaidSource != null) ...[
            _buildMermaidControls(context, ref, mermaidSource),
            Divider(color: tokens.panelBorder, height: AppSpacing.pageWide),
          ],
          if (!isMultiSelection) ...[
            _buildTransformSection(context, ref, selectedNode),
            if (selectedNode.parentId != null) ...[
              const SizedBox(height: AppSpacing.lg),
              _buildConstraintsSection(context, ref, selectedNode),
            ],
            if (selectedNode.pins.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _buildUniversalPinsSection(context, ref, selectedNode),
            ],
            const SizedBox(height: AppSpacing.lg),
            _buildPayloadControls(context, ref, selectedNode),
            const SizedBox(height: AppSpacing.lg),
            _buildPrototypeControls(context, ref, selectedNode, nodes),
          ],
        ],
      ),
    );
  }

  Widget _buildPrototypeControls(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
    List<CanvasNode> nodes,
  ) {
    final tokens = context.appTokens;
    final interactions = node.prototypeInteractions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'PROTOTYPE',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: tokens.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            UiButton(
              variant: UiButtonVariant.outline,
              size: UiButtonSize.sm,
              prefix: const Icon(Icons.account_tree_outlined, size: 13),
              onPressed: () async {
                final edited = await PrototypeInteractionEditorDialog.show(
                  context,
                  sourceNodeId: node.id,
                  sourceNodeLabel: node.name ?? node.id,
                  initialInteractions: interactions,
                  initialStateId: node.prototypeStateId,
                  nodes: nodes,
                );
                if (edited == null || !context.mounted) return;
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        prototypeInteractions: edited.interactions,
                        prototypeStateId: edited.stateId,
                      ),
                    );
              },
              child: const Text('Configure'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        Text(
          interactions.isEmpty
              ? 'No triggers configured.'
              : '${interactions.length} trigger(s) · state: ${node.prototypeStateId ?? 'default'}',
          style: TextStyle(color: tokens.textMuted, fontSize: 11),
        ),
        if (interactions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          for (final interaction in interactions.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '${interaction.trigger.name} → ${interaction.action.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: interaction.enabled ? tokens.text : tokens.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
          if (interactions.length > 3)
            Text(
              '+ ${interactions.length - 3} more',
              style: TextStyle(color: tokens.textMuted, fontSize: 10),
            ),
        ],
      ],
    );
  }

  Widget _buildUniversalPinsSection(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
  ) {
    final tokens = context.appTokens;
    final unresolvedCount = node.pins.where((p) => !p.isResolved).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'PINNED ANNOTATIONS',
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: tokens.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs + AppSpacing.xxs,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: unresolvedCount > 0 ? tokens.danger : tokens.success,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${node.pins.length} pins ($unresolvedCount open)',
                style: TextStyle(
                  color: tokens.handle,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ...List.generate(node.pins.length, (idx) {
          final pin = node.pins[idx];
          final pinColor = pin.isResolved
              ? tokens.success
              : (pin.status == AnnotationPinStatus.issue
                    ? tokens.danger
                    : pin.color);

          return Container(
            margin: const EdgeInsets.only(
              bottom: AppSpacing.xs + AppSpacing.xxs,
            ),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: tokens.panelElevated,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: pin.isResolved
                    ? tokens.success.withValues(alpha: 0.3)
                    : tokens.panelBorder,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: pinColor,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    pin.isResolved ? '✓' : '${idx + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pin.text.isNotEmpty
                            ? pin.text
                            : 'Pin #${idx + 1} (No description)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: pin.isResolved
                              ? context.appTokens.textMuted
                              : context.appTokens.text,
                          fontSize: 11,
                          decoration: pin.isResolved
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      Text(
                        'By ${pin.author} • ${pin.status.name.toUpperCase()}',
                        style: TextStyle(
                          color: context.appTokens.textMuted,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                UiIconButton(
                  icon: Icons.edit,
                  tooltip: 'Edit Pin',
                  size: UiButtonSize.sm,
                  onPressed: () {
                    showUiDialog(
                      context: context,
                      builder: (ctx) => AnnotationPinEditorDialog(
                        pin: pin,
                        pinIndex: idx,
                        onSave: (updatedPin) {
                          final newPins = List<ImageAnnotationPin>.from(
                            node.pins,
                          );
                          newPins[idx] = updatedPin;
                          ref
                              .read(documentNodesProvider.notifier)
                              .updateNode(node.copyWith(pins: newPins));
                        },
                        onDelete: () {
                          final newPins = List<ImageAnnotationPin>.from(
                            node.pins,
                          )..removeAt(idx);
                          ref
                              .read(documentNodesProvider.notifier)
                              .updateNode(node.copyWith(pins: newPins));
                        },
                      ),
                    );
                  },
                ),
                UiIconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete Pin',
                  variant: UiButtonVariant.destructive,
                  size: UiButtonSize.sm,
                  onPressed: () {
                    final newPins = List<ImageAnnotationPin>.from(node.pins)
                      ..removeAt(idx);
                    ref
                        .read(documentNodesProvider.notifier)
                        .updateNode(node.copyWith(pins: newPins));
                  },
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMultiSelectHeader(
    BuildContext context,
    WidgetRef ref,
    List<String> selectedIds,
  ) {
    final tokens = context.appTokens;
    final selectedNodes = ref.read(documentNodesProvider);
    final selectedImages = selectedNodes
        .where(
          (node) =>
              selectedIds.contains(node.id) &&
              node.type == NodeType.image &&
              node.payload is ImagePayload,
        )
        .toList(growable: false);
    final canBatchRelink = selectedImages.length > 1;
    return Row(
      children: [
        Flexible(
          child: Text(
            '${selectedIds.length} ITEMS SELECTED',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: tokens.accent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        if (canBatchRelink) ...[
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: UiButton(
                onPressed: () => _batchRelinkImages(context, ref, selectedIds),
                variant: UiButtonVariant.outline,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.link, size: 14),
                child: const Text('Relink Images'),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: UiButton(
              onPressed: () {
                final groupId = ref
                    .read(documentNodesProvider.notifier)
                    .groupNodes(selectedIds);
                if (groupId != null) {
                  ref.read(selectionProvider.notifier).select(groupId);
                }
              },
              variant: UiButtonVariant.outline,
              size: UiButtonSize.sm,
              prefix: const Icon(Icons.folder_outlined),
              child: const Text('Group (Ctrl+G)'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTidyBoardSection(
    BuildContext context,
    WidgetRef ref,
    List<String> selectedIds, {
    required int selectedNodeCount,
    required CanvasNode? selectedFrame,
    required bool hasFrameChildren,
  }) {
    final tokens = context.appTokens;
    final canAlign = selectedNodeCount >= 2;
    final canDistribute = selectedNodeCount >= 3;
    final framePayload = selectedFrame?.payload;
    final frameHasAutoLayout =
        framePayload is FramePayload &&
        framePayload.layoutDirection != AutoLayoutDirection.none;
    final canApplyAutoLayout =
        selectedFrame != null && hasFrameChildren && frameHasAutoLayout;
    final autoLayoutTooltip = selectedFrame == null || !hasFrameChildren
        ? 'Apply Auto Layout (select a frame with children)'
        : !frameHasAutoLayout
        ? 'Apply Auto Layout (choose Row or Col first)'
        : 'Apply Auto Layout to frame children';
    final notifier = ref.read(documentNodesProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TIDY BOARD',
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final alignmentButtons = [
              _buildIconButton(
                icon: Icons.align_horizontal_left,
                tooltip: 'Align Left',
                onPressed: canAlign
                    ? () => notifier.alignNodes(selectedIds, AlignmentType.left)
                    : null,
              ),
              _buildIconButton(
                icon: Icons.align_horizontal_center,
                tooltip: 'Align Horizontal Center',
                onPressed: canAlign
                    ? () =>
                          notifier.alignNodes(selectedIds, AlignmentType.center)
                    : null,
              ),
              _buildIconButton(
                icon: Icons.align_horizontal_right,
                tooltip: 'Align Right',
                onPressed: canAlign
                    ? () =>
                          notifier.alignNodes(selectedIds, AlignmentType.right)
                    : null,
              ),
              _buildIconButton(
                icon: Icons.align_vertical_top,
                tooltip: 'Align Top',
                onPressed: canAlign
                    ? () => notifier.alignNodes(selectedIds, AlignmentType.top)
                    : null,
              ),
              _buildIconButton(
                icon: Icons.align_vertical_center,
                tooltip: 'Align Vertical Middle',
                onPressed: canAlign
                    ? () =>
                          notifier.alignNodes(selectedIds, AlignmentType.middle)
                    : null,
              ),
              _buildIconButton(
                icon: Icons.align_vertical_bottom,
                tooltip: 'Align Bottom',
                onPressed: canAlign
                    ? () =>
                          notifier.alignNodes(selectedIds, AlignmentType.bottom)
                    : null,
              ),
            ];
            if (constraints.maxWidth >=
                AppControlSize.minimumHitTarget * alignmentButtons.length) {
              return Row(
                key: const ValueKey('inspector-alignment-actions-wide'),
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: alignmentButtons,
              );
            }
            return Column(
              key: const ValueKey('inspector-alignment-actions-compact'),
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  key: const ValueKey('inspector-horizontal-alignment-actions'),
                  spacing: AppSpacing.xs,
                  children: alignmentButtons.take(3).toList(growable: false),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  key: const ValueKey('inspector-vertical-alignment-actions'),
                  spacing: AppSpacing.xs,
                  children: alignmentButtons.skip(3).toList(growable: false),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            alignment: WrapAlignment.start,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                child: UiButton(
                  onPressed: canDistribute
                      ? () => notifier.distributeNodes(
                          selectedIds,
                          DistributionType.horizontal,
                        )
                      : null,
                  variant: UiButtonVariant.outline,
                  size: UiButtonSize.sm,
                  prefix: const Icon(Icons.horizontal_distribute, size: 14),
                  semanticsLabel: 'Distribute Horizontally',
                  child: const Text('Distribute H'),
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                child: UiButton(
                  onPressed: canDistribute
                      ? () => notifier.distributeNodes(
                          selectedIds,
                          DistributionType.vertical,
                        )
                      : null,
                  variant: UiButtonVariant.outline,
                  size: UiButtonSize.sm,
                  prefix: const Icon(Icons.vertical_distribute, size: 14),
                  semanticsLabel: 'Distribute Vertically',
                  child: const Text('Distribute V'),
                ),
              ),
            ],
          ),
        ),
        if (selectedFrame != null) ...[
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              width: constraints.maxWidth,
              child: UiButton(
                onPressed: canApplyAutoLayout
                    ? () => notifier.applyAutoLayoutToFrame(selectedFrame.id)
                    : null,
                variant: UiButtonVariant.outline,
                size: UiButtonSize.sm,
                mainAxisSize: MainAxisSize.max,
                prefix: const Icon(Icons.auto_awesome_motion, size: 14),
                semanticsLabel: autoLayoutTooltip,
                child: Text(
                  'Apply Auto Layout',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) => UiIconButton(icon: icon, tooltip: tooltip, onPressed: onPressed);

  Widget _buildTransformSection(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
  ) {
    final tokens = context.appTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'COORDINATES & SIZE',
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _buildNumberInput('X', node.x, (val) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(node.copyWith(x: val));
              }),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _buildNumberInput('Y', node.y, (val) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(node.copyWith(y: val));
              }),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildNumberInput('Rotation (°)', node.rotation * 180 / math.pi, (
          value,
        ) {
          if (!value.isFinite) return;
          ref
              .read(documentNodesProvider.notifier)
              .updateNode(node.copyWith(rotation: value * math.pi / 180));
        }),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _buildNumberInput('W', node.width, (val) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(node.copyWith(width: val));
              }),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _buildNumberInput('H', node.height, (val) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(node.copyWith(height: val));
              }),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Text(
              'Opacity',
              style: TextStyle(color: tokens.textMuted, fontSize: 12),
            ),
            Expanded(
              child: _buildSlider(
                value: node.opacity,
                min: 0.0,
                max: 1.0,
                onChanged: (val) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(node.copyWith(opacity: val));
                },
              ),
            ),
            Text(
              '${(node.opacity * 100).toInt()}%',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConstraintsSection(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
  ) {
    final tokens = context.appTokens;
    final current = node.constraints;
    final horizontal = current?.horizontal ?? CanvasHorizontalConstraint.left;
    final vertical = current?.vertical ?? CanvasVerticalConstraint.top;

    void updateConstraints(CanvasNodeConstraints next) {
      ref
          .read(documentNodesProvider.notifier)
          .updateNode(node.copyWith(constraints: next));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'RESPONSIVE CONSTRAINTS',
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: tokens.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            if (current != null)
              UiButton(
                key: ValueKey('clear_constraints_${node.id}'),
                variant: UiButtonVariant.ghost,
                size: UiButtonSize.sm,
                onPressed: () => ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(node.copyWith(constraints: null)),
                child: const Text('Clear'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _InspectorSelect<CanvasHorizontalConstraint>(
          key: ValueKey('horizontal_constraint_${node.id}'),
          label: 'Horizontal',
          value: horizontal,
          options: const [
            (CanvasHorizontalConstraint.left, 'Left'),
            (CanvasHorizontalConstraint.center, 'Center'),
            (CanvasHorizontalConstraint.right, 'Right'),
            (CanvasHorizontalConstraint.leftRight, 'Left & Right'),
            (CanvasHorizontalConstraint.scale, 'Scale'),
          ],
          onChanged: (value) => updateConstraints(
            (current ?? const CanvasNodeConstraints()).copyWith(
              horizontal: value,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _InspectorSelect<CanvasVerticalConstraint>(
          key: ValueKey('vertical_constraint_${node.id}'),
          label: 'Vertical',
          value: vertical,
          options: const [
            (CanvasVerticalConstraint.top, 'Top'),
            (CanvasVerticalConstraint.center, 'Center'),
            (CanvasVerticalConstraint.bottom, 'Bottom'),
            (CanvasVerticalConstraint.topBottom, 'Top & Bottom'),
            (CanvasVerticalConstraint.scale, 'Scale'),
          ],
          onChanged: (value) => updateConstraints(
            (current ?? const CanvasNodeConstraints()).copyWith(
              vertical: value,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        Text(
          node.parentId == null
              ? 'Assign this node to a frame to apply constraints.'
              : 'Constraints follow the parent frame when it resizes.',
          style: TextStyle(color: tokens.textMuted, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildModel3DControls(CanvasNode node, Model3DPayload payload) =>
      Model3DInspectorControls(
        node: node,
        payload: payload,
        onReset: onResetModel3d == null ? null : () => onResetModel3d!(node),
        onRetry: onRetryModel3d == null ? null : () => onRetryModel3d!(node),
        onReplace: onReplaceModel3d == null
            ? null
            : () => onReplaceModel3d!(node),
      );

  Widget _buildChartControls(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
    ChartPayload payload,
  ) {
    final tokens = context.appTokens;

    void update(ChartPayload next) {
      ref
          .read(documentNodesProvider.notifier)
          .updateNode(node.copyWith(payload: next));
    }

    void updateSeries(int index, ChartSeries next) {
      final nextSeries = List<ChartSeries>.from(payload.series);
      if (index < 0 || index >= nextSeries.length) return;
      nextSeries[index] = next;
      update(payload.copyWith(series: nextSeries));
    }

    Widget toggle(String label, bool value, ValueChanged<bool> onChanged) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.text, fontSize: 11),
            ),
          ),
          Transform.scale(
            scale: 0.82,
            child: UiSwitch(value: value, onChange: onChanged),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CHART',
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        if (onEditChartData != null && payload.databaseTableName == null) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: UiButton(
              key: ValueKey('chart_edit_data_${node.id}'),
              variant: UiButtonVariant.outline,
              prefix: const Icon(Icons.table_chart_outlined, size: 14),
              onPressed: () => onEditChartData!(node),
              child: Text(
                payload.tableSourceNodeId == null
                    ? 'Edit Data Table'
                    : 'Edit Source Table',
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        _InspectorSelect<ChartType>(
          label: 'Chart Type',
          value: payload.chartType,
          options: const [
            (ChartType.line, 'Line'),
            (ChartType.bar, 'Bar / Column'),
            (ChartType.pie, 'Pie'),
            (ChartType.doughnut, 'Doughnut'),
            (ChartType.scatter, 'Scatter'),
            (ChartType.radar, 'Radar'),
          ],
          onChanged: (value) => update(payload.copyWith(chartType: value)),
        ),
        const SizedBox(height: AppSpacing.sm),
        Builder(
          builder: (_) {
            final tableNodes = ref
                .read(documentNodesProvider)
                .where(
                  (candidate) =>
                      candidate.type == NodeType.tableGrid &&
                      candidate.payload is TablePayload,
                )
                .toList();
            final sourceNode = tableNodes
                .where((candidate) => candidate.id == payload.tableSourceNodeId)
                .firstOrNull;
            final sourcePayload = sourceNode?.payload as TablePayload?;
            final sourceOptions = <(String, String)>[
              ('', 'Manual Data'),
              for (final candidate in tableNodes)
                (
                  candidate.id,
                  (candidate.payload as TablePayload).name.trim().isEmpty
                      ? 'Table ${candidate.id.substring(0, 6)}'
                      : (candidate.payload as TablePayload).name,
                ),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InspectorSelect<String>(
                  label: 'Table Source',
                  value: payload.tableSourceNodeId ?? '',
                  options: sourceOptions,
                  onChanged: (value) {
                    if (value.isEmpty) {
                      update(
                        payload.copyWith(
                          clearTableSource: true,
                          clearDataSourceUrl: true,
                          clearDatabaseTable: true,
                        ),
                      );
                    } else {
                      update(
                        payload.copyWith(
                          tableSourceNodeId: value,
                          tableCategoryColumn: 0,
                          tableValueColumns: const [],
                          clearDataSourceUrl: true,
                          clearDatabaseTable: true,
                        ),
                      );
                    }
                  },
                ),
                if (sourcePayload != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _InspectorSelect<int>(
                    label: 'Category Column',
                    value: payload.tableCategoryColumn,
                    options: [
                      for (
                        var index = 0;
                        index < sourcePayload.columns.length;
                        index++
                      )
                        (index, sourcePayload.columns[index]),
                    ],
                    onChanged: (value) =>
                        update(payload.copyWith(tableCategoryColumn: value)),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        _InspectorTextField(
          key: ValueKey('chart_data_source_url_${node.id}'),
          value: payload.dataSourceUrl ?? '',
          label: 'JSON / API URL',
          hint: 'https://example.com/chart.json',
          keyboardType: TextInputType.url,
          onSubmitted: (value) {
            if (value.trim().isEmpty) {
              update(payload.copyWith(clearDataSourceUrl: true));
            } else {
              update(
                payload.copyWith(
                  dataSourceUrl: value,
                  clearTableSource: true,
                  clearDatabaseTable: true,
                ),
              );
            }
          },
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        SizedBox(
          width: double.infinity,
          child: UiButton(
            key: ValueKey('chart_refresh_source_${node.id}'),
            variant: UiButtonVariant.outline,
            prefix: const Icon(Icons.refresh, size: 14),
            onPressed: payload.dataSourceUrl == null
                ? null
                : () => update(
                    payload.copyWith(
                      dataRefreshRevision: payload.dataRefreshRevision + 1,
                    ),
                  ),
            child: const Text('Refresh Source'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'DATABASE SOURCE',
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _InspectorTextField(
          key: ValueKey('chart_database_table_${node.id}'),
          value: payload.databaseTableName ?? '',
          label: 'Database Table',
          hint: 'sales_chart',
          onSubmitted: (value) {
            if (value.trim().isEmpty) {
              update(payload.copyWith(clearDatabaseTable: true));
            } else {
              update(
                payload.copyWith(
                  databaseTableName: value,
                  clearTableSource: true,
                  clearDataSourceUrl: true,
                ),
              );
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        _InspectorTextField(
          key: ValueKey('chart_database_category_${node.id}'),
          value: payload.databaseCategoryColumn,
          label: 'Database Category Column',
          hint: 'category',
          onSubmitted: (value) =>
              update(payload.copyWith(databaseCategoryColumn: value)),
        ),
        const SizedBox(height: AppSpacing.sm),
        _InspectorTextField(
          key: ValueKey('chart_database_values_${node.id}'),
          value: payload.databaseValueColumns.join(', '),
          label: 'Database Value Columns',
          hint: 'revenue, cost',
          onSubmitted: (value) => update(
            payload.copyWith(
              databaseValueColumns: value
                  .split(',')
                  .map((item) => item.trim())
                  .where((item) => item.isNotEmpty)
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _InspectorTextField(
          key: ValueKey('chart_database_limit_${node.id}'),
          value: payload.databaseRowLimit.toString(),
          label: 'Database Row Limit',
          hint: '1-100',
          keyboardType: TextInputType.number,
          onSubmitted: (value) {
            final limit = int.tryParse(value.trim());
            if (limit != null) {
              update(payload.copyWith(databaseRowLimit: limit));
            }
          },
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        SizedBox(
          width: double.infinity,
          child: UiButton(
            key: ValueKey('chart_refresh_database_${node.id}'),
            variant: UiButtonVariant.outline,
            prefix: const Icon(Icons.storage_outlined, size: 14),
            onPressed: payload.databaseTableName == null
                ? null
                : () => update(
                    payload.copyWith(
                      dataRefreshRevision: payload.dataRefreshRevision + 1,
                    ),
                  ),
            child: const Text('Refresh DB'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _InspectorTextField(
          key: ValueKey('chart_title_${node.id}'),
          value: payload.title,
          label: 'Title',
          onChanged: (value) => update(payload.copyWith(title: value)),
        ),
        const SizedBox(height: AppSpacing.sm),
        _InspectorTextField(
          key: ValueKey('chart_categories_${node.id}'),
          value: payload.categories.join(', '),
          label: 'Categories',
          hint: 'Q1, Q2, Q3, Q4',
          onChanged: (value) {
            final categories = value
                .split(',')
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .take(100)
                .toList();
            update(
              payload.copyWith(
                categories: categories.isEmpty
                    ? const ['A', 'B', 'C']
                    : categories,
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        _InspectorTextField(
          key: ValueKey('chart_category_filter_${node.id}'),
          value: payload.categoryFilter,
          label: 'Category Filter',
          hint: 'e.g. Q1 or North',
          onChanged: (value) => update(payload.copyWith(categoryFilter: value)),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'SERIES DATA',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        for (var index = 0; index < payload.series.length; index++) ...[
          Container(
            key: ValueKey('inspector-chart-series-card-${node.id}-$index'),
            padding: const EdgeInsets.all(AppSpacing.sm),
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            decoration: BoxDecoration(
              color: tokens.panelElevated,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: tokens.panelBorder,
                width: AppBorder.thin,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _InspectorTextField(
                        key: ValueKey('chart_series_name_${node.id}_$index'),
                        value: payload.series[index].name,
                        label: 'Series ${index + 1}',
                        onChanged: (value) => updateSeries(
                          index,
                          payload.series[index].copyWith(name: value),
                        ),
                      ),
                    ),
                    if (payload.series.length > 1) ...[
                      const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                      UiIconButton(
                        icon: Icons.delete_outline,
                        tooltip: 'Remove series ${index + 1}',
                        variant: UiButtonVariant.destructive,
                        size: UiButtonSize.sm,
                        onPressed: () {
                          final nextSeries = List<ChartSeries>.from(
                            payload.series,
                          )..removeAt(index);
                          update(payload.copyWith(series: nextSeries));
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                _InspectorTextField(
                  key: ValueKey('chart_series_values_${node.id}_$index'),
                  value: payload.series[index].values
                      .map((value) => value.toString())
                      .join(', '),
                  label: 'Values',
                  hint: '4, 7, 5, 9',
                  onChanged: (value) => updateSeries(
                    index,
                    payload.series[index].copyWith(
                      values: _parseChartValues(value),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                _buildColorPickerTile(
                  context,
                  'Series Color',
                  payload.series[index].color,
                  (color) => updateSeries(
                    index,
                    payload.series[index].copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
        ],
        SizedBox(
          width: double.infinity,
          child: UiButton(
            variant: UiButtonVariant.outline,
            prefix: const Icon(Icons.add, size: 14),
            onPressed: payload.series.length >= 12
                ? null
                : () {
                    final index = payload.series.length;
                    update(
                      payload.copyWith(
                        series: [
                          ...payload.series,
                          ChartSeries(
                            name: 'Series ${index + 1}',
                            values: const [4, 7, 5, 9],
                            color: payload.colors.isEmpty
                                ? const Color(0xFFF97316)
                                : payload.colors[index % payload.colors.length],
                          ),
                        ],
                      ),
                    );
                  },
            child: const Text('Add Series'),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'DISPLAY',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        if (payload.chartType != ChartType.pie &&
            payload.chartType != ChartType.doughnut) ...[
          Text(
            'AXIS RANGE',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          Row(
            children: [
              Expanded(
                child: _InspectorTextField(
                  key: ValueKey('chart_min_y_${node.id}'),
                  value: payload.minY?.toString() ?? '',
                  label: 'Min Y',
                  hint: 'Auto',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  onChanged: (raw) {
                    final value = double.tryParse(raw.trim());
                    if (raw.trim().isEmpty) {
                      update(payload.copyWith(clearMinY: true));
                    } else if (value != null && value.isFinite) {
                      update(payload.copyWith(minY: value));
                    }
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _InspectorTextField(
                  key: ValueKey('chart_max_y_${node.id}'),
                  value: payload.maxY?.toString() ?? '',
                  label: 'Max Y',
                  hint: 'Auto',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  onChanged: (raw) {
                    final value = double.tryParse(raw.trim());
                    if (raw.trim().isEmpty) {
                      update(payload.copyWith(clearMaxY: true));
                    } else if (value != null && value.isFinite) {
                      update(payload.copyWith(maxY: value));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        toggle('Legend', payload.showLegend, (value) {
          update(payload.copyWith(showLegend: value));
        }),
        toggle('Grid', payload.showGrid, (value) {
          update(payload.copyWith(showGrid: value));
        }),
        toggle('Axes', payload.showAxes, (value) {
          update(payload.copyWith(showAxes: value));
        }),
        toggle('Show Values', payload.showValues, (value) {
          update(payload.copyWith(showValues: value));
        }),
        if (payload.chartType == ChartType.line ||
            payload.chartType == ChartType.bar ||
            payload.chartType == ChartType.scatter)
          toggle('Interactive Tooltips', payload.showTooltips, (value) {
            update(payload.copyWith(showTooltips: value));
          }),
        if (payload.chartType == ChartType.line) ...[
          toggle('Curved Lines', payload.lineCurved, (value) {
            update(payload.copyWith(lineCurved: value));
          }),
          toggle('Point Dots', payload.showDots, (value) {
            update(payload.copyWith(showDots: value));
          }),
        ],
        if (payload.chartType == ChartType.bar) ...[
          const SizedBox(height: AppSpacing.sm),
          _InspectorSelect<ChartBarOrientation>(
            label: 'Bar Orientation',
            value: payload.barOrientation,
            options: const [
              (ChartBarOrientation.vertical, 'Vertical / Column'),
              (ChartBarOrientation.horizontal, 'Horizontal / Bar'),
            ],
            onChanged: (value) =>
                update(payload.copyWith(barOrientation: value)),
          ),
        ],
        if (payload.chartType == ChartType.doughnut) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildNumberInput(
            'Hole Ratio',
            payload.doughnutHoleRatio,
            (value) => update(
              payload.copyWith(doughnutHoleRatio: value.clamp(0.0, 0.9)),
            ),
          ),
        ],
      ],
    );
  }

  List<double> _parseChartValues(String raw) {
    return raw
        .split(RegExp(r'[,\\s]+'))
        .map(double.tryParse)
        .whereType<double>()
        .where((value) => value.isFinite)
        .take(100)
        .toList();
  }

  Widget _buildPayloadControls(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
  ) {
    final tokens = context.appTokens;
    final designTokens = ref.watch(designTokenSetProvider);
    if (node.payload is Model3DPayload) {
      return _buildModel3DControls(node, node.payload as Model3DPayload);
    }
    if (node.payload is FramePayload) {
      return _buildFrameControls(
        context,
        ref,
        node,
        node.payload as FramePayload,
      );
    } else if (node.payload is ChartPayload) {
      return _buildChartControls(
        context,
        ref,
        node,
        node.payload as ChartPayload,
      );
    } else if (node.payload is ShapePayload) {
      final payload = node.payload as ShapePayload;
      final isRectangle = node.type == NodeType.rectangle;
      final isEllipse = node.type == NodeType.ellipse;
      final isDiamond = node.type == NodeType.diamond;
      final isCylinder = node.type == NodeType.cylinder;
      final isParallelogram = node.type == NodeType.parallelogram;
      final isLineOrArrow =
          node.type == NodeType.line || node.type == NodeType.arrow;
      final supportsRichShape =
          isRectangle ||
          isEllipse ||
          isDiamond ||
          isCylinder ||
          isParallelogram ||
          isLineOrArrow;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TRANSFORM',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              UiButton(
                variant: UiButtonVariant.outline,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.rotate_right, size: 14),
                onPressed: () {
                  final nextRotation =
                      (node.rotation + (math.pi / 2)) % (2 * math.pi);
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(node.copyWith(rotation: nextRotation));
                },
                child: const Text('Rotate 90°'),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${(node.rotation * 180 / math.pi).round()}°',
                style: TextStyle(color: tokens.textMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (!isLineOrArrow) ...[
            Text(
              'SURFACE & CORNERS',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildColorPickerTile(context, 'Fill Color', payload.fill, (
              newColor,
            ) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(fill: newColor)),
                  );
            }),
            if (supportsRichShape) ...[
              const SizedBox(height: AppSpacing.sm),
              _InspectorSelect<FillType>(
                label: 'Fill Type',
                value: payload.fillType,
                options: const [
                  (FillType.solid, 'Solid'),
                  (FillType.linearGradient, 'Linear Gradient'),
                  (FillType.radialGradient, 'Radial Gradient'),
                  (FillType.angularGradient, 'Angular Gradient'),
                ],
                onChanged: (value) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(
                            fillType: value,
                            fillGradientEnd:
                                payload.fillGradientEnd ??
                                const Color(0xFF1E1B4B),
                          ),
                        ),
                      );
                },
              ),
              if (payload.fillType != FillType.solid) ...[
                const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                _buildColorPickerTile(
                  context,
                  'Gradient End',
                  payload.fillGradientEnd ?? const Color(0xFF1E1B4B),
                  (newColor) {
                    ref
                        .read(documentNodesProvider.notifier)
                        .updateNode(
                          node.copyWith(
                            payload: payload.copyWith(
                              fillGradientEnd: newColor,
                            ),
                          ),
                        );
                  },
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              _buildNumberInput('Fill Opacity', payload.fillOpacity, (val) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          fillOpacity: val.clamp(0.0, 1.0),
                        ),
                      ),
                    );
              }),
            ],
          ] else ...[
            Text(
              'LINE ROUTING & CAPS',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _InspectorSelect<LineRouting>(
              label: 'Routing',
              value: payload.lineRouting,
              options: const [
                (LineRouting.straight, 'Straight ───'),
                (LineRouting.orthogonal, 'Elbow / Step ┌─┘'),
                (LineRouting.curved, 'Curved Arc ~~~'),
              ],
              onChanged: (value) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(lineRouting: value),
                      ),
                    );
              },
            ),
            if (payload.lineRouting == LineRouting.curved) ...[
              const SizedBox(height: AppSpacing.sm),
              _buildNumberInput('Curve Depth', payload.curveDepth, (val) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          curveDepth: val.clamp(-1.5, 1.5),
                        ),
                      ),
                    );
              }),
            ],
            const SizedBox(height: AppSpacing.sm),
            _InspectorSelect<LineMarker>(
              label: 'Start Cap',
              value: payload.startMarker,
              options: const [
                (LineMarker.none, 'None ───'),
                (LineMarker.arrow, 'Arrow 🡐'),
                (LineMarker.circle, 'Circle ●'),
                (LineMarker.diamond, 'Diamond ◆'),
              ],
              onChanged: (value) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(startMarker: value),
                      ),
                    );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            _InspectorSelect<LineMarker>(
              label: 'End Cap',
              value: payload.endMarker,
              options: const [
                (LineMarker.none, 'None ───'),
                (LineMarker.arrow, 'Arrow 🡒'),
                (LineMarker.circle, 'Circle ●'),
                (LineMarker.diamond, 'Diamond ◆'),
              ],
              onChanged: (value) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(endMarker: value),
                      ),
                    );
              },
            ),
          ],
          if (isRectangle) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Independent Corners',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall!.copyWith(color: tokens.text),
                  ),
                ),
                UiSwitch(
                  value: payload.independentCorners,
                  onChange: (val) {
                    ref
                        .read(documentNodesProvider.notifier)
                        .updateNode(
                          node.copyWith(
                            payload: payload.copyWith(
                              independentCorners: val,
                              topLeftRadius: payload.cornerRadius,
                              topRightRadius: payload.cornerRadius,
                              bottomRightRadius: payload.cornerRadius,
                              bottomLeftRadius: payload.cornerRadius,
                            ),
                          ),
                        );
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            if (!payload.independentCorners) ...[
              _buildNumberInput('Corner Radius', payload.cornerRadius, (val) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          cornerRadius: val.clamp(0.0, 500.0),
                          topLeftRadius: val.clamp(0.0, 500.0),
                          topRightRadius: val.clamp(0.0, 500.0),
                          bottomRightRadius: val.clamp(0.0, 500.0),
                          bottomLeftRadius: val.clamp(0.0, 500.0),
                        ),
                      ),
                    );
              }),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _buildNumberInput('TL', payload.topLeftRadius, (
                      val,
                    ) {
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateNode(
                            node.copyWith(
                              payload: payload.copyWith(
                                topLeftRadius: val.clamp(0.0, 500.0),
                              ),
                            ),
                          );
                    }),
                  ),
                  const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                  Expanded(
                    child: _buildNumberInput('TR', payload.topRightRadius, (
                      val,
                    ) {
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateNode(
                            node.copyWith(
                              payload: payload.copyWith(
                                topRightRadius: val.clamp(0.0, 500.0),
                              ),
                            ),
                          );
                    }),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
              Row(
                children: [
                  Expanded(
                    child: _buildNumberInput('BL', payload.bottomLeftRadius, (
                      val,
                    ) {
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateNode(
                            node.copyWith(
                              payload: payload.copyWith(
                                bottomLeftRadius: val.clamp(0.0, 500.0),
                              ),
                            ),
                          );
                    }),
                  ),
                  const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                  Expanded(
                    child: _buildNumberInput('BR', payload.bottomRightRadius, (
                      val,
                    ) {
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateNode(
                            node.copyWith(
                              payload: payload.copyWith(
                                bottomRightRadius: val.clamp(0.0, 500.0),
                              ),
                            ),
                          );
                    }),
                  ),
                ],
              ),
            ],
          ] else if (isEllipse) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'ARC / DONUT',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildNumberInput('Start Angle', payload.startAngle, (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(startAngle: val % 360.0),
                    ),
                  );
            }),
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            _buildNumberInput('Sweep Angle', payload.sweepAngle, (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(
                        sweepAngle: val.clamp(0.1, 360.0),
                      ),
                    ),
                  );
            }),
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            _buildNumberInput('Inner Radius', payload.innerRadiusRatio, (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(
                        innerRadiusRatio: val.clamp(0.0, 0.99),
                      ),
                    ),
                  );
            }),
          ] else if (isDiamond) ...[
            const SizedBox(height: AppSpacing.sm),
            _buildNumberInput('Corner Fillet', payload.cornerRadius, (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(
                        cornerRadius: val.clamp(0.0, 100.0),
                      ),
                    ),
                  );
            }),
          ] else if (isCylinder) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'STORAGE TIERS & CAP',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildNumberInput(
              'Partitions',
              payload.cylinderPartitions.toDouble(),
              (val) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          cylinderPartitions: val.toInt().clamp(1, 6),
                        ),
                      ),
                    );
              },
            ),
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            _buildNumberInput('Cap Ratio', payload.cylinderCapRatio, (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(
                        cylinderCapRatio: val.clamp(0.1, 0.5),
                      ),
                    ),
                  );
            }),
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            _buildBranchInput('Status Badge', payload.badgeText, (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(badgeText: val)),
                  );
            }),
          ] else if (isParallelogram) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'SKEW & DATA I/O',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildNumberInput('Skew Ratio', payload.skewRatio, (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(
                        skewRatio: val.clamp(-0.45, 0.45),
                      ),
                    ),
                  );
            }),
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            _buildNumberInput('Corner Fillet', payload.cornerRadius, (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(
                        cornerRadius: val.clamp(0.0, 100.0),
                      ),
                    ),
                  );
            }),
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            _InspectorSelect<String>(
              label: 'I/O Direction',
              value: payload.ioType.isEmpty ? 'none' : payload.ioType,
              options: const [
                ('none', 'None'),
                ('input', '📥 Input'),
                ('output', '📤 Output'),
                ('io', '🔄 I/O'),
                ('stream', '📡 Stream'),
              ],
              onChanged: (value) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          ioType: value == 'none' ? '' : value,
                        ),
                      ),
                    );
              },
            ),
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            _buildBranchInput('Data Schema', payload.subText, (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(subText: val)),
                  );
            }),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            'BORDER / STROKE',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildColorPickerTile(context, 'Stroke Color', payload.stroke, (
            newColor,
          ) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: payload.copyWith(stroke: newColor)),
                );
          }),
          const SizedBox(height: AppSpacing.sm),
          _buildNumberInput('Stroke Width', payload.strokeWidth, (val) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(
                    payload: payload.copyWith(
                      strokeWidth: val.clamp(0.0, 100.0),
                    ),
                  ),
                );
          }),
          if (supportsRichShape) ...[
            const SizedBox(height: AppSpacing.sm),
            _InspectorSelect<StrokeStyle>(
              label: 'Stroke Style',
              value: payload.strokeStyle,
              options: const [
                (StrokeStyle.solid, 'Solid ───'),
                (StrokeStyle.dashed, 'Dashed ╌╌╌'),
                (StrokeStyle.dotted, 'Dotted ···'),
              ],
              onChanged: (value) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(strokeStyle: value),
                      ),
                    );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'EFFECTS',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Drop Shadow',
                    style: TextStyle(color: tokens.text, fontSize: 11),
                  ),
                ),
                UiSwitch(
                  value: payload.hasShadow,
                  onChange: (val) {
                    ref
                        .read(documentNodesProvider.notifier)
                        .updateNode(
                          node.copyWith(
                            payload: payload.copyWith(hasShadow: val),
                          ),
                        );
                  },
                ),
              ],
            ),
            if (payload.hasShadow) ...[
              const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
              _buildColorPickerTile(
                context,
                'Shadow Color',
                payload.shadowColor,
                (c) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(shadowColor: c),
                        ),
                      );
                },
              ),
              const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
              _buildNumberInput('Shadow Blur', payload.shadowBlur, (val) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          shadowBlur: val.clamp(0.0, 100.0),
                        ),
                      ),
                    );
              }),
              const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
              Row(
                children: [
                  Expanded(
                    child: _buildNumberInput(
                      'Offset X',
                      payload.shadowOffsetX,
                      (val) {
                        ref
                            .read(documentNodesProvider.notifier)
                            .updateNode(
                              node.copyWith(
                                payload: payload.copyWith(shadowOffsetX: val),
                              ),
                            );
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                  Expanded(
                    child: _buildNumberInput(
                      'Offset Y',
                      payload.shadowOffsetY,
                      (val) {
                        ref
                            .read(documentNodesProvider.notifier)
                            .updateNode(
                              node.copyWith(
                                payload: payload.copyWith(shadowOffsetY: val),
                              ),
                            );
                      },
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text(
              'EMBEDDED LABEL',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _InspectorTextField(
              value: payload.label,
              hint: 'Center label text...',
              onChanged: (val) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(payload: payload.copyWith(label: val)),
                    );
              },
            ),
            if (payload.label.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _buildColorPickerTile(
                context,
                'Label Color',
                payload.labelColor,
                (c) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(payload: payload.copyWith(labelColor: c)),
                      );
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildNumberInput('Label Size', payload.labelFontSize, (val) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          labelFontSize: val.clamp(8.0, 72.0),
                        ),
                      ),
                    );
              }),
            ],
            if (isDiamond) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                'BRANCH LABELS',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _buildBranchInput('Top', payload.branchTop, (val) {
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateNode(
                            node.copyWith(
                              payload: payload.copyWith(branchTop: val),
                            ),
                          );
                    }),
                  ),
                  const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                  Expanded(
                    child: _buildBranchInput('Right', payload.branchRight, (
                      val,
                    ) {
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateNode(
                            node.copyWith(
                              payload: payload.copyWith(branchRight: val),
                            ),
                          );
                    }),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
              Row(
                children: [
                  Expanded(
                    child: _buildBranchInput('Bottom', payload.branchBottom, (
                      val,
                    ) {
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateNode(
                            node.copyWith(
                              payload: payload.copyWith(branchBottom: val),
                            ),
                          );
                    }),
                  ),
                  const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                  Expanded(
                    child: _buildBranchInput('Left', payload.branchLeft, (val) {
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateNode(
                            node.copyWith(
                              payload: payload.copyWith(branchLeft: val),
                            ),
                          );
                    }),
                  ),
                ],
              ),
            ],
          ],
        ],
      );
    } else if (node.payload is TextPayload) {
      final payload = node.payload as TextPayload;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TYPOGRAPHY & FONT',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildTypographyControls(context, ref, node, payload),
        ],
      );
    } else if (node.payload is StickyNotePayload) {
      final payload = node.payload as StickyNotePayload;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MEMO NOTE',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _InspectorTextField(
            key: ValueKey('note_${node.id}'),
            value: payload.text,
            minLines: 4,
            maxLines: 4,
            onChanged: (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(text: val)),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildColorPickerTile(
            context,
            'Note Color',
            payload.backgroundColor,
            (newColor) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(backgroundColor: newColor),
                    ),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildColorPickerTile(context, 'Text Color', payload.textColor, (
            newColor,
          ) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: payload.copyWith(textColor: newColor)),
                );
          }),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _buildNumberInput('Font Size', payload.fontSize, (val) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(
                            fontSize: val.clamp(8.0, 72.0),
                          ),
                        ),
                      );
                }),
              ),
              const SizedBox(width: AppSpacing.sm),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in [
                    (TextAlign.left, Icons.format_align_left),
                    (TextAlign.center, Icons.format_align_center),
                    (TextAlign.right, Icons.format_align_right),
                  ])
                    UiIconButton(
                      icon: entry.$2,
                      tooltip: 'Align ${entry.$1.name}',
                      selected: payload.textAlign == entry.$1,
                      variant: payload.textAlign == entry.$1
                          ? UiButtonVariant.primary
                          : UiButtonVariant.outline,
                      size: UiButtonSize.sm,
                      onPressed: () {
                        ref
                            .read(documentNodesProvider.notifier)
                            .updateNode(
                              node.copyWith(
                                payload: payload.copyWith(textAlign: entry.$1),
                              ),
                            );
                      },
                    ),
                ],
              ),
            ],
          ),
        ],
      );
    } else if (node.payload is VectorPathPayload) {
      final payload = node.payload as VectorPathPayload;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VECTOR PATH',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildColorPickerTile(context, 'Stroke Color', payload.stroke, (
            newColor,
          ) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: payload.copyWith(stroke: newColor)),
                );
          }),
          const SizedBox(height: AppSpacing.sm),
          _buildColorPickerTile(context, 'Fill Color', payload.fill, (
            newColor,
          ) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: payload.copyWith(fill: newColor)),
                );
          }),
          const SizedBox(height: AppSpacing.sm),
          _buildNumberInput('Stroke Width', payload.strokeWidth, (val) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: payload.copyWith(strokeWidth: val)),
                );
          }),
          const SizedBox(height: AppSpacing.sm),
          _InspectorSelect<VectorStrokeCap>(
            label: 'Stroke Cap',
            value: payload.strokeCap,
            options: const [
              (VectorStrokeCap.round, 'Round'),
              (VectorStrokeCap.butt, 'Butt'),
              (VectorStrokeCap.square, 'Square'),
            ],
            onChanged: (value) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(strokeCap: value)),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _InspectorSelect<VectorStrokeJoin>(
            label: 'Stroke Join',
            value: payload.strokeJoin,
            options: const [
              (VectorStrokeJoin.round, 'Round'),
              (VectorStrokeJoin.miter, 'Miter'),
              (VectorStrokeJoin.bevel, 'Bevel'),
            ],
            onChanged: (value) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(strokeJoin: value)),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _InspectorSelect<String>(
            label: 'Pattern',
            value: payload.dashPattern.isEmpty
                ? 'Solid'
                : (payload.dashPattern.first == 4 ? 'Dotted' : 'Dashed'),
            options: const [
              ('Solid', 'Solid ───'),
              ('Dashed', 'Dashed ╌╌╌'),
              ('Dotted', 'Dotted ···'),
            ],
            onChanged: (value) {
              final pattern = switch (value) {
                'Dashed' => [8.0, 6.0],
                'Dotted' => [4.0, 4.0],
                _ => <double>[],
              };
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(dashPattern: pattern),
                    ),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Closed Path',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall!.copyWith(color: tokens.text),
                ),
              ),
              UiSwitch(
                value: payload.isClosed,
                onChange: (newVal) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(isClosed: newVal),
                        ),
                      );
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Gradient Fill',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall!.copyWith(color: tokens.text),
                ),
              ),
              UiSwitch(
                value: payload.isGradientFill,
                onChange: (newVal) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(isGradientFill: newVal),
                        ),
                      );
                },
              ),
            ],
          ),
          if (payload.isGradientFill) ...[
            const SizedBox(height: AppSpacing.sm),
            _buildColorPickerTile(
              context,
              'Gradient End',
              payload.gradientEndColor,
              (newColor) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(gradientEndColor: newColor),
                      ),
                    );
              },
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: UiButton(
              variant: UiButtonVariant.outline,
              prefix: const Icon(Icons.code, size: 14),
              onPressed: () {
                if (payload.points.isEmpty) return;
                final sb = payload.toSvgPathData();
                showUiToast(
                  context,
                  'SVG Path copied: $sb',
                  variant: UiToastVariant.success,
                  duration: const Duration(seconds: 3),
                );
              },
              child: const Text('Export SVG Path (d)'),
            ),
          ),
        ],
      );
    } else if (node.payload is SketchCardPayload) {
      final payload = node.payload as SketchCardPayload;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SKETCH CARD',
            style: TextStyle(
              color: tokens.warning,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _InspectorTextField(
            key: ValueKey('title_${node.id}'),
            value: payload.title,
            label: 'Sketch Title',
            onChanged: (newTitle) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(title: newTitle.trim()),
                    ),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildColorPickerTile(context, 'Stroke Color', payload.strokeColor, (
            newColor,
          ) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(
                    payload: payload.copyWith(strokeColor: newColor),
                  ),
                );
          }),
          const SizedBox(height: AppSpacing.sm),
          _buildColorPickerTile(
            context,
            'Card Background',
            payload.backgroundColor,
            (newColor) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(backgroundColor: newColor),
                    ),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildNumberInput('Stroke Width', payload.strokeWidth, (val) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(
                    payload: payload.copyWith(
                      strokeWidth: val.clamp(1.0, 12.0),
                    ),
                  ),
                );
          }),
          const SizedBox(height: AppSpacing.sm),
          _InspectorSelect<String>(
            label: 'Grid Pattern',
            value: payload.cardPattern,
            options: const [
              ('none', 'Blank'),
              ('dots', 'Dots'),
              ('grid', 'Grid'),
            ],
            onChanged: (value) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(cardPattern: value),
                    ),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Smooth Stroke Curve',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
              ),
              Transform.scale(
                scale: 0.8,
                child: UiSwitch(
                  value: payload.smoothCurves,
                  onChange: (val) {
                    ref
                        .read(documentNodesProvider.notifier)
                        .updateNode(
                          node.copyWith(
                            payload: payload.copyWith(smoothCurves: val),
                          ),
                        );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: UiButton(
                  variant: UiButtonVariant.outline,
                  prefix: const Icon(Icons.undo, size: 14),
                  onPressed: payload.strokes.isNotEmpty
                      ? () {
                          final updated = payload.strokes.sublist(
                            0,
                            payload.strokes.length - 1,
                          );
                          ref
                              .read(documentNodesProvider.notifier)
                              .updateNode(
                                node.copyWith(
                                  payload: payload.copyWith(strokes: updated),
                                ),
                              );
                        }
                      : null,
                  child: const Text('Undo Stroke'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: UiButton(
                  variant: UiButtonVariant.destructive,
                  prefix: const Icon(Icons.delete_outline, size: 14),
                  onPressed: payload.strokes.isNotEmpty
                      ? () {
                          ref
                              .read(documentNodesProvider.notifier)
                              .updateNode(
                                node.copyWith(
                                  payload: payload.copyWith(strokes: const []),
                                ),
                              );
                        }
                      : null,
                  child: const Text('Clear'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: UiButton(
              prefix: const Icon(Icons.edit_note, size: 16),
              onPressed: () {
                showUiDialog<void>(
                  context: context,
                  builder: (ctx) => SketchCardEditorDialog(
                    node: node,
                    onSave: (updatedPayload) {
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateNode(node.copyWith(payload: updatedPayload));
                    },
                  ),
                );
              },
              child: const Text('Open Sketch Studio'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: UiButton(
              variant: UiButtonVariant.outline,
              prefix: const Icon(Icons.auto_awesome, size: 14),
              onPressed: () {
                showUiToast(
                  context,
                  'Sketch "${payload.title}" (${payload.strokes.length} strokes) linked to AI Wireframe prompt!',
                  variant: UiToastVariant.success,
                );
              },
              child: const Text('Send Wireframe to AI'),
            ),
          ),
        ],
      );
    } else if (node.payload is ComponentPayload) {
      final payload = node.payload as ComponentPayload;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                payload.isMaster
                    ? 'MAIN COMPONENT (❖)'
                    : 'COMPONENT INSTANCE (◇)',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              UiButton(
                variant: UiButtonVariant.ghost,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.tune, size: 12),
                onPressed: () {
                  ComponentEditorModal.show(
                    context,
                    node: node,
                    onUpdate: (updated) {
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateNode(updated);
                    },
                  );
                },
                child: const Text('Configure'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Master vs Instance Type Chip Row
          Row(
            children: [
              Expanded(
                child: UiButton(
                  variant: payload.isMaster
                      ? UiButtonVariant.primary
                      : UiButtonVariant.outline,
                  size: UiButtonSize.sm,
                  onPressed: () {
                    ref
                        .read(documentNodesProvider.notifier)
                        .updateNode(
                          node.copyWith(
                            payload: payload.copyWith(isMaster: true),
                          ),
                        );
                  },
                  child: const Text('❖ Main'),
                ),
              ),
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              Expanded(
                child: UiButton(
                  variant: !payload.isMaster
                      ? UiButtonVariant.primary
                      : UiButtonVariant.outline,
                  size: UiButtonSize.sm,
                  onPressed: () {
                    ref
                        .read(documentNodesProvider.notifier)
                        .updateNode(
                          node.copyWith(
                            payload: payload.copyWith(isMaster: false),
                          ),
                        );
                  },
                  child: const Text('◇ Instance'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),

          // Component Name Input
          _InspectorTextField(
            value: payload.componentName,
            label: 'Component Name',
            onChanged: (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      name: val.trim().isEmpty ? 'Component' : val.trim(),
                      payload: payload.copyWith(componentName: val),
                    ),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),

          if (payload.variants.isNotEmpty) ...[
            _InspectorSelect<String>(
              label: 'Component Variant',
              value: payload.variantId ?? payload.resolveVariant()?.id,
              options: [
                for (final variant in payload.variants)
                  (variant.id, variant.name),
              ],
              onChanged: (variantId) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: ComponentInstanceFactory.setVariant(
                          payload,
                          variantId,
                        ),
                      ),
                    );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // Component Properties List (Figma Props Inspector)
          if (payload.properties.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            Text(
              'COMPONENT PROPERTIES',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            ...payload.properties.map((prop) {
              final val = ComponentInstanceFactory.resolvedValue(
                payload,
                prop.id,
                designTokens: designTokens,
              );
              if (prop.type == ComponentPropType.boolean) {
                final boolVal = val is bool ? val : true;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        prop.name,
                        style: Theme.of(
                          context,
                        ).textTheme.labelMedium!.copyWith(color: tokens.text),
                      ),
                    ),
                    UiSwitch(
                      value: boolVal,
                      onChange: (newB) {
                        final nextPayload = payload.isMaster
                            ? ComponentInstanceFactory.setPropertyValue(
                                payload,
                                prop.id,
                                newB,
                              )
                            : ComponentInstanceFactory.setOverride(
                                payload,
                                prop.id,
                                newB,
                              );
                        ref
                            .read(documentNodesProvider.notifier)
                            .updateNode(node.copyWith(payload: nextPayload));
                      },
                    ),
                  ],
                );
              } else if (prop.type == ComponentPropType.variant) {
                final current = prop.options.contains(val)
                    ? val.toString()
                    : (prop.options.isNotEmpty ? prop.options.first : null);
                final options = [
                  for (final option in prop.options) (option, option),
                ];
                return Padding(
                  padding: const EdgeInsets.only(
                    bottom: AppSpacing.xs + AppSpacing.xxs,
                  ),
                  child: _InspectorSelect<String>(
                    label: prop.name,
                    value: current,
                    options: options,
                    onChanged: (newOpt) {
                      final nextPayload = payload.isMaster
                          ? ComponentInstanceFactory.setPropertyValue(
                              payload,
                              prop.id,
                              newOpt,
                            )
                          : ComponentInstanceFactory.setOverride(
                              payload,
                              prop.id,
                              newOpt,
                            );
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateNode(node.copyWith(payload: nextPayload));
                    },
                  ),
                );
              } else {
                return Padding(
                  padding: const EdgeInsets.only(
                    bottom: AppSpacing.xs + AppSpacing.xxs,
                  ),
                  child: _InspectorTextField(
                    key: ValueKey('component_prop_${node.id}_${prop.id}'),
                    value: val?.toString() ?? '',
                    label: prop.name,
                    onChanged: (newText) {
                      final nextPayload = payload.isMaster
                          ? ComponentInstanceFactory.setPropertyValue(
                              payload,
                              prop.id,
                              newText,
                            )
                          : ComponentInstanceFactory.setOverride(
                              payload,
                              prop.id,
                              newText,
                            );
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateNode(node.copyWith(payload: nextPayload));
                    },
                  ),
                );
              }
            }),
          ],

          if (payload.tokenBindings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'BOUND DESIGN TOKENS',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ...payload.tokenBindings.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${entry.key} · ${entry.value}',
                  style: TextStyle(color: tokens.textMuted, fontSize: 11),
                ),
              ),
            ),
          ],

          if (payload.slots.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'CONTENT SLOTS',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ...payload.slots.map(
              (slot) => Row(
                children: [
                  Expanded(
                    child: Text(
                      '${slot.name} · ${payload.slotContent[slot.id]?.length ?? 0} layers',
                      style: TextStyle(color: tokens.textMuted, fontSize: 11),
                    ),
                  ),
                  if (!payload.isMaster &&
                      payload.slotContent.containsKey(slot.id))
                    UiIconButton(
                      icon: Icons.restore,
                      tooltip: 'Reset Slot Content',
                      onPressed: () {
                        ref
                            .read(documentNodesProvider.notifier)
                            .updateNode(
                              node.copyWith(
                                payload:
                                    ComponentInstanceFactory.clearSlotContent(
                                      payload,
                                      slot.id,
                                    ),
                              ),
                            );
                      },
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.sm),

          // Instance Actions (Detach / Reset)
          if (!payload.isMaster) ...[
            Divider(color: tokens.panelBorder),
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            Row(
              children: [
                Expanded(
                  child: UiButton(
                    variant: UiButtonVariant.outline,
                    prefix: const Icon(Icons.link_off, size: 12),
                    onPressed: () {
                      // Detach instance to normal rectangle / frame
                      final regularPayload = FramePayload(
                        name: payload.componentName,
                        background: payload.backgroundColor,
                        borderColor: payload.borderColor,
                      );
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateNode(
                            node.copyWith(
                              type: NodeType.frame,
                              payload: regularPayload,
                            ),
                          );
                    },
                    child: const Text('Detach Instance'),
                  ),
                ),
              ],
            ),
          ],
        ],
      );
    } else if (node.payload is DrawingPayload) {
      final payload = node.payload as DrawingPayload;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RASTER BRUSH & STROKE',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _InspectorSelect<BrushType>(
            label: 'Brush Preset',
            value: payload.brushType,
            options: [
              for (final brush in BrushType.values)
                if (brush != BrushType.eraser)
                  (brush, brush.name.toUpperCase()),
            ],
            onChanged: (value) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(brushType: value)),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildColorPickerTile(context, 'Stroke Color', payload.strokeColor, (
            newColor,
          ) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(
                    payload: payload.copyWith(strokeColor: newColor),
                  ),
                );
          }),
          const SizedBox(height: AppSpacing.sm),
          _buildNumberInput('Stroke Width', payload.strokeWidth, (val) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: payload.copyWith(strokeWidth: val)),
                );
          }),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Smooth Stroke Curves',
                style: TextStyle(color: tokens.text, fontSize: 12),
              ),
              Transform.scale(
                scale: 0.8,
                child: UiSwitch(
                  value: payload.isSmoothed,
                  onChange: (val) {
                    ref
                        .read(documentNodesProvider.notifier)
                        .updateNode(
                          node.copyWith(
                            payload: payload.copyWith(isSmoothed: val),
                          ),
                        );
                  },
                ),
              ),
            ],
          ),
        ],
      );
    } else if (node.payload is FilePayload) {
      final payload = node.payload as FilePayload;
      return _buildFileCardControls(context, ref, node, payload);
    } else if (node.payload is ImagePayload) {
      final payload = node.payload as ImagePayload;
      return _buildImageAssetControls(context, ref, node, payload);
    } else if (node.payload is AnnotatedImagePayload) {
      final payload = node.payload as AnnotatedImagePayload;
      final unresolvedCount = payload.pins.where((p) => !p.isResolved).length;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ANNOTATION LAYER',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs + AppSpacing.xxs,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: unresolvedCount > 0 ? tokens.danger : tokens.success,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${payload.pins.length} pins ($unresolvedCount open)',
                  style: TextStyle(
                    color: tokens.handle,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // Toggles
          Container(
            key: const ValueKey('inspector-annotation-toggles'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm + AppSpacing.xxs,
              vertical: AppSpacing.xs + AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: tokens.panelElevated,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: tokens.panelBorder,
                width: AppBorder.thin,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Corner Badge',
                      style: TextStyle(color: tokens.textMuted, fontSize: 11),
                    ),
                    UiSwitch(
                      value: payload.showCornerBadge,
                      onChange: (val) {
                        ref
                            .read(documentNodesProvider.notifier)
                            .updateNode(
                              node.copyWith(
                                payload: payload.copyWith(showCornerBadge: val),
                              ),
                            );
                      },
                    ),
                  ],
                ),
                Divider(
                  key: const ValueKey('inspector-annotation-toggle-divider'),
                  color: tokens.panelBorder,
                  height: AppSpacing.sm,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Leader Tooltips',
                      style: TextStyle(color: tokens.textMuted, fontSize: 11),
                    ),
                    UiSwitch(
                      value: payload.showLeaderLines,
                      onChange: (val) {
                        ref
                            .read(documentNodesProvider.notifier)
                            .updateNode(
                              node.copyWith(
                                payload: payload.copyWith(showLeaderLines: val),
                              ),
                            );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(
            key: ValueKey('inspector-annotation-pin-section-gap'),
            height: AppSpacing.sm + AppSpacing.xs + AppSpacing.xxs,
          ),

          // Pins List
          Text(
            'PINNED NOTES',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          if (payload.pins.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'No pins yet. Use the Annotate Tool on the toolbar to add a pin.',
                style: TextStyle(color: tokens.textMuted, fontSize: 11),
              ),
            )
          else
            ...List.generate(payload.pins.length, (idx) {
              final pin = payload.pins[idx];
              final pinColor = pin.isResolved
                  ? tokens.success
                  : (pin.status == AnnotationPinStatus.issue
                        ? tokens.danger
                        : pin.color);

              return Container(
                key: ValueKey('inspector-annotation-pin-${pin.id}'),
                margin: const EdgeInsets.only(
                  bottom: AppSpacing.xs + AppSpacing.xxs,
                ),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: tokens.panelElevated,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: pin.isResolved
                        ? tokens.success.withValues(alpha: 0.3)
                        : tokens.panelBorder,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: pinColor,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        pin.isResolved ? '✓' : '${idx + 1}',
                        style: TextStyle(
                          color: tokens.handle,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pin.text.isNotEmpty
                                ? pin.text
                                : 'Pin #${idx + 1} (No description)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: pin.isResolved
                                  ? tokens.textMuted
                                  : tokens.text,
                              fontSize: 11,
                              decoration: pin.isResolved
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          Text(
                            'By ${pin.author} • ${pin.status.name.toUpperCase()}',
                            style: TextStyle(
                              color: tokens.textMuted,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                    UiIconButton(
                      icon: Icons.edit,
                      tooltip: 'Edit Pin',
                      size: UiButtonSize.sm,
                      onPressed: () {
                        showUiDialog(
                          context: context,
                          builder: (ctx) => AnnotationPinEditorDialog(
                            pin: pin,
                            pinIndex: idx,
                            onSave: (updatedPin) {
                              final newPins = List<ImageAnnotationPin>.from(
                                payload.pins,
                              );
                              newPins[idx] = updatedPin;
                              ref
                                  .read(documentNodesProvider.notifier)
                                  .updateNode(
                                    node.copyWith(
                                      payload: payload.copyWith(pins: newPins),
                                    ),
                                  );
                            },
                            onDelete: () {
                              final newPins = List<ImageAnnotationPin>.from(
                                payload.pins,
                              )..removeAt(idx);
                              ref
                                  .read(documentNodesProvider.notifier)
                                  .updateNode(
                                    node.copyWith(
                                      payload: payload.copyWith(pins: newPins),
                                    ),
                                  );
                            },
                          ),
                        );
                      },
                    ),
                    UiIconButton(
                      icon: Icons.delete_outline,
                      tooltip: 'Delete Pin',
                      variant: UiButtonVariant.destructive,
                      size: UiButtonSize.sm,
                      onPressed: () {
                        final newPins = List<ImageAnnotationPin>.from(
                          payload.pins,
                        )..removeAt(idx);
                        ref
                            .read(documentNodesProvider.notifier)
                            .updateNode(
                              node.copyWith(
                                payload: payload.copyWith(pins: newPins),
                              ),
                            );
                      },
                    ),
                  ],
                ),
              );
            }),
        ],
      );
    } else if (node.payload is TablePayload) {
      final payload = node.payload as TablePayload;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header title & Open Modal Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TABLE MATRIX',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              UiButton(
                onPressed: () {
                  TableMatrixEditorModal.show(
                    context,
                    node: node,
                    onUpdate: (updated) {
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateNode(updated);
                    },
                  );
                },
                variant: UiButtonVariant.ghost,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.open_in_new_rounded, size: 12),
                child: const Text('Open Grid'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Title Input
          _InspectorTextField(
            value: payload.name,
            label: 'Table Name',
            onChanged: (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(name: val)),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),

          // Dimensions (Rows / Cols)
          Row(
            children: [
              Expanded(
                child: _buildNumberInput(
                  'Rows',
                  payload.rows.length.toDouble(),
                  (val) {
                    final newRows = List<List<String>>.from(payload.rows);
                    final target = val.toInt().clamp(1, 50);
                    final colCount = payload.columns.isEmpty
                        ? 1
                        : payload.columns.length;
                    while (newRows.length < target) {
                      newRows.add(List.filled(colCount, ''));
                    }
                    if (newRows.length > target) {
                      newRows.removeRange(target, newRows.length);
                    }
                    ref
                        .read(documentNodesProvider.notifier)
                        .updateNode(
                          node.copyWith(
                            payload: payload.copyWith(rows: newRows),
                          ),
                        );
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _buildNumberInput(
                  'Cols',
                  payload.columns.length.toDouble(),
                  (val) {
                    final target = val.toInt().clamp(1, 20);
                    final newCols = List<String>.from(payload.columns);
                    while (newCols.length < target) {
                      newCols.add('Column ${newCols.length + 1}');
                    }
                    if (newCols.length > target) {
                      newCols.removeRange(target, newCols.length);
                    }
                    final newRows = payload.rows.map((r) {
                      final nr = List<String>.from(r);
                      while (nr.length < target) {
                        nr.add('');
                      }
                      if (nr.length > target) {
                        nr.removeRange(target, nr.length);
                      }
                      return nr;
                    }).toList();
                    var newTypes = List<TableCellType>.from(
                      payload.columnTypes,
                    );
                    while (newTypes.length < target) {
                      newTypes.add(TableCellType.text);
                    }
                    if (newTypes.length > target) {
                      newTypes.removeRange(target, newTypes.length);
                    }
                    ref
                        .read(documentNodesProvider.notifier)
                        .updateNode(
                          node.copyWith(
                            payload: payload.copyWith(
                              columns: newCols,
                              rows: newRows,
                              columnTypes: newTypes,
                            ),
                          ),
                        );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Summary Row Switch
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Show Summary Row',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall!.copyWith(color: tokens.text),
              ),
              UiSwitch(
                value: payload.showSummaryRow,
                onChange: (val) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(showSummaryRow: val),
                        ),
                      );
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Column Types Header & Add Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'COLUMNS & TYPES',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              UiButton(
                onPressed: () {
                  final newCols = List<String>.from(payload.columns)
                    ..add('Col ${payload.columns.length + 1}');
                  final newTypes = List<TableCellType>.from(payload.columnTypes)
                    ..add(TableCellType.text);
                  final newRows = payload.rows
                      .map((r) => List<String>.from(r)..add(''))
                      .toList();
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(
                            columns: newCols,
                            columnTypes: newTypes,
                            rows: newRows,
                          ),
                        ),
                      );
                },
                variant: UiButtonVariant.ghost,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.add, size: 12),
                child: const Text('Add Col'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          ...payload.columns.asMap().entries.map((entry) {
            final colIndex = entry.key;
            final colName = entry.value;
            final currentType = payload.typeForColumn(colIndex);
            return Padding(
              padding: const EdgeInsets.only(
                bottom: AppSpacing.xs + AppSpacing.xxs,
              ),
              child: Row(
                children: [
                  // Rename input
                  Expanded(
                    child: _InspectorTextField(
                      key: ValueKey('col_name_${colIndex}_$colName'),
                      value: colName,
                      onChanged: (val) {
                        final newCols = List<String>.from(payload.columns);
                        newCols[colIndex] = val;
                        ref
                            .read(documentNodesProvider.notifier)
                            .updateNode(
                              node.copyWith(
                                payload: payload.copyWith(columns: newCols),
                              ),
                            );
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                  // Dropdown type
                  Expanded(
                    child: _InspectorSelect<TableCellType>(
                      label: 'Column Type',
                      value: currentType,
                      options: [
                        for (final item in TableCellType.values)
                          (item, item.name.toUpperCase()),
                      ],
                      onChanged: (type) {
                        final newTypes = List<TableCellType>.from(
                          payload.columnTypes,
                        );
                        while (newTypes.length <= colIndex) {
                          newTypes.add(TableCellType.text);
                        }
                        newTypes[colIndex] = type;
                        ref
                            .read(documentNodesProvider.notifier)
                            .updateNode(
                              node.copyWith(
                                payload: payload.copyWith(
                                  columnTypes: newTypes,
                                ),
                              ),
                            );
                      },
                    ),
                  ),
                  if (payload.columns.length > 1)
                    UiIconButton(
                      icon: Icons.delete_outline,
                      size: UiButtonSize.sm,
                      variant: UiButtonVariant.destructive,
                      tooltip: 'Delete Column',
                      onPressed: () {
                        final newCols = List<String>.from(payload.columns)
                          ..removeAt(colIndex);
                        final newTypes = List<TableCellType>.from(
                          payload.columnTypes,
                        );
                        if (colIndex < newTypes.length) {
                          newTypes.removeAt(colIndex);
                        }
                        final newRows = payload.rows.map((r) {
                          final nr = List<String>.from(r);
                          if (colIndex < nr.length) nr.removeAt(colIndex);
                          return nr;
                        }).toList();
                        ref
                            .read(documentNodesProvider.notifier)
                            .updateNode(
                              node.copyWith(
                                payload: payload.copyWith(
                                  columns: newCols,
                                  columnTypes: newTypes,
                                  rows: newRows,
                                ),
                              ),
                            );
                      },
                    ),
                ],
              ),
            );
          }),

          const SizedBox(height: AppSpacing.md),
          Divider(color: tokens.panelBorder),
          const SizedBox(height: AppSpacing.sm),

          // Appearance Styling
          Text(
            'TABLE APPEARANCE',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildColorPickerTile(
            context,
            'Header Background',
            payload.headerBgColor,
            (c) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(headerBgColor: c)),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          _buildColorPickerTile(
            context,
            'Header Text Color',
            payload.headerTextColor,
            (c) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(headerTextColor: c),
                    ),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          _buildColorPickerTile(
            context,
            'Background Color',
            payload.backgroundColor,
            (c) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(backgroundColor: c),
                    ),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          _buildColorPickerTile(
            context,
            'Zebra Row Color',
            payload.zebraColor,
            (c) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(zebraColor: c)),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          _buildColorPickerTile(context, 'Border Color', payload.borderColor, (
            c,
          ) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: payload.copyWith(borderColor: c)),
                );
          }),
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Corner Radius',
                  style: TextStyle(color: tokens.textMuted, fontSize: 11),
                ),
              ),
              Text(
                '${payload.cornerRadius.toStringAsFixed(0)}px',
                style: TextStyle(color: tokens.text, fontSize: 11),
              ),
            ],
          ),
          _buildSlider(
            value: payload.cornerRadius,
            min: 0.0,
            max: 20.0,
            onChanged: (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(cornerRadius: val)),
                  );
            },
          ),
        ],
      );
    } else if (node.payload is TodoListPayload) {
      final payload = node.payload as TodoListPayload;
      final completedCount = payload.items.where((i) => i.isDone).length;
      final totalCount = payload.items.length;
      final progress = totalCount > 0 ? (completedCount / totalCount) : 0.0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Quick Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'TO-DO LIST',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              UiButton(
                onPressed: () {
                  TodoListEditorModal.show(
                    context,
                    node: node,
                    onUpdate: (updated) {
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateNode(updated);
                    },
                  );
                },
                variant: UiButtonVariant.ghost,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.open_in_new_rounded, size: 12),
                child: const Text('Open Modal'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Title Input
          _InspectorTextField(
            value: payload.title,
            label: 'Checklist Title',
            onChanged: (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(title: val)),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),

          // Progress Bar Box
          Container(
            key: const ValueKey('inspector-checklist-progress'),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: tokens.panel,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: tokens.panelBorder,
                width: AppBorder.thin,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Completed: $completedCount/$totalCount',
                      style: TextStyle(color: tokens.text, fontSize: 11),
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: TextStyle(
                        color: payload.accentColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                UiLinearProgressIndicator(
                  value: progress,
                  semanticsLabel: 'Video generation progress',
                  height: 4,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),

          // Quick Filter Mode
          Row(
            children: [
              Text(
                'Filter: ',
                style: TextStyle(color: tokens.textMuted, fontSize: 11),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Row(
                  children: [
                    for (final mode in ['all', 'active', 'completed'])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: UiButton(
                              onPressed: () {
                                ref
                                    .read(documentNodesProvider.notifier)
                                    .updateNode(
                                      node.copyWith(
                                        payload: payload.copyWith(
                                          filterMode: mode,
                                        ),
                                      ),
                                    );
                              },
                              variant: payload.filterMode == mode
                                  ? UiButtonVariant.primary
                                  : UiButtonVariant.outline,
                              size: UiButtonSize.sm,
                              child: Text(
                                mode == 'completed'
                                    ? 'DONE'
                                    : mode.toUpperCase(),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Add Task Button
          UiButton(
            prefix: const Icon(Icons.add, size: 14),
            child: const Text('Add Task'),
            onPressed: () {
              final newId = const Uuid().v4();
              final newItems = List<TodoItem>.from(payload.items)
                ..add(TodoItem(id: newId, text: 'New task', isDone: false));
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(items: newItems)),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),

          // Task items list
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: payload.items.length,
            onReorderItem: (oldIndex, newIndex) {
              final newItems = List<TodoItem>.from(payload.items);
              final movedItem = newItems.removeAt(oldIndex);
              newItems.insert(newIndex, movedItem);
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(items: newItems)),
                  );
            },
            itemBuilder: (context, index) {
              final item = payload.items[index];
              return Container(
                key: ValueKey(item.id),
                margin: const EdgeInsets.only(
                  bottom: AppSpacing.xs + AppSpacing.xxs,
                ),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: tokens.panelElevated,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: tokens.panelBorder,
                    width: AppBorder.thin,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Drag handle
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.xs),
                          child: Icon(
                            Icons.drag_indicator,
                            size: 14,
                            color: context.appTokens.textMuted,
                          ),
                        ),
                        // Checkbox toggle
                        Semantics(
                          button: true,
                          checked: item.isDone,
                          label: item.isDone
                              ? 'Mark task active'
                              : 'Mark task done',
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              final newItems = List<TodoItem>.from(
                                payload.items,
                              );
                              newItems[index] = item.copyWith(
                                isDone: !item.isDone,
                              );
                              ref
                                  .read(documentNodesProvider.notifier)
                                  .updateNode(
                                    node.copyWith(
                                      payload: payload.copyWith(
                                        items: newItems,
                                      ),
                                    ),
                                  );
                            },
                            child: Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: item.isDone
                                      ? payload.accentColor
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: item.isDone
                                        ? payload.accentColor
                                        : context.appTokens.textMuted,
                                  ),
                                ),
                                child: item.isDone
                                    ? const Icon(
                                        Icons.check,
                                        size: 12,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(
                          key: ValueKey('inspector-checklist-task-control-gap'),
                          width: AppSpacing.sm,
                        ),
                        // Text input inline
                        Expanded(
                          child: _InspectorTextField(
                            key: ValueKey('item_text_${item.id}'),
                            value: item.text,
                            hint: 'Task',
                            onChanged: (val) {
                              final newItems = List<TodoItem>.from(
                                payload.items,
                              );
                              newItems[index] = item.copyWith(text: val);
                              ref
                                  .read(documentNodesProvider.notifier)
                                  .updateNode(
                                    node.copyWith(
                                      payload: payload.copyWith(
                                        items: newItems,
                                      ),
                                    ),
                                  );
                            },
                          ),
                        ),
                        UiIconButton(
                          icon: Icons.delete_outline,
                          tooltip: 'Delete task',
                          variant: UiButtonVariant.destructive,
                          size: UiButtonSize.sm,
                          onPressed: () {
                            final newItems = List<TodoItem>.from(payload.items)
                              ..removeAt(index);
                            ref
                                .read(documentNodesProvider.notifier)
                                .updateNode(
                                  node.copyWith(
                                    payload: payload.copyWith(items: newItems),
                                  ),
                                );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                    // Priority selector & Due date picker
                    Row(
                      children: [
                        // Priority Dropdown
                        Expanded(
                          child: _InspectorSelect<TodoPriority>(
                            label: 'Priority',
                            value: item.priority,
                            options: [
                              for (final option in TodoPriority.values)
                                (option, option.label),
                            ],
                            onChanged: (priority) {
                              final newItems = List<TodoItem>.from(
                                payload.items,
                              );
                              newItems[index] = item.copyWith(
                                priority: priority,
                              );
                              ref
                                  .read(documentNodesProvider.notifier)
                                  .updateNode(
                                    node.copyWith(
                                      payload: payload.copyWith(
                                        items: newItems,
                                      ),
                                    ),
                                  );
                            },
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                        // Due Date Picker Button
                        Expanded(
                          child: UiButton(
                            prefix: const Icon(Icons.calendar_today, size: 12),
                            variant: UiButtonVariant.outline,
                            size: UiButtonSize.sm,
                            onPressed: () async {
                              final initial = item.dueDate != null
                                  ? DateTime.tryParse(item.dueDate!) ??
                                        DateTime.now()
                                  : DateTime.now();
                              final picked = await showUiDatePicker(
                                context: context,
                                initialDate: initial,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035),
                              );
                              if (picked != null) {
                                final formatted =
                                    '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                                final newItems = List<TodoItem>.from(
                                  payload.items,
                                );
                                newItems[index] = item.copyWith(
                                  dueDate: formatted,
                                );
                                ref
                                    .read(documentNodesProvider.notifier)
                                    .updateNode(
                                      node.copyWith(
                                        payload: payload.copyWith(
                                          items: newItems,
                                        ),
                                      ),
                                    );
                              }
                            },
                            child: Flexible(
                              child: Text(
                                item.dueDate?.isNotEmpty == true
                                    ? item.dueDate!
                                    : 'Set Date',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(
                      key: ValueKey('inspector-checklist-assignee-gap'),
                      height: AppSpacing.xs,
                    ),
                    // Assignee input
                    _InspectorTextField(
                      key: ValueKey('item_assignee_${item.id}'),
                      value: item.assignee ?? '',
                      label: 'Assignee',
                      onChanged: (val) {
                        final newItems = List<TodoItem>.from(payload.items);
                        newItems[index] = item.copyWith(
                          assignee: val.isEmpty ? null : val,
                        );
                        ref
                            .read(documentNodesProvider.notifier)
                            .updateNode(
                              node.copyWith(
                                payload: payload.copyWith(items: newItems),
                              ),
                            );
                      },
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: AppSpacing.md),
          Divider(color: tokens.panelBorder),
          const SizedBox(height: AppSpacing.sm),

          // Styling Options
          Text(
            'CARD APPEARANCE',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildColorPickerTile(
            context,
            'Background Color',
            payload.backgroundColor,
            (color) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(backgroundColor: color),
                    ),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          _buildColorPickerTile(
            context,
            'Accent / Checkbox',
            payload.accentColor,
            (color) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(
                        accentColor: color,
                        borderColor: color,
                      ),
                    ),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Border Width',
                  style: TextStyle(color: tokens.textMuted, fontSize: 11),
                ),
              ),
              Text(
                '${payload.borderWidth.toStringAsFixed(1)}px',
                style: TextStyle(color: tokens.text, fontSize: 11),
              ),
            ],
          ),
          _buildSlider(
            value: payload.borderWidth,
            min: 0.0,
            max: 6.0,
            onChanged: (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(borderWidth: val)),
                  );
            },
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Corner Radius',
                  style: TextStyle(color: tokens.textMuted, fontSize: 11),
                ),
              ),
              Text(
                '${payload.cornerRadius.toStringAsFixed(0)}px',
                style: TextStyle(color: tokens.text, fontSize: 11),
              ),
            ],
          ),
          _buildSlider(
            value: payload.cornerRadius,
            min: 0.0,
            max: 24.0,
            onChanged: (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(cornerRadius: val)),
                  );
            },
          ),
        ],
      );
    } else if (node.payload is ColumnPayload) {
      final payload = node.payload as ColumnPayload;
      final totalCards = payload.cards.length;
      final doneCards = payload.cards.where((c) => c.isDone).length;
      final isWipExceeded =
          payload.wipLimit > 0 && totalCards > payload.wipLimit;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Quick Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'COLUMN CARD / KANBAN',
                  style: TextStyle(
                    color: tokens.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              UiButton(
                onPressed: () {
                  ColumnCardEditorModal.show(
                    context,
                    node: node,
                    onUpdate: (updated) {
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateNode(updated);
                    },
                  );
                },
                variant: UiButtonVariant.ghost,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.open_in_new_rounded, size: 12),
                child: const Text('Open Modal'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Title Input
          _InspectorTextField(
            value: payload.headerTitle,
            label: 'Column Title',
            onChanged: (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(headerTitle: val)),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),

          // WIP & Stats Box
          Container(
            key: const ValueKey('inspector-column-stats'),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: tokens.panel,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isWipExceeded ? tokens.danger : tokens.panelBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Cards: $totalCards${payload.wipLimit > 0 ? ' / WIP ${payload.wipLimit}' : ''}',
                      style: TextStyle(
                        color: isWipExceeded ? tokens.danger : tokens.textMuted,
                        fontSize: 11,
                        fontWeight: isWipExceeded
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    Text(
                      'Done: $doneCards',
                      style: TextStyle(
                        color: payload.headerColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                Wrap(
                  spacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  runSpacing: AppSpacing.xs + AppSpacing.xxs,
                  children: [
                    Row(
                      key: const ValueKey('inspector-column-wip-row'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'WIP Limit: ',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(
                          key: ValueKey('inspector-column-wip-gap'),
                          width: AppSpacing.xs,
                        ),
                        SizedBox(
                          width: 64,
                          child: _InspectorTextField(
                            key: ValueKey('wip_limit_${node.id}'),
                            value: payload.wipLimit.toString(),
                            keyboardType: TextInputType.number,
                            onChanged: (val) {
                              final parsed = int.tryParse(val) ?? 0;
                              ref
                                  .read(documentNodesProvider.notifier)
                                  .updateNode(
                                    node.copyWith(
                                      payload: payload.copyWith(
                                        wipLimit: parsed.clamp(0, 999),
                                      ),
                                    ),
                                  );
                            },
                          ),
                        ),
                      ],
                    ),
                    Row(
                      key: const ValueKey('inspector-column-collapse-row'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Collapse: ',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 10,
                          ),
                        ),
                        UiSwitch(
                          key: const ValueKey('inspector-column-collapse'),
                          value: payload.isCollapsed,
                          onChange: (val) {
                            ref
                                .read(documentNodesProvider.notifier)
                                .updateNode(
                                  node.copyWith(
                                    payload: payload.copyWith(isCollapsed: val),
                                  ),
                                );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),

          // Quick Filter Row
          Row(
            children: [
              Text(
                'Filter: ',
                style: TextStyle(color: tokens.textMuted, fontSize: 11),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Row(
                  children: [
                    for (final mode in ['all', 'active', 'done'])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: UiButton(
                              onPressed: () {
                                ref
                                    .read(documentNodesProvider.notifier)
                                    .updateNode(
                                      node.copyWith(
                                        payload: payload.copyWith(
                                          filterMode: mode,
                                        ),
                                      ),
                                    );
                              },
                              variant: payload.filterMode == mode
                                  ? UiButtonVariant.primary
                                  : UiButtonVariant.outline,
                              size: UiButtonSize.sm,
                              child: Text(
                                mode == 'completed'
                                    ? 'DONE'
                                    : mode.toUpperCase(),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Add Card Quick Button
          UiButton(
            prefix: const Icon(Icons.add, size: 14),
            child: const Text('Add Card'),
            onPressed: () {
              final newId = const Uuid().v4();
              final newCards = List<ColumnCardItem>.from(payload.cards)
                ..add(
                  ColumnCardItem(
                    id: newId,
                    title: 'New Card ${payload.cards.length + 1}',
                  ),
                );
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(cards: newCards)),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),

          // Reorderable Card List
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: payload.cards.length,
            onReorderItem: (oldIdx, newIdx) {
              final items = List<ColumnCardItem>.from(payload.cards);
              final moved = items.removeAt(oldIdx);
              items.insert(newIdx, moved);
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(cards: items)),
                  );
            },
            itemBuilder: (context, index) {
              final card = payload.cards[index];
              return Container(
                key: ValueKey('column_card_${card.id}'),
                margin: const EdgeInsets.only(
                  bottom: AppSpacing.xs + AppSpacing.xxs,
                ),
                padding: const EdgeInsets.all(AppSpacing.xs + AppSpacing.xxs),
                decoration: BoxDecoration(
                  color:
                      card.cardColor?.withValues(alpha: 0.12) ?? tokens.panel,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: card.cardColor ?? tokens.panelBorder,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        UiCheckbox(
                          value: card.isDone,
                          onChange: (val) {
                            final newCards = List<ColumnCardItem>.from(
                              payload.cards,
                            );
                            newCards[index] = card.copyWith(isDone: val);
                            ref
                                .read(documentNodesProvider.notifier)
                                .updateNode(
                                  node.copyWith(
                                    payload: payload.copyWith(cards: newCards),
                                  ),
                                );
                          },
                        ),
                        Expanded(
                          child: _InspectorTextField(
                            key: ValueKey('card_title_${card.id}'),
                            value: card.title,
                            hint: 'Card title',
                            onChanged: (val) {
                              final newCards = List<ColumnCardItem>.from(
                                payload.cards,
                              );
                              newCards[index] = card.copyWith(title: val);
                              ref
                                  .read(documentNodesProvider.notifier)
                                  .updateNode(
                                    node.copyWith(
                                      payload: payload.copyWith(
                                        cards: newCards,
                                      ),
                                    ),
                                  );
                            },
                          ),
                        ),
                        UiIconButton(
                          icon: Icons.close,
                          tooltip: 'Delete card',
                          variant: UiButtonVariant.destructive,
                          size: UiButtonSize.sm,
                          onPressed: () {
                            final newCards = List<ColumnCardItem>.from(
                              payload.cards,
                            )..removeAt(index);
                            ref
                                .read(documentNodesProvider.notifier)
                                .updateNode(
                                  node.copyWith(
                                    payload: payload.copyWith(cards: newCards),
                                  ),
                                );
                          },
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        // Priority dropdown
                        Expanded(
                          child: _InspectorSelect<ColumnCardPriority>(
                            label: 'Card Priority',
                            value: card.priority,
                            options: const [
                              (ColumnCardPriority.none, '⚪ None'),
                              (ColumnCardPriority.low, '🔵 Low'),
                              (ColumnCardPriority.medium, '🟡 Med'),
                              (ColumnCardPriority.high, '🔴 High'),
                            ],
                            onChanged: (priority) {
                              final newCards = List<ColumnCardItem>.from(
                                payload.cards,
                              );
                              newCards[index] = card.copyWith(
                                priority: priority,
                              );
                              ref
                                  .read(documentNodesProvider.notifier)
                                  .updateNode(
                                    node.copyWith(
                                      payload: payload.copyWith(
                                        cards: newCards,
                                      ),
                                    ),
                                  );
                            },
                          ),
                        ),
                        SizedBox(
                          key: ValueKey(
                            'inspector-column-card-control-gap-${card.id}',
                          ),
                          width: AppSpacing.xs,
                        ),
                        // Assignee
                        Expanded(
                          child: _InspectorTextField(
                            key: ValueKey('card_assignee_${card.id}'),
                            value: card.assignee ?? '',
                            hint: '@user',
                            onChanged: (val) {
                              final newCards = List<ColumnCardItem>.from(
                                payload.cards,
                              );
                              newCards[index] = card.copyWith(
                                assignee: val.isEmpty ? null : val,
                              );
                              ref
                                  .read(documentNodesProvider.notifier)
                                  .updateNode(
                                    node.copyWith(
                                      payload: payload.copyWith(
                                        cards: newCards,
                                      ),
                                    ),
                                  );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: AppSpacing.md),
          Divider(color: tokens.panelBorder),
          const SizedBox(height: AppSpacing.sm),

          // Styling Options
          Text(
            'COLUMN APPEARANCE',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          _buildColorPickerTile(context, 'Header Color', payload.headerColor, (
            newColor,
          ) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(
                    payload: payload.copyWith(headerColor: newColor),
                  ),
                );
          }),
          const SizedBox(height: AppSpacing.sm),
          _buildColorPickerTile(
            context,
            'Background Color',
            payload.backgroundColor,
            (newColor) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(backgroundColor: newColor),
                    ),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildColorPickerTile(context, 'Border Color', payload.borderColor, (
            newColor,
          ) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(
                    payload: payload.copyWith(borderColor: newColor),
                  ),
                );
          }),
          const SizedBox(height: AppSpacing.sm),

          _buildNumberInput('Border Width', payload.borderWidth, (val) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(
                    payload: payload.copyWith(
                      borderWidth: val.clamp(0.0, 10.0),
                    ),
                  ),
                );
          }),
          const SizedBox(height: AppSpacing.sm),

          Text(
            'Corner Radius',
            style: TextStyle(color: tokens.textMuted, fontSize: 11),
          ),
          _buildSlider(
            value: payload.cornerRadius,
            min: 0.0,
            max: 24.0,
            onChanged: (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(cornerRadius: val)),
                  );
            },
          ),
        ],
      );
    } else if (node.payload is NestedBoardPayload) {
      final payload = node.payload as NestedBoardPayload;
      final count = payload.subNodes.isNotEmpty
          ? payload.subNodes.length
          : payload.childNodeCount;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'NESTED BOARD',
                style: TextStyle(
                  color: tokens.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              UiButton(
                onPressed: () {
                  NestedBoardScreen.show(
                    context,
                    node: node,
                    onUpdate: (updated) {
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateNode(updated);
                    },
                  );
                },
                variant: UiButtonVariant.ghost,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.open_in_new_rounded, size: 12),
                child: const Text('Open Sub-Canvas'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),

          // Open Full Sub-Canvas Action Button
          SizedBox(
            width: double.infinity,
            child: UiButton(
              onPressed: () {
                NestedBoardScreen.show(
                  context,
                  node: node,
                  onUpdate: (updated) {
                    ref
                        .read(documentNodesProvider.notifier)
                        .updateNode(updated);
                  },
                );
              },
              prefix: const Icon(Icons.dashboard_customize_outlined, size: 14),
              child: const Text('Open Sub-Canvas Workspace'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Board Title Input
          _InspectorTextField(
            value: payload.boardName,
            label: 'Board Name',
            onChanged: (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      name: val.trim().isEmpty ? 'Nested Board' : val.trim(),
                      payload: payload.copyWith(boardName: val),
                    ),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),

          // Board Description Input
          _InspectorTextField(
            value: payload.description,
            label: 'Description',
            minLines: 2,
            maxLines: 2,
            onChanged: (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(description: val)),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),

          // Items summary card
          Container(
            key: const ValueKey('inspector-nested-board-summary'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm + AppSpacing.xxs,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: tokens.panelElevated,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(
                color: tokens.panelBorder,
                width: AppBorder.thin,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.layers_outlined, size: 14, color: tokens.accent),
                const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                Text(
                  'Contains $count canvas items',
                  style: TextStyle(
                    color: tokens.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(color: tokens.panelBorder),
          const SizedBox(height: AppSpacing.sm),

          // Board Appearance
          Text(
            'BOARD APPEARANCE',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          _buildColorPickerTile(
            context,
            'Accent / Title Color',
            payload.accentColor,
            (newColor) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(accentColor: newColor),
                    ),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildColorPickerTile(
            context,
            'Background Color',
            payload.backgroundColor,
            (newColor) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(backgroundColor: newColor),
                    ),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildColorPickerTile(context, 'Border Color', payload.borderColor, (
            newColor,
          ) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(
                    payload: payload.copyWith(borderColor: newColor),
                  ),
                );
          }),
          const SizedBox(height: AppSpacing.sm),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Show Grid Preview',
                  style: TextStyle(color: tokens.text, fontSize: 12),
                ),
              ),
              UiSwitch(
                value: payload.showGridPreview,
                onChange: (val) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(showGridPreview: val),
                        ),
                      );
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          _buildNumberInput('Border Width', payload.borderWidth, (val) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(
                    payload: payload.copyWith(borderWidth: val.clamp(0.0, 8.0)),
                  ),
                );
          }),
        ],
      );
    } else if (node.payload is VideoPayload) {
      final payload = node.payload as VideoPayload;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VIDEO CARD',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _InspectorTextField(
            value: payload.title,
            label: 'Title',
            onChanged: (v) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(title: v)),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _InspectorTextField(
            value: payload.caption ?? '',
            label: 'Description',
            minLines: 2,
            maxLines: 4,
            onChanged: (v) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(caption: v)),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            payload.videoArtifactReference == null
                ? 'No owned video artifact is attached.'
                : 'Owned video artifact attached',
            style: TextStyle(color: tokens.textMuted, fontSize: 11),
          ),
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          UiButton(
            variant: UiButtonVariant.outline,
            prefix: const Icon(Icons.folder_open, size: 16),
            onPressed: () async {
              final operationGeneration = _beginArtifactOperation();
              final sync = ref.read(supabaseSyncServiceProvider);
              final accountId = sync.currentUserId;
              final result = await AssetService(
                sync,
              ).pickVideo(projectId: projectId);
              if (result == null ||
                  _currentReplacementNode(
                        ref: ref,
                        capturedNode: node,
                        generation: operationGeneration,
                        accountId: accountId,
                      ) ==
                      null) {
                return;
              }

              final bytes = result.bytes;
              if (bytes == null || bytes.isEmpty) {
                if (!context.mounted) return;
                showUiToast(
                  context,
                  'The selected video could not be read for owned storage.',
                  variant: UiToastVariant.error,
                );
                return;
              }

              VideoArtifact artifact;
              try {
                artifact = await _videoStore(
                  ref,
                ).save(bytes, fileName: result.name);
              } catch (error) {
                if (!context.mounted) return;
                showUiToast(
                  context,
                  'Video could not be stored: $error',
                  variant: UiToastVariant.error,
                );
                return;
              }
              final currentAfterSave = _currentReplacementNode(
                ref: ref,
                capturedNode: node,
                generation: operationGeneration,
                accountId: accountId,
              );
              if (currentAfterSave == null) return;
              final reference = validVideoArtifactReference(artifact.reference);
              if (!context.mounted) return;
              if (reference == null) {
                showUiToast(
                  context,
                  'The selected video could not be stored in owned artifact storage.',
                  variant: UiToastVariant.error,
                );
                return;
              }
              final current = _currentReplacementNode(
                ref: ref,
                capturedNode: node,
                generation: operationGeneration,
                accountId: accountId,
              );
              if (current == null || current.payload is! VideoPayload) return;
              final currentPayload = current.payload as VideoPayload;
              final assetId = _mediaAssetId(
                ref,
                current,
                currentPayload.assetId,
              );
              _upsertDocumentAsset(
                ref,
                assetId: assetId,
                kind: DocumentAssetKind.video,
                name: result.name,
                mimeType: result.detectedMimeType,
                artifactReference: reference,
                storagePath: null,
                declaredSize: result.size,
                bytes: bytes,
              );
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    current.copyWith(
                      payload: currentPayload.copyWith(
                        title: result.name,
                        assetId: assetId,
                        storagePath: null,
                        videoPath: null,
                        videoUrl: null,
                        videoArtifactReference: reference,
                        sourceError: '',
                        isTemporary: false,
                      ),
                    ),
                  );
            },
            child: const Text('Choose video file'),
          ),
          const SizedBox(height: AppSpacing.sm),
          UiButton(
            variant: UiButtonVariant.outline,
            prefix: const Icon(Icons.timeline, size: 16),
            onPressed: () => _editMediaTimeline(
              context,
              ref,
              node,
              _videoTimeline(payload),
              payload.title,
              (timeline) => payload.copyWith(
                mediaTimeline: timeline,
                caption: timeline.caption ?? '',
                durationMs: timeline.sourceDurationMs > 0
                    ? timeline.sourceDurationMs
                    : payload.durationMs,
                durationText: timeline.sourceDurationMs > 0
                    ? formatMediaDurationMs(timeline.sourceDurationMs)
                    : payload.durationText,
              ),
            ),
            child: const Text('Edit media timeline'),
          ),
        ],
      );
    } else if (node.payload is AudioPayload) {
      final payload = node.payload as AudioPayload;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AUDIO CARD',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _InspectorTextField(
            value: payload.trackName,
            label: 'Track Title',
            onChanged: (v) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(trackName: v)),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _InspectorTextField(
            value: payload.artist,
            label: 'Artist',
            onChanged: (v) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(artist: v)),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _InspectorTextField(
            value: payload.description,
            label: 'Description',
            minLines: 3,
            maxLines: 3,
            onChanged: (v) => ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: payload.copyWith(description: v)),
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            payload.audioArtifactReference == null
                ? 'No owned audio artifact is attached.'
                : 'Owned audio artifact attached',
            style: TextStyle(color: tokens.textMuted, fontSize: 11),
          ),
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          UiButton(
            variant: UiButtonVariant.outline,
            prefix: const Icon(Icons.folder_open, size: 16),
            onPressed: () async {
              final operationGeneration = _beginArtifactOperation();
              final sync = ref.read(supabaseSyncServiceProvider);
              final accountId = sync.currentUserId;
              final result = await AssetService(
                sync,
              ).pickAudio(projectId: projectId);
              if (result == null ||
                  _currentReplacementNode(
                        ref: ref,
                        capturedNode: node,
                        generation: operationGeneration,
                        accountId: accountId,
                      ) ==
                      null) {
                return;
              }
              final bytes = result.bytes;
              if (bytes == null || bytes.isEmpty) {
                if (!context.mounted) return;
                showUiToast(
                  context,
                  'The selected audio could not be read for owned storage.',
                  variant: UiToastVariant.error,
                );
                return;
              }
              final artifact = await _mediaStore(ref).save(
                bytes,
                kind: MediaArtifactKind.original,
                mimeType: _audioMimeTypeForFileName(result.name),
                checksum: mediaArtifactChecksum(bytes),
                fileName: result.name,
                storagePolicy: MediaStoragePolicy.durable,
              );
              if (_currentReplacementNode(
                    ref: ref,
                    capturedNode: node,
                    generation: operationGeneration,
                    accountId: accountId,
                  ) ==
                  null) {
                return;
              }
              final reference = validMediaArtifactReference(artifact.reference);
              if (!context.mounted) return;
              if (reference == null) {
                showUiToast(
                  context,
                  'The selected audio could not be stored in owned artifact storage.',
                  variant: UiToastVariant.error,
                );
                return;
              }
              final current = _currentReplacementNode(
                ref: ref,
                capturedNode: node,
                generation: operationGeneration,
                accountId: accountId,
              );
              if (current == null || current.payload is! AudioPayload) return;
              final currentPayload = current.payload as AudioPayload;
              final assetId = _mediaAssetId(
                ref,
                current,
                currentPayload.assetId,
              );
              _upsertDocumentAsset(
                ref,
                assetId: assetId,
                kind: DocumentAssetKind.audio,
                name: result.name,
                mimeType: _audioMimeTypeForFileName(result.name),
                artifactReference: reference,
                storagePath: null,
                declaredSize: result.size,
                bytes: bytes,
              );
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    current.copyWith(
                      payload: currentPayload.copyWith(
                        trackName: result.name,
                        assetId: assetId,
                        storagePath: null,
                        audioPath: null,
                        audioUrl: null,
                        audioArtifactReference: reference,
                      ),
                    ),
                  );
            },
            child: const Text('Choose audio file'),
          ),
          const SizedBox(height: AppSpacing.sm),
          UiButton(
            variant: UiButtonVariant.outline,
            prefix: const Icon(Icons.timeline, size: 16),
            onPressed: () => _editMediaTimeline(
              context,
              ref,
              node,
              _audioTimeline(payload),
              payload.trackName,
              (timeline) => payload.copyWith(
                mediaTimeline: timeline,
                playbackSpeed: timeline.playbackSpeed,
                durationSeconds: timeline.sourceDurationMs > 0
                    ? (timeline.sourceDurationMs / 1000).round()
                    : payload.durationSeconds,
                durationText: timeline.sourceDurationMs > 0
                    ? formatMediaDurationMs(timeline.sourceDurationMs)
                    : payload.durationText,
              ),
            ),
            child: const Text('Edit media timeline'),
          ),
        ],
      );
    } else if (node.payload is LinkPayload) {
      final payload = node.payload as LinkPayload;
      return LinkCardInspector(
        node: node,
        onSubmitUrl: (url) =>
            ref.read(linkPreviewControllerProvider.notifier).submit(node, url),
        onTitleChanged: (value) => ref
            .read(documentNodesProvider.notifier)
            .updateNode(node.copyWith(payload: payload.copyWith(title: value))),
        onDescriptionChanged: (value) => ref
            .read(documentNodesProvider.notifier)
            .updateNode(
              node.copyWith(payload: payload.copyWith(description: value)),
            ),
        onRefresh: () =>
            ref.read(linkPreviewControllerProvider.notifier).refresh(node),
        onOpenInApp: () {
          try {
            final uri = normalizeLinkUrl(payload.url);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EmbedWebviewScreen(
                  url: uri.toString(),
                  title: payload.title.isEmpty ? uri.host : payload.title,
                ),
              ),
            );
          } on LinkUrlValidationException catch (error) {
            showUiToast(context, error.message, variant: UiToastVariant.error);
          }
        },
        onOpenExternal: () async {
          try {
            final opened = await launchUrl(
              normalizeLinkUrl(payload.url),
              mode: LaunchMode.externalApplication,
            );
            if (!opened && context.mounted) {
              showUiToast(
                context,
                'Browser tidak dapat dibuka.',
                variant: UiToastVariant.error,
              );
            }
          } catch (_) {
            if (context.mounted) {
              showUiToast(
                context,
                'Browser tidak dapat dibuka.',
                variant: UiToastVariant.error,
              );
            }
          }
        },
      );
    } else if (node.payload is MapPayload) {
      final payload = node.payload as MapPayload;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MAP LOCATION',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _InspectorTextField(
            value: payload.locationTitle,
            label: 'Location Name',
            onChanged: (v) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: MapPayload(
                        locationTitle: v,
                        address: payload.address,
                        latitude: payload.latitude,
                        longitude: payload.longitude,
                        zoomLevel: payload.zoomLevel,
                      ),
                    ),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _InspectorTextField(
            value: payload.address,
            label: 'Address',
            onChanged: (v) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: MapPayload(
                        locationTitle: payload.locationTitle,
                        address: v,
                        latitude: payload.latitude,
                        longitude: payload.longitude,
                        zoomLevel: payload.zoomLevel,
                      ),
                    ),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _mapNumberField(
                  'Latitude',
                  payload.latitude,
                  MapPayload.isValidLatitude,
                  (value) {
                    ref
                        .read(documentNodesProvider.notifier)
                        .updateNode(
                          node.copyWith(
                            payload: MapPayload(
                              locationTitle: payload.locationTitle,
                              address: payload.address,
                              latitude: value,
                              longitude: payload.longitude,
                              zoomLevel: payload.zoomLevel,
                            ),
                          ),
                        );
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _mapNumberField(
                  'Longitude',
                  payload.longitude,
                  MapPayload.isValidLongitude,
                  (value) {
                    ref
                        .read(documentNodesProvider.notifier)
                        .updateNode(
                          node.copyWith(
                            payload: MapPayload(
                              locationTitle: payload.locationTitle,
                              address: payload.address,
                              latitude: payload.latitude,
                              longitude: value,
                              zoomLevel: payload.zoomLevel,
                            ),
                          ),
                        );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _mapNumberField(
            'Zoom (1–19)',
            payload.zoomLevel,
            MapPayload.isValidZoom,
            (value) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: MapPayload(
                        locationTitle: payload.locationTitle,
                        address: payload.address,
                        latitude: payload.latitude,
                        longitude: payload.longitude,
                        zoomLevel: value,
                      ),
                    ),
                  );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: UiButton(
                  variant: UiButtonVariant.outline,
                  prefix: const Icon(Icons.my_location, size: 15),
                  onPressed: () async {
                    final result = await MapLocationService().reverse(
                      payload.latitude,
                      payload.longitude,
                    );
                    if (!context.mounted || result == null) return;
                    ref
                        .read(documentNodesProvider.notifier)
                        .updateNode(
                          node.copyWith(
                            payload: MapPayload(
                              locationTitle: payload.locationTitle,
                              address: result.displayName,
                              latitude: result.latitude,
                              longitude: result.longitude,
                              zoomLevel: payload.zoomLevel,
                            ),
                          ),
                        );
                  },
                  child: const Text('REVERSE'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: UiButton(
                  prefix: const Icon(Icons.map_outlined, size: 15),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MapViewerScreen(
                        initialPayload: payload,
                        onSaveAndExit: (updated) {
                          final current = ref
                              .read(documentNodesProvider)
                              .firstWhere(
                                (candidate) => candidate.id == node.id,
                                orElse: () => node,
                              );
                          ref
                              .read(documentNodesProvider.notifier)
                              .updateNode(current.copyWith(payload: updated));
                        },
                      ),
                    ),
                  ),
                  child: const Text('OPEN MAP'),
                ),
              ),
            ],
          ),
        ],
      );
    } else if (node.payload is EmbedPayload) {
      final payload = node.payload as EmbedPayload;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EMBED MEDIA',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _InspectorTextField(
            value: payload.url,
            label: 'Embed URL',
            onChanged: (value) {
              try {
                final info = parseEmbedUrl(value);
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          url: value,
                          provider: info.providerLabel,
                        ),
                      ),
                    );
              } catch (_) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(payload: payload.copyWith(url: value)),
                    );
              }
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _InspectorTextField(
            value: payload.title ?? '',
            label: 'Title',
            onChanged: (value) => ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: payload.copyWith(title: value)),
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _InspectorTextField(
            value: payload.description ?? '',
            label: 'Description',
            minLines: 2,
            maxLines: 2,
            onChanged: (value) => ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: payload.copyWith(description: value)),
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _InspectorTextField(
            value: payload.thumbnailUrl ?? '',
            label: 'Thumbnail URL',
            onChanged: (value) => ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: payload.copyWith(thumbnailUrl: value)),
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: UiButton(
                  prefix: const Icon(Icons.play_arrow, size: 15),
                  onPressed: payload.url.trim().isEmpty
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EmbedWebviewScreen(
                              url: parseEmbedUrl(
                                payload.url,
                              ).launchUrl.toString(),
                              title: payload.title ?? payload.provider,
                            ),
                          ),
                        ),
                  child: const Text('PREVIEW'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: UiButton(
                  prefix: const Icon(Icons.open_in_new, size: 15),
                  onPressed: payload.url.trim().isEmpty
                      ? null
                      : () => launchUrl(
                          parseEmbedUrl(payload.url).url,
                          mode: LaunchMode.externalApplication,
                        ),
                  child: const Text('EXTERNAL'),
                ),
              ),
            ],
          ),
        ],
      );
    } else if (node.payload is DocumentPayload) {
      final payload = node.payload as DocumentPayload;
      final currentPreset = DocumentPaperCatalog.findById(
        payload.paperPresetId,
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DOCUMENT CARD',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(
            key: ValueKey('inspector-document-title-gap'),
            height: AppSpacing.sm + AppSpacing.xxs,
          ),
          // Action Button: Open Document Editor
          SizedBox(
            width: double.infinity,
            child: UiButton(
              prefix: const Icon(Icons.edit_note_outlined, size: 16),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => DocumentEditorScreen(
                      initialPayload: payload,
                      onSave: (updated) {
                        final latestNode = ref
                            .read(documentNodesProvider)
                            .firstWhere(
                              (n) => n.id == node.id,
                              orElse: () => node,
                            );
                        ref
                            .read(documentNodesProvider.notifier)
                            .updateNode(
                              latestNode.copyWith(
                                name: updated.title,
                                payload: updated,
                              ),
                            );
                      },
                      onSaveAndExit: (updated) {
                        final latestNode = ref
                            .read(documentNodesProvider)
                            .firstWhere(
                              (n) => n.id == node.id,
                              orElse: () => node,
                            );
                        ref
                            .read(documentNodesProvider.notifier)
                            .updateNode(
                              latestNode.copyWith(
                                name: updated.title,
                                payload: updated,
                              ),
                            );
                      },
                    ),
                  ),
                );
              },
              child: const Text('OPEN DOCUMENT EDITOR'),
            ),
          ),
          Divider(color: tokens.panelBorder, height: AppSpacing.xl),
          Text(
            'PAGE & TEMPLATE',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Paper Size Template
          _InspectorSelect<String>(
            label: 'Paper Template',
            value: payload.paperPresetId,
            options: [
              for (final preset in DocumentPaperCatalog.presets)
                (preset.id, preset.name),
            ],
            onChanged: (presetId) {
              final newPreset = DocumentPaperCatalog.findById(presetId);
              final nextW = newPreset.getEffectiveWidth(payload.isLandscape);
              final nextH = newPreset.getEffectiveHeight(payload.isLandscape);
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      width: nextW,
                      height: nextH,
                      payload: payload.copyWith(paperPresetId: presetId),
                    ),
                  );
            },
          ),
          const SizedBox(
            key: ValueKey('inspector-document-template-gap'),
            height: AppSpacing.sm + AppSpacing.xxs,
          ),
          // Orientation Switch
          Row(
            children: [
              Expanded(
                child: UiButton(
                  variant: !payload.isLandscape
                      ? UiButtonVariant.primary
                      : UiButtonVariant.outline,
                  size: UiButtonSize.sm,
                  prefix: const Icon(Icons.crop_portrait, size: 14),
                  onPressed: payload.isLandscape
                      ? () {
                          final newW = currentPreset.getEffectiveWidth(false);
                          final newH = currentPreset.getEffectiveHeight(false);
                          ref
                              .read(documentNodesProvider.notifier)
                              .updateNode(
                                node.copyWith(
                                  width: newW,
                                  height: newH,
                                  payload: payload.copyWith(isLandscape: false),
                                ),
                              );
                        }
                      : null,
                  child: const Text('Portrait'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: UiButton(
                  variant: payload.isLandscape
                      ? UiButtonVariant.primary
                      : UiButtonVariant.outline,
                  size: UiButtonSize.sm,
                  prefix: const Icon(Icons.crop_landscape, size: 14),
                  onPressed: !payload.isLandscape
                      ? () {
                          final newW = currentPreset.getEffectiveWidth(true);
                          final newH = currentPreset.getEffectiveHeight(true);
                          ref
                              .read(documentNodesProvider.notifier)
                              .updateNode(
                                node.copyWith(
                                  width: newW,
                                  height: newH,
                                  payload: payload.copyWith(isLandscape: true),
                                ),
                              );
                        }
                      : null,
                  child: const Text('Landscape'),
                ),
              ),
            ],
          ),
          Divider(color: tokens.panelBorder, height: AppSpacing.xl),
          Text(
            'CARD APPEARANCE',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(
            key: ValueKey('inspector-document-appearance-gap'),
            height: AppSpacing.sm + AppSpacing.xxs,
          ),
          // Paper Tone Presets
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: DocumentThemeCatalog.themes.map((theme) {
              final isSelected = theme.id == payload.themeId;
              return Semantics(
                button: true,
                selected: isSelected,
                label: '${theme.name} paper theme',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    ref
                        .read(documentNodesProvider.notifier)
                        .updateNode(
                          node.copyWith(
                            payload: payload.copyWith(
                              themeId: theme.id,
                              backgroundColor: theme.backgroundColor,
                              borderColor: theme.borderColor,
                            ),
                          ),
                        );
                  },
                  child: Container(
                    width: 54,
                    height: 32,
                    decoration: BoxDecoration(
                      color: theme.backgroundColor,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.braunOrange
                            : theme.borderColor,
                        width: isSelected ? 2.0 : 1.0,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        theme.name.split(' ').first,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: theme.textColor,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(
            key: ValueKey('inspector-document-theme-gap'),
            height: AppSpacing.sm + AppSpacing.xs + AppSpacing.xxs,
          ),
          // Background Color Custom Picker
          _buildColorPickerTile(
            context,
            'Background',
            payload.backgroundColor,
            (c) => ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: payload.copyWith(backgroundColor: c)),
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Border Color Custom Picker
          _buildColorPickerTile(
            context,
            'Border Color',
            payload.borderColor,
            (c) => ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: payload.copyWith(borderColor: c)),
                ),
          ),
          const SizedBox(
            key: ValueKey('inspector-document-border-gap'),
            height: AppSpacing.sm + AppSpacing.xxs,
          ),
          // Border Width & Corner Radius
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Border: ${payload.borderWidth.toStringAsFixed(1)}px',
                      style: TextStyle(color: tokens.textMuted, fontSize: 10),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                      ),
                      child: _buildSlider(
                        value: payload.borderWidth.clamp(0.0, 10.0),
                        min: 0.0,
                        max: 10.0,
                        onChanged: (v) {
                          ref
                              .read(documentNodesProvider.notifier)
                              .updateNode(
                                node.copyWith(
                                  payload: payload.copyWith(borderWidth: v),
                                ),
                              );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Radius: ${payload.cornerRadius.round()}px',
                      style: TextStyle(color: tokens.textMuted, fontSize: 10),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                      ),
                      child: _buildSlider(
                        value: payload.cornerRadius.clamp(0.0, 32.0),
                        min: 0.0,
                        max: 32.0,
                        onChanged: (v) {
                          ref
                              .read(documentNodesProvider.notifier)
                              .updateNode(
                                node.copyWith(
                                  payload: payload.copyWith(cornerRadius: v),
                                ),
                              );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          // Toggle: Drop Shadow
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Drop Shadow',
                style: TextStyle(color: tokens.text, fontSize: 11),
              ),
              UiSwitch(
                value: payload.hasShadow,
                onChange: (v) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(payload: payload.copyWith(hasShadow: v)),
                      );
                },
              ),
            ],
          ),
        ],
      );
    } else if (node.payload is GroupPayload) {
      final payload = node.payload as GroupPayload;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GROUP CONTAINER',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Contains ${payload.childNodeIds.length} elements',
            style: TextStyle(color: tokens.text, fontSize: 12),
          ),
          const SizedBox(height: AppSpacing.md),
          UiButton(
            onPressed: () {
              ref.read(documentNodesProvider.notifier).ungroupNodes(node.id);
              ref
                  .read(selectionProvider.notifier)
                  .selectAll(payload.childNodeIds);
            },
            variant: UiButtonVariant.outline,
            prefix: const Icon(Icons.folder_open, size: 14),
            child: const Text('Ungroup (Ctrl+Shift+G)'),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildMermaidControls(
    BuildContext context,
    WidgetRef ref,
    CanvasNode source,
  ) {
    final tokens = context.appTokens;
    final payload = source.payload as MermaidPayload;
    final isNative = payload.renderMode == MermaidRenderMode.native;
    final isConverting = ref
        .watch(mermaidConversionInFlightProvider)
        .contains(source.id);

    void showConversionResult(MermaidConversionResult result) {
      final diagnostic = result.diagnostic;
      if (diagnostic != null) {
        showUiToast(context, diagnostic.message, variant: UiToastVariant.error);
        return;
      }
      if (result.warnings.isEmpty) return;
      showUiToast(
        context,
        result.warnings.first.message,
        variant: UiToastVariant.warning,
      );
    }

    Future<void> runConversion() async {
      final notifier = ref.read(documentNodesProvider.notifier);
      final result = isNative
          ? await notifier.regenerateMermaidNodeAsync(source.id)
          : await notifier.convertMermaidNodeAsync(source.id);
      if (context.mounted) showConversionResult(result);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MERMAID SOURCE',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          isNative
              ? 'Native graph: ${payload.nativeNodeIds.length} nodes, ${payload.nativeEdgeIds.length} edges'
              : 'Source-backed local preview',
          style: TextStyle(color: tokens.textMuted, fontSize: 11),
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            UiButton(
              key: ValueKey('mermaid-edit-source-${source.id}'),
              onPressed: onEditMermaid == null
                  ? null
                  : () => onEditMermaid!(source),
              variant: UiButtonVariant.outline,
              size: UiButtonSize.sm,
              prefix: const Icon(Icons.edit_outlined, size: 14),
              child: const Text('Edit source'),
            ),
            if (isNative)
              UiButton(
                key: ValueKey('mermaid-regenerate-${source.id}'),
                onPressed: isConverting
                    ? null
                    : () => unawaited(runConversion()),
                variant: UiButtonVariant.outline,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.refresh, size: 14),
                child: Text(isConverting ? 'Converting…' : 'Regenerate'),
              )
            else
              UiButton(
                key: ValueKey('mermaid-convert-${source.id}'),
                onPressed: isConverting
                    ? null
                    : () => unawaited(runConversion()),
                variant: UiButtonVariant.primary,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.account_tree_outlined, size: 14),
                child: Text(isConverting ? 'Converting…' : 'Convert to native'),
              ),
            if (isNative)
              UiButton(
                key: ValueKey('mermaid-revert-${source.id}'),
                onPressed: () => showConversionResult(
                  ref
                      .read(documentNodesProvider.notifier)
                      .revertMermaidToSource(source.id),
                ),
                variant: UiButtonVariant.ghost,
                size: UiButtonSize.sm,
                prefix: const Icon(Icons.undo, size: 14),
                child: const Text('Revert to source'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSlider({
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    final range = max - min;
    final normalized = range <= 0
        ? 0.0
        : ((value - min) / range).clamp(0.0, 1.0);
    return UiSlider(
      value: normalized,
      onChanged: (next) => onChanged(min + next * range),
    );
  }

  Widget _buildTypographyControls(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
    TextPayload payload,
  ) {
    final tokens = context.appTokens;
    const fonts = [
      'Inter',
      'Roboto',
      'Poppins',
      'Fira Code',
      'Caveat',
      'Playfair Display',
    ];
    final pathNodes = ref
        .read(documentNodesProvider)
        .where((candidate) => candidate.type == NodeType.vectorPath)
        .toList(growable: false);
    final selectedPathId =
        pathNodes.any((candidate) => candidate.id == payload.textPathNodeId)
        ? payload.textPathNodeId!
        : '';

    void updatePayload(TextPayload next) {
      ref
          .read(documentNodesProvider.notifier)
          .updateNode(node.copyWith(payload: next));
    }

    Widget select<T>({
      required String label,
      required T value,
      required List<(T, String)> options,
      required ValueChanged<T?> onChanged,
    }) => _InspectorSelect<T>(
      label: label,
      value: value,
      options: options,
      onChanged: onChanged,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InspectorTextField(
          key: ValueKey('text_${node.id}'),
          value: payload.text,
          label: payload.renderMode == TextRenderMode.markdown
              ? 'Markdown Text'
              : 'Text Content',
          minLines: payload.renderMode == TextRenderMode.markdown ? 6 : 3,
          maxLines: payload.renderMode == TextRenderMode.markdown ? 6 : 3,
          onChanged: (value) => updatePayload(payload.copyWith(text: value)),
        ),
        const SizedBox(height: AppSpacing.sm),
        select<TextRenderMode>(
          label: 'Render',
          value: payload.renderMode,
          options: [
            for (final mode in TextRenderMode.values)
              (mode, mode.name.toUpperCase()),
          ],
          onChanged: (mode) {
            if (mode != null) {
              updatePayload(payload.copyWith(renderMode: mode));
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        select<String>(
          label: 'Font',
          value: fonts.contains(payload.fontFamily)
              ? payload.fontFamily
              : fonts.first,
          options: [for (final font in fonts) (font, font)],
          onChanged: (value) {
            if (value != null) {
              updatePayload(payload.copyWith(fontFamily: value));
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _buildNumberInput(
                'Weight Axis',
                payload.fontAxes['wght'] ?? payload.fontWeight.value.toDouble(),
                (value) {
                  final axes = Map<String, double>.from(payload.fontAxes)
                    ..['wght'] = value.clamp(1.0, 1000.0).toDouble();
                  updatePayload(payload.copyWith(fontAxes: axes));
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _buildNumberInput(
                'Width Axis',
                payload.fontAxes['wdth'] ?? 100.0,
                (value) {
                  final axes = Map<String, double>.from(payload.fontAxes)
                    ..['wdth'] = value.clamp(1.0, 1000.0).toDouble();
                  updatePayload(payload.copyWith(fontAxes: axes));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _buildNumberInput('Size', payload.fontSize, (value) {
                updatePayload(
                  payload.copyWith(fontSize: value.clamp(6.0, 200.0)),
                );
              }),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: select<FontWeight>(
                label: 'Weight',
                value: payload.fontWeight,
                options: const [
                  (FontWeight.normal, 'Regular'),
                  (FontWeight.w500, 'Medium'),
                  (FontWeight.bold, 'Bold'),
                ],
                onChanged: (value) {
                  if (value != null) {
                    updatePayload(payload.copyWith(fontWeight: value));
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildColorPickerTile(context, 'Text Color', payload.color, (color) {
          updatePayload(payload.copyWith(color: color));
        }),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            _buildStyleToggle('B', payload.fontWeight == FontWeight.bold, () {
              updatePayload(
                payload.copyWith(
                  fontWeight: payload.fontWeight == FontWeight.bold
                      ? FontWeight.normal
                      : FontWeight.bold,
                ),
              );
            }),
            _buildStyleToggle('I', payload.fontStyle == FontStyle.italic, () {
              updatePayload(
                payload.copyWith(
                  fontStyle: payload.fontStyle == FontStyle.italic
                      ? FontStyle.normal
                      : FontStyle.italic,
                ),
              );
            }),
            _buildStyleToggle('U', payload.underline, () {
              updatePayload(payload.copyWith(underline: !payload.underline));
            }),
            _buildStyleToggle('S', payload.strikethrough, () {
              updatePayload(
                payload.copyWith(strikethrough: !payload.strikethrough),
              );
            }),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        select<TextSizeMode>(
          label: 'Sizing',
          value: payload.sizeMode,
          options: [for (final mode in TextSizeMode.values) (mode, mode.name)],
          onChanged: (mode) {
            if (mode != null) updatePayload(payload.copyWith(sizeMode: mode));
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        select<TextAlign>(
          label: 'Align',
          value: payload.textAlign,
          options: const [
            (TextAlign.left, 'Left'),
            (TextAlign.center, 'Center'),
            (TextAlign.right, 'Right'),
            (TextAlign.justify, 'Justify'),
          ],
          onChanged: (align) {
            if (align != null) {
              updatePayload(payload.copyWith(textAlign: align));
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        select<TextVerticalAlign>(
          label: 'Vertical',
          value: payload.verticalAlign,
          options: [
            for (final align in TextVerticalAlign.values) (align, align.name),
          ],
          onChanged: (align) {
            if (align != null) {
              updatePayload(payload.copyWith(verticalAlign: align));
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        select<TextTransformCase>(
          label: 'Case',
          value: payload.textTransform,
          options: [
            for (final mode in TextTransformCase.values) (mode, mode.name),
          ],
          onChanged: (mode) {
            if (mode != null) {
              updatePayload(payload.copyWith(textTransform: mode));
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        _InspectorTextField(
          key: ValueKey('text_locale_${node.id}'),
          value: payload.localeTag ?? '',
          label: 'Locale fallback',
          hint: 'id-ID or en-US',
          onChanged: (value) => updatePayload(
            payload.copyWith(
              localeTag: value.trim().isEmpty ? null : value.trim(),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        select<TextWrapMode>(
          label: 'Wrap',
          value: payload.wrapMode,
          options: [for (final mode in TextWrapMode.values) (mode, mode.name)],
          onChanged: (mode) {
            if (mode != null) updatePayload(payload.copyWith(wrapMode: mode));
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                'Spellcheck / IME fallback',
                style: TextStyle(color: tokens.text, fontSize: 11),
              ),
            ),
            UiSwitch(
              value: payload.spellCheckEnabled,
              onChange: (value) =>
                  updatePayload(payload.copyWith(spellCheckEnabled: value)),
            ),
          ],
        ),
        if (pathNodes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          select<String>(
            label: 'Text on Path',
            value: selectedPathId,
            options: [
              const ('', 'None'),
              for (final path in pathNodes)
                (
                  path.id,
                  path.name?.trim().isNotEmpty == true
                      ? path.name!
                      : 'Vector ${path.id.substring(0, path.id.length.clamp(0, 8))}',
                ),
            ],
            onChanged: (pathId) {
              if (pathId != null) {
                updatePayload(
                  payload.copyWith(
                    textPathNodeId: pathId.isEmpty ? null : pathId,
                  ),
                );
              }
            },
          ),
        ],
        if (payload.textPathNodeId != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _buildNumberInput(
                  'Path Offset',
                  payload.textPathOffset,
                  (value) =>
                      updatePayload(payload.copyWith(textPathOffset: value)),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: select<TextPathAlignment>(
                  label: 'Path Align',
                  value: payload.textPathAlignment,
                  options: [
                    for (final alignment in TextPathAlignment.values)
                      (alignment, alignment.name),
                  ],
                  onChanged: (alignment) {
                    if (alignment != null) {
                      updatePayload(
                        payload.copyWith(textPathAlignment: alignment),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Reverse path direction',
                  style: TextStyle(color: tokens.text, fontSize: 11),
                ),
              ),
              UiSwitch(
                value: payload.textPathReversed,
                onChange: (value) =>
                    updatePayload(payload.copyWith(textPathReversed: value)),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        _buildNumberInput('Line Height', payload.lineHeight, (value) {
          updatePayload(payload.copyWith(lineHeight: value.clamp(0.5, 4.0)));
        }),
        const SizedBox(height: AppSpacing.sm),
        _buildNumberInput('Letter Space', payload.letterSpacing, (value) {
          updatePayload(
            payload.copyWith(letterSpacing: value.clamp(-5.0, 20.0)),
          );
        }),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _buildNumberInput('Stroke Width', payload.strokeWidth, (
                value,
              ) {
                updatePayload(
                  payload.copyWith(strokeWidth: value.clamp(0.0, 20.0)),
                );
              }),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _buildNumberInput(
                'Shadow Blur',
                payload.shadowBlurRadius,
                (value) {
                  updatePayload(
                    payload.copyWith(shadowBlurRadius: value.clamp(0.0, 100.0)),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildColorPickerTile(
          context,
          'Outline Color',
          payload.strokeColor ?? payload.color,
          (color) => updatePayload(payload.copyWith(strokeColor: color)),
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildColorPickerTile(
          context,
          'Shadow Color',
          payload.shadowColor ?? Colors.black,
          (color) => updatePayload(payload.copyWith(shadowColor: color)),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _buildNumberInput(
                'Badge Radius',
                payload.backgroundRadius,
                (value) {
                  updatePayload(
                    payload.copyWith(backgroundRadius: value.clamp(0.0, 100.0)),
                  );
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _buildNumberInput(
                'Badge Padding',
                payload.backgroundPadding,
                (value) {
                  updatePayload(
                    payload.copyWith(
                      backgroundPadding: value.clamp(0.0, 100.0),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildColorPickerTile(
          context,
          'Background Badge',
          payload.backgroundColor ?? Colors.transparent,
          (color) => updatePayload(payload.copyWith(backgroundColor: color)),
        ),
        if (payload.renderMode == TextRenderMode.rich) ...[
          const SizedBox(height: AppSpacing.md),
          _buildRichTextEditor(context, ref, node, payload),
        ],
      ],
    );
  }

  Widget _buildRichTextEditor(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
    TextPayload payload,
  ) {
    final blocks = payload.blocks ?? const <RichTextBlock>[];

    Widget update(List<RichTextBlock> newBlocks) {
      ref
          .read(documentNodesProvider.notifier)
          .updateNode(
            node.copyWith(payload: payload.copyWith(blocks: newBlocks)),
          );
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InspectorSelect<RichTextBlockType>(
          label: 'Add Block',
          value: RichTextBlockType.paragraph,
          options: [
            for (final item in RichTextBlockType.values)
              (item, item.name.toUpperCase()),
          ],
          onChanged: (type) {
            update([...blocks, RichTextBlock(type: type)]);
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        ...blocks.asMap().entries.map((entry) {
          final index = entry.key;
          final block = entry.value;
          final plainText = block.plainText;
          return _buildBlockTile(
            context,
            ref,
            node,
            payload,
            index,
            block,
            plainText,
          );
        }),
      ],
    );
  }

  Widget _buildBlockTile(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
    TextPayload payload,
    int index,
    RichTextBlock block,
    String plainText,
  ) {
    final tokens = context.appTokens;
    final blocks = payload.blocks ?? const <RichTextBlock>[];

    void update(List<RichTextBlock> newBlocks) {
      ref
          .read(documentNodesProvider.notifier)
          .updateNode(
            node.copyWith(payload: payload.copyWith(blocks: newBlocks)),
          );
    }

    return Container(
      key: ValueKey('inspector-rich-text-block-$index'),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: tokens.panelElevated,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: tokens.panelBorder, width: AppBorder.thin),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  block.type.name.toUpperCase(),
                  style: TextStyle(
                    color: tokens.accent,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              UiIconButton(
                icon: Icons.delete_outline,
                size: UiButtonSize.sm,
                variant: UiButtonVariant.destructive,
                tooltip: 'Delete rich text block',
                onPressed: () {
                  final newBlocks = List<RichTextBlock>.from(blocks)
                    ..removeAt(index);
                  update(newBlocks);
                },
              ),
            ],
          ),
          _InspectorTextField(
            key: ValueKey('rich_block_$index'),
            value: plainText,
            minLines: 3,
            maxLines: 3,
            onChanged: (val) {
              update(RichTextEditing.replaceBlockText(blocks, index, val));
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              _buildStyleToggle('B', _spanBold(block), () {
                final spans = block.spans.isEmpty
                    ? [const RichTextSpan(text: '')]
                    : block.spans;
                final newBlocks = List<RichTextBlock>.from(blocks);
                newBlocks[index] = block.copyWith(
                  spans: spans
                      .map((s) => s.copyWith(bold: !_spanBold(block)))
                      .toList(),
                );
                update(newBlocks);
              }),
              _buildStyleToggle('I', _spanItalic(block), () {
                final spans = block.spans.isEmpty
                    ? [const RichTextSpan(text: '')]
                    : block.spans;
                final newBlocks = List<RichTextBlock>.from(blocks);
                newBlocks[index] = block.copyWith(
                  spans: spans
                      .map((s) => s.copyWith(italic: !_spanItalic(block)))
                      .toList(),
                );
                update(newBlocks);
              }),
              _buildStyleToggle('U', _spanUnderline(block), () {
                final spans = block.spans.isEmpty
                    ? [const RichTextSpan(text: '')]
                    : block.spans;
                final newBlocks = List<RichTextBlock>.from(blocks);
                newBlocks[index] = block.copyWith(
                  spans: spans
                      .map((s) => s.copyWith(underline: !_spanUnderline(block)))
                      .toList(),
                );
                update(newBlocks);
              }),
              _buildStyleToggle('S', _spanStrike(block), () {
                final spans = block.spans.isEmpty
                    ? [const RichTextSpan(text: '')]
                    : block.spans;
                final newBlocks = List<RichTextBlock>.from(blocks);
                newBlocks[index] = block.copyWith(
                  spans: spans
                      .map(
                        (s) => s.copyWith(strikethrough: !_spanStrike(block)),
                      )
                      .toList(),
                );
                update(newBlocks);
              }),
              _buildStyleToggle('🔗', _spanLink(block) != null, () {
                _promptLink(context, block, index, blocks, update);
              }),
            ],
          ),
        ],
      ),
    );
  }

  void _promptLink(
    BuildContext context,
    RichTextBlock block,
    int index,
    List<RichTextBlock> blocks,
    void Function(List<RichTextBlock>) update,
  ) {
    final controller = TextEditingController(text: _spanLink(block));
    showUiDialog<void>(
      context: context,
      builder: (dialogContext) => UiDialog(
        semanticsLabel: 'Add hyperlink',
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(AppSpacing.pageWide),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add Hyperlink', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.md),
              UiTextField(
                controller: controller,
                autofocus: true,
                hint: 'https://...',
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  UiButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    variant: UiButtonVariant.ghost,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  UiButton(
                    onPressed: () {
                      final url = RichTextEditing.normalizeLink(
                        controller.text,
                      );
                      final spans = block.spans.isEmpty
                          ? [const RichTextSpan(text: '')]
                          : block.spans;
                      final newBlocks = List<RichTextBlock>.from(blocks);
                      newBlocks[index] = block.copyWith(
                        spans: spans
                            .map((s) => s.copyWith(linkUrl: url))
                            .toList(),
                      );
                      update(newBlocks);
                      Navigator.pop(dialogContext);
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  bool _spanBold(RichTextBlock block) =>
      block.spans.isNotEmpty && block.spans.first.bold;
  bool _spanItalic(RichTextBlock block) =>
      block.spans.isNotEmpty && block.spans.first.italic;
  bool _spanUnderline(RichTextBlock block) =>
      block.spans.isNotEmpty && block.spans.first.underline;
  bool _spanStrike(RichTextBlock block) =>
      block.spans.isNotEmpty && block.spans.first.strikethrough;
  String? _spanLink(RichTextBlock block) =>
      block.spans.isNotEmpty ? block.spans.first.linkUrl : null;

  Widget _buildStyleToggle(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: UiButton(
        onPressed: onTap,
        semanticsLabel: 'Toggle $label formatting',
        variant: active ? UiButtonVariant.primary : UiButtonVariant.outline,
        size: UiButtonSize.sm,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            decoration: label == 'U' ? TextDecoration.underline : null,
            decorationThickness: 2,
          ),
        ),
      ),
    );
  }

  void _showNodeHistoryDialog(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
  ) {
    final history = ref.read(nodeHistoryProvider.notifier).historyFor(node.id);

    showUiDialog<void>(
      context: context,
      builder: (dialogContext) => UiDialog(
        semanticsLabel: 'Object history',
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(AppSpacing.pageWide),
          child: SizedBox(
            width: 320,
            height: 360,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('OBJECT HISTORY', style: style.titleTextStyle),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: history.isEmpty
                      ? const Center(
                          child: Text(
                            'No history recorded yet.\nEdit this object to create snapshots.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          itemCount: history.length,
                          itemBuilder: (context, index) {
                            final entry = history[history.length - 1 - index];
                            return UiButton(
                              onPressed: () {
                                ref
                                    .read(documentNodesProvider.notifier)
                                    .updateNode(entry.snapshot);
                                Navigator.pop(dialogContext);
                              },
                              variant: UiButtonVariant.outline,
                              prefix: const Icon(Icons.restore, size: 16),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_formatTime(entry.timestamp)),
                                    Text(
                                      entry.snapshot.type.name.toUpperCase(),
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: UiButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    variant: UiButtonVariant.ghost,
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _replaceImage(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
    ImagePayload payload,
  ) async {
    final operationGeneration = _beginArtifactOperation();
    final sync = ref.read(supabaseSyncServiceProvider);
    final accountId = sync.currentUserId;
    final picker = AssetService(sync);
    final result = await picker.pickImage(projectId: projectId);
    if (result == null ||
        _currentReplacementNode(
              ref: ref,
              capturedNode: node,
              generation: operationGeneration,
              accountId: accountId,
            ) ==
            null) {
      return;
    }
    final bytes = result.bytes;
    final imageReference = bytes == null || bytes.isEmpty
        ? null
        : validImageArtifactReference(
            (await _imageStore(
              ref,
            ).save(bytes, fileName: result.name)).reference,
          );
    if (_currentReplacementNode(
          ref: ref,
          capturedNode: node,
          generation: operationGeneration,
          accountId: accountId,
        ) ==
        null) {
      return;
    }
    final storagePath = _validatedImageStoragePath(ref, result.storagePath);
    if (imageReference == null && storagePath == null) {
      if (context.mounted) {
        showUiToast(
          context,
          'The selected image could not be stored.',
          variant: UiToastVariant.error,
        );
      }
      return;
    }
    if (bytes != null && bytes.isNotEmpty && imageReference != null) {
      await _cache().decodeAndCacheBytes(imageReference, bytes);
    }
    if (!context.mounted) return;
    final current = _currentReplacementNode(
      ref: ref,
      capturedNode: node,
      generation: operationGeneration,
      accountId: accountId,
    );
    if (current == null || current.payload is! ImagePayload) return;
    final currentPayload = current.payload as ImagePayload;
    final assetId = _imageAssetId(ref, current, currentPayload);
    _upsertDocumentAsset(
      ref,
      assetId: assetId,
      kind: DocumentAssetKind.image,
      name: result.name,
      mimeType: result.detectedMimeType,
      artifactReference: imageReference,
      storagePath: storagePath,
      declaredSize: result.size,
      bytes: bytes,
    );
    ref
        .read(documentNodesProvider.notifier)
        .updateNode(
          current.copyWith(
            payload: currentPayload.copyWith(
              imageArtifactReference: imageReference,
              storagePath: storagePath,
              clearImageArtifactReference: imageReference == null,
              clearStoragePath: storagePath == null,
              clearLocalPath: true,
              clearUrl: true,
              assetId: assetId,
              caption: currentPayload.caption,
              cropX: 0.0,
              cropY: 0.0,
              cropWidth: 1.0,
              cropHeight: 1.0,
              focalPointX: 0.5,
              focalPointY: 0.5,
              clearBackgroundMask: true,
            ),
          ),
        );
  }

  Future<void> _batchRelinkImages(
    BuildContext context,
    WidgetRef ref,
    List<String> selectedIds,
  ) async {
    final operationGeneration = _beginArtifactOperation();
    final sync = ref.read(supabaseSyncServiceProvider);
    final accountId = sync.currentUserId;
    final nodes = ref.read(documentNodesProvider);
    final selectedImages = nodes
        .where(
          (node) =>
              selectedIds.contains(node.id) &&
              node.type == NodeType.image &&
              node.payload is ImagePayload,
        )
        .toList(growable: false);
    if (selectedImages.length < 2) return;

    final results = await AssetService(sync).pickImages(projectId: projectId);
    if (!context.mounted ||
        results.isEmpty ||
        !_isArtifactOperationCurrent(
          generation: operationGeneration,
          accountId: accountId,
        )) {
      return;
    }

    final assignments = planImageRelinks(selectedImages, results);
    final notifier = ref.read(documentNodesProvider.notifier);
    var relinkedCount = 0;
    for (final assignment in assignments) {
      final capturedNode = nodes.firstWhere(
        (candidate) => candidate.id == assignment.nodeId,
      );
      if (_currentReplacementNode(
            ref: ref,
            capturedNode: capturedNode,
            generation: operationGeneration,
            accountId: accountId,
          ) ==
          null) {
        continue;
      }
      final result = assignment.asset;
      final bytes = result.bytes;
      final imageReference = bytes == null || bytes.isEmpty
          ? null
          : validImageArtifactReference(
              (await _imageStore(
                ref,
              ).save(bytes, fileName: result.name)).reference,
            );
      if (_currentReplacementNode(
            ref: ref,
            capturedNode: capturedNode,
            generation: operationGeneration,
            accountId: accountId,
          ) ==
          null) {
        continue;
      }
      final storagePath = _validatedImageStoragePath(ref, result.storagePath);
      if (imageReference == null && storagePath == null) continue;
      if (bytes != null && bytes.isNotEmpty && imageReference != null) {
        await _cache().decodeAndCacheBytes(imageReference, bytes);
      }
      final current = _currentReplacementNode(
        ref: ref,
        capturedNode: capturedNode,
        generation: operationGeneration,
        accountId: accountId,
      );
      if (current == null || current.payload is! ImagePayload) continue;
      final currentPayload = current.payload as ImagePayload;
      final assetId = _imageAssetId(ref, current, currentPayload);
      _upsertDocumentAsset(
        ref,
        assetId: assetId,
        kind: DocumentAssetKind.image,
        name: result.name,
        mimeType: result.detectedMimeType,
        artifactReference: imageReference,
        storagePath: storagePath,
        declaredSize: result.size,
        bytes: bytes,
      );
      notifier.updateNode(
        current.copyWith(
          payload: currentPayload.copyWith(
            imageArtifactReference: imageReference,
            storagePath: storagePath,
            clearImageArtifactReference: imageReference == null,
            clearStoragePath: storagePath == null,
            clearLocalPath: true,
            clearUrl: true,
            assetId: assetId,
          ),
        ),
      );
      relinkedCount++;
    }
    if (context.mounted &&
        _isArtifactOperationCurrent(
          generation: operationGeneration,
          accountId: accountId,
        )) {
      showUiToast(
        context,
        'Relinked $relinkedCount image${relinkedCount == 1 ? '' : 's'}.',
      );
    }
  }

  Future<void> _pickImageMask(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
    ImagePayload payload,
  ) async {
    final operationGeneration = _beginArtifactOperation();
    final sync = ref.read(supabaseSyncServiceProvider);
    final accountId = sync.currentUserId;
    final result = await AssetService(sync).pickImage(projectId: projectId);
    if (!context.mounted ||
        result == null ||
        _currentReplacementNode(
              ref: ref,
              capturedNode: node,
              generation: operationGeneration,
              accountId: accountId,
            ) ==
            null) {
      return;
    }

    final bytes = result.bytes;
    final imageReference = bytes == null || bytes.isEmpty
        ? null
        : validImageArtifactReference(
            (await _imageStore(
              ref,
            ).save(bytes, fileName: result.name)).reference,
          );
    if (_currentReplacementNode(
          ref: ref,
          capturedNode: node,
          generation: operationGeneration,
          accountId: accountId,
        ) ==
        null) {
      return;
    }
    final storagePath = _validatedImageStoragePath(ref, result.storagePath);
    if (imageReference == null && storagePath == null) {
      if (!context.mounted) return;
      showUiToast(
        context,
        'The selected mask could not be stored. Upload it or choose a local file.',
        variant: UiToastVariant.error,
      );
      return;
    }

    if (bytes != null && bytes.isNotEmpty && imageReference != null) {
      await _cache().decodeAndCacheBytes(imageReference, bytes);
    }

    if (!context.mounted) return;
    final current = _currentReplacementNode(
      ref: ref,
      capturedNode: node,
      generation: operationGeneration,
      accountId: accountId,
    );
    if (current == null || current.payload is! ImagePayload) return;
    final currentPayload = current.payload as ImagePayload;
    final maskAssetId = stableDocumentAssetId(
      candidate: currentPayload.backgroundMask?.assetId,
      manifest: ref.read(documentAssetsProvider),
      nodes: ref.read(documentNodesProvider),
      ownerNodeId: current.id,
    );
    _upsertDocumentAsset(
      ref,
      assetId: maskAssetId,
      kind: DocumentAssetKind.image,
      name: result.name,
      mimeType: result.detectedMimeType,
      artifactReference: imageReference,
      storagePath: storagePath,
      declaredSize: result.size,
      bytes: bytes,
    );
    ref
        .read(documentNodesProvider.notifier)
        .updateNode(
          current.copyWith(
            payload: currentPayload.copyWith(
              backgroundMask: ImageMask(
                assetId: maskAssetId,
                imageArtifactReference: imageReference,
                storagePath: storagePath,
              ),
            ),
          ),
        );
  }

  (double, double) _imageAdjustmentRange(ImageAdjustmentType type) {
    return switch (type) {
      ImageAdjustmentType.brightness => (-1.0, 1.0),
      ImageAdjustmentType.contrast => (0.0, 2.0),
      ImageAdjustmentType.saturation => (0.0, 2.0),
      ImageAdjustmentType.exposure => (-2.0, 2.0),
      ImageAdjustmentType.temperature => (-1.0, 1.0),
      ImageAdjustmentType.highlights => (-1.0, 1.0),
      ImageAdjustmentType.shadows => (-1.0, 1.0),
      ImageAdjustmentType.grayscale => (0.0, 1.0),
      ImageAdjustmentType.sepia => (0.0, 1.0),
      ImageAdjustmentType.invert => (0.0, 1.0),
      ImageAdjustmentType.blur => (0.0, 20.0),
      ImageAdjustmentType.opacity => (0.0, 1.0),
    };
  }

  String _imageAdjustmentLabel(ImageAdjustmentType type) {
    return switch (type) {
      ImageAdjustmentType.brightness => 'Brightness',
      ImageAdjustmentType.contrast => 'Contrast',
      ImageAdjustmentType.saturation => 'Saturation',
      ImageAdjustmentType.exposure => 'Exposure',
      ImageAdjustmentType.temperature => 'Temperature',
      ImageAdjustmentType.highlights => 'Highlights',
      ImageAdjustmentType.shadows => 'Shadows',
      ImageAdjustmentType.grayscale => 'Grayscale',
      ImageAdjustmentType.sepia => 'Sepia',
      ImageAdjustmentType.invert => 'Invert',
      ImageAdjustmentType.blur => 'Blur',
      ImageAdjustmentType.opacity => 'Opacity',
    };
  }

  double _imageAdjustmentDefault(ImageAdjustmentType type) {
    return switch (type) {
      ImageAdjustmentType.brightness => 0.0,
      ImageAdjustmentType.contrast => 1.0,
      ImageAdjustmentType.saturation => 1.0,
      ImageAdjustmentType.exposure => 0.0,
      ImageAdjustmentType.temperature => 0.0,
      ImageAdjustmentType.highlights => 0.0,
      ImageAdjustmentType.shadows => 0.0,
      ImageAdjustmentType.grayscale => 1.0,
      ImageAdjustmentType.sepia => 1.0,
      ImageAdjustmentType.invert => 1.0,
      ImageAdjustmentType.blur => 4.0,
      ImageAdjustmentType.opacity => 1.0,
    };
  }

  void _addImageAdjustment(
    WidgetRef ref,
    CanvasNode node,
    ImagePayload payload,
    ImageAdjustmentType type,
  ) {
    final next = [
      ...payload.adjustments,
      ImageAdjustment(
        id: const Uuid().v4(),
        type: type,
        amount: _imageAdjustmentDefault(type),
      ),
    ];
    ref
        .read(documentNodesProvider.notifier)
        .updateNode(
          node.copyWith(payload: payload.copyWith(adjustments: next)),
        );
  }

  Widget _buildNumberInput(
    String label,
    double value,
    ValueChanged<double> onChanged,
  ) => _InspectorNumberInput(label: label, value: value, onChanged: onChanged);

  Widget _buildImageAssetControls(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
    ImagePayload payload,
  ) {
    final tokens = context.appTokens;
    final hasImageSource =
        (payload.imageArtifactReference?.trim().isNotEmpty ?? false) ||
        (payload.storagePath?.trim().isNotEmpty ?? false) ||
        (payload.localPath?.trim().isNotEmpty ?? false) ||
        (payload.url?.trim().isNotEmpty ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Image Header & Source
        Row(
          children: [
            Text(
              'IMAGE ASSET',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            Container(
              key: const ValueKey('inspector-image-source-badge'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs + AppSpacing.xxs,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF525252).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF525252)),
              ),
              child: Text(
                payload.imageArtifactReference != null
                    ? 'OWNED ARTIFACT'
                    : (payload.storagePath != null
                          ? 'PRIVATE STORAGE'
                          : (payload.url != null
                                ? 'COMPATIBILITY'
                                : (payload.localPath != null
                                      ? 'LOCAL FILE'
                                      : 'EMPTY'))),
                style: const TextStyle(
                  color: Color(0xFFBDBDBD),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        Text(
          payload.assetId ??
              payload.imageArtifactReference ??
              payload.storagePath ??
              payload.localPath ??
              (payload.url != null ? 'Compatibility Image' : 'No image loaded'),
          style: TextStyle(color: tokens.textMuted, fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),

        // Action Buttons Row: Replace & Crop
        Row(
          children: [
            Expanded(
              child: UiButton(
                variant: UiButtonVariant.outline,
                prefix: const Icon(Icons.file_upload_outlined, size: 14),
                onPressed: () => _replaceImage(context, ref, node, payload),
                child: Text(hasImageSource ? 'Replace' : 'Choose image'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
            Expanded(
              child: UiButton(
                variant: UiButtonVariant.outline,
                prefix: const Icon(Icons.crop, size: 14),
                onPressed: hasImageSource
                    ? () => _openImageCropDialog(context, ref, node, payload)
                    : null,
                child: const Text('Crop'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),

        // Transform Buttons: Rotate 90, Flip H, Flip V
        Row(
          children: [
            Expanded(
              child: UiButton(
                variant: UiButtonVariant.outline,
                prefix: const Icon(Icons.rotate_right, size: 14),
                onPressed: () {
                  final newRotation =
                      (node.rotation + (math.pi / 2)) % (2 * math.pi);
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(node.copyWith(rotation: newRotation));
                },
                child: const Text('Rotate'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
            UiButton(
              variant: payload.flipHorizontal
                  ? UiButtonVariant.primary
                  : UiButtonVariant.outline,
              size: UiButtonSize.sm,
              prefix: const Icon(Icons.flip, size: 16),
              onPressed: () {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          flipHorizontal: !payload.flipHorizontal,
                        ),
                      ),
                    );
              },
              child: const Text('Flip H'),
            ),
            const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
            UiButton(
              variant: payload.flipVertical
                  ? UiButtonVariant.primary
                  : UiButtonVariant.outline,
              size: UiButtonSize.sm,
              prefix: Transform.rotate(
                angle: math.pi / 2,
                child: const Icon(Icons.flip, size: 16),
              ),
              onPressed: () {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          flipVertical: !payload.flipVertical,
                        ),
                      ),
                    );
              },
              child: const Text('Flip V'),
            ),
          ],
        ),

        Divider(color: tokens.panelBorder, height: AppSpacing.xl),

        // BoxFit Fitting Modes
        Text(
          'IMAGE FIT MODE',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs + AppSpacing.xxs,
          runSpacing: AppSpacing.xs + AppSpacing.xxs,
          children: [
            for (final mode in [
              'cover',
              'contain',
              'fill',
              'fitWidth',
              'fitHeight',
            ])
              UiButton(
                variant: payload.fit == mode
                    ? UiButtonVariant.primary
                    : UiButtonVariant.outline,
                size: UiButtonSize.sm,
                onPressed: () {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(payload: payload.copyWith(fit: mode)),
                      );
                },
                child: Text(
                  mode == 'fitWidth'
                      ? 'Fit W'
                      : (mode == 'fitHeight'
                            ? 'Fit H'
                            : mode[0].toUpperCase() + mode.substring(1)),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),

        Divider(color: tokens.panelBorder, height: AppSpacing.xl),

        // Corner Radius Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'CORNER RADIUS',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            UiIconButton(
              icon: payload.independentCorners
                  ? Icons.rounded_corner
                  : Icons.all_out,
              tooltip: payload.independentCorners
                  ? 'Uniform Corners'
                  : 'Independent Corners',
              selected: payload.independentCorners,
              onPressed: () {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          independentCorners: !payload.independentCorners,
                        ),
                      ),
                    );
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        if (!payload.independentCorners) ...[
          _buildSlider(
            value: payload.cornerRadius,
            min: 0.0,
            max: 100.0,
            onChanged: (val) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: payload.copyWith(cornerRadius: val)),
                  );
            },
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: _buildNumberInput('TL', payload.topLeftRadius, (val) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(topLeftRadius: val),
                        ),
                      );
                }),
              ),
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              Expanded(
                child: _buildNumberInput('TR', payload.topRightRadius, (val) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(topRightRadius: val),
                        ),
                      );
                }),
              ),
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              Expanded(
                child: _buildNumberInput('BR', payload.bottomRightRadius, (
                  val,
                ) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(bottomRightRadius: val),
                        ),
                      );
                }),
              ),
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              Expanded(
                child: _buildNumberInput('BL', payload.bottomLeftRadius, (val) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(bottomLeftRadius: val),
                        ),
                      );
                }),
              ),
            ],
          ),
        ],

        Divider(color: tokens.panelBorder, height: AppSpacing.xl),

        // Border & Stroke
        Text(
          'BORDER & STROKE',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            _buildColorSquare(
              context,
              payload.strokeColor ?? Colors.transparent,
              (c) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          strokeColor: c,
                          strokeWidth: payload.strokeWidth > 0
                              ? payload.strokeWidth
                              : 2.0,
                        ),
                      ),
                    );
              },
            ),
            const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
            Expanded(
              child: _buildSlider(
                value: payload.strokeWidth,
                min: 0.0,
                max: 20.0,
                onChanged: (val) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(
                            strokeWidth: val,
                            strokeColor:
                                payload.strokeColor ?? const Color(0xFF64748B),
                          ),
                        ),
                      );
                },
              ),
            ),
            Text(
              '${payload.strokeWidth.toInt()}px',
              style: TextStyle(color: tokens.textMuted, fontSize: 11),
            ),
          ],
        ),

        Divider(color: tokens.panelBorder, height: AppSpacing.xl),

        // Color Filter Adjustments
        Text(
          'IMAGE FILTERS & PRESETS',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs + AppSpacing.xxs,
          runSpacing: AppSpacing.xs + AppSpacing.xxs,
          children: [
            UiButton(
              variant: !payload.grayscale && !payload.sepia && !payload.invert
                  ? UiButtonVariant.primary
                  : UiButtonVariant.outline,
              size: UiButtonSize.sm,
              onPressed: () {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          grayscale: false,
                          sepia: false,
                          invert: false,
                        ),
                      ),
                    );
              },
              child: const Text('Normal', style: TextStyle(fontSize: 11)),
            ),
            UiButton(
              variant: payload.grayscale
                  ? UiButtonVariant.primary
                  : UiButtonVariant.outline,
              size: UiButtonSize.sm,
              onPressed: () {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          grayscale: true,
                          sepia: false,
                          invert: false,
                        ),
                      ),
                    );
              },
              child: const Text('Grayscale', style: TextStyle(fontSize: 11)),
            ),
            UiButton(
              variant: payload.sepia
                  ? UiButtonVariant.primary
                  : UiButtonVariant.outline,
              size: UiButtonSize.sm,
              onPressed: () {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          sepia: true,
                          grayscale: false,
                          invert: false,
                        ),
                      ),
                    );
              },
              child: const Text('Sepia', style: TextStyle(fontSize: 11)),
            ),
            UiButton(
              variant: payload.invert
                  ? UiButtonVariant.primary
                  : UiButtonVariant.outline,
              size: UiButtonSize.sm,
              onPressed: () {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          invert: true,
                          grayscale: false,
                          sepia: false,
                        ),
                      ),
                    );
              },
              child: const Text('Invert', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),

        // Brightness
        Row(
          children: [
            SizedBox(
              width: 65,
              child: Text(
                'Brightness',
                style: TextStyle(color: tokens.textMuted, fontSize: 11),
              ),
            ),
            Expanded(
              child: _buildSlider(
                value: payload.brightness,
                min: -1.0,
                max: 1.0,
                onChanged: (val) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(brightness: val),
                        ),
                      );
                },
              ),
            ),
            Text(
              '${(payload.brightness * 100).toInt()}%',
              style: TextStyle(color: tokens.textMuted, fontSize: 10),
            ),
          ],
        ),

        // Contrast
        Row(
          children: [
            SizedBox(
              width: 65,
              child: Text(
                'Contrast',
                style: TextStyle(color: tokens.textMuted, fontSize: 11),
              ),
            ),
            Expanded(
              child: _buildSlider(
                value: payload.contrast,
                min: 0.0,
                max: 2.0,
                onChanged: (val) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(payload: payload.copyWith(contrast: val)),
                      );
                },
              ),
            ),
            Text(
              '${(payload.contrast * 100).toInt()}%',
              style: TextStyle(color: tokens.textMuted, fontSize: 10),
            ),
          ],
        ),

        // Blur
        Row(
          children: [
            SizedBox(
              width: 65,
              child: Text(
                'Blur',
                style: TextStyle(color: tokens.textMuted, fontSize: 11),
              ),
            ),
            Expanded(
              child: _buildSlider(
                value: payload.blur,
                min: 0.0,
                max: 20.0,
                onChanged: (val) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(payload: payload.copyWith(blur: val)),
                      );
                },
              ),
            ),
            Text(
              '${payload.blur.toInt()}px',
              style: TextStyle(color: tokens.textMuted, fontSize: 10),
            ),
          ],
        ),

        Text(
          'ADJUSTMENT STACK',
          style: TextStyle(
            color: tokens.textMuted,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs + AppSpacing.xxs,
          children: [
            for (final type in const [
              ImageAdjustmentType.saturation,
              ImageAdjustmentType.exposure,
              ImageAdjustmentType.temperature,
              ImageAdjustmentType.highlights,
              ImageAdjustmentType.shadows,
              ImageAdjustmentType.opacity,
            ])
              UiButton(
                variant: UiButtonVariant.outline,
                size: UiButtonSize.sm,
                onPressed: () => _addImageAdjustment(ref, node, payload, type),
                child: Text(
                  '+ ${_imageAdjustmentLabel(type)}',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
          ],
        ),
        if (payload.adjustments.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final adjustment in payload.adjustments)
            Builder(
              builder: (context) {
                final range = _imageAdjustmentRange(adjustment.type);
                return Padding(
                  padding: const EdgeInsets.only(
                    bottom: AppSpacing.xs + AppSpacing.xxs,
                  ),
                  child: Row(
                    children: [
                      UiIconButton(
                        icon: adjustment.enabled
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        tooltip: adjustment.enabled
                            ? 'Disable ${_imageAdjustmentLabel(adjustment.type)}'
                            : 'Enable ${_imageAdjustmentLabel(adjustment.type)}',
                        onPressed: () {
                          final next = payload.adjustments
                              .map(
                                (entry) => entry.id == adjustment.id
                                    ? entry.copyWith(enabled: !entry.enabled)
                                    : entry,
                              )
                              .toList(growable: false);
                          ref
                              .read(documentNodesProvider.notifier)
                              .updateNode(
                                node.copyWith(
                                  payload: payload.copyWith(adjustments: next),
                                ),
                              );
                        },
                      ),
                      Expanded(
                        child: _buildSlider(
                          value: adjustment.amount,
                          min: range.$1,
                          max: range.$2,
                          onChanged: (value) {
                            final next = payload.adjustments
                                .map(
                                  (entry) => entry.id == adjustment.id
                                      ? entry.copyWith(amount: value)
                                      : entry,
                                )
                                .toList(growable: false);
                            ref
                                .read(documentNodesProvider.notifier)
                                .updateNode(
                                  node.copyWith(
                                    payload: payload.copyWith(
                                      adjustments: next,
                                    ),
                                  ),
                                );
                          },
                        ),
                      ),
                      UiIconButton(
                        icon: Icons.delete_outline,
                        tooltip:
                            'Remove ${_imageAdjustmentLabel(adjustment.type)}',
                        onPressed: () {
                          final next = payload.adjustments
                              .where((entry) => entry.id != adjustment.id)
                              .toList(growable: false);
                          ref
                              .read(documentNodesProvider.notifier)
                              .updateNode(
                                node.copyWith(
                                  payload: payload.copyWith(adjustments: next),
                                ),
                              );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'BACKGROUND MASK',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: UiButton(
                variant: UiButtonVariant.outline,
                prefix: const Icon(Icons.auto_fix_high_outlined, size: 14),
                onPressed: () => _pickImageMask(context, ref, node, payload),
                child: Text(
                  payload.backgroundMask == null ? 'Add mask' : 'Replace mask',
                ),
              ),
            ),
            if (payload.backgroundMask != null) ...[
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              UiIconButton(
                icon: Icons.delete_outline,
                tooltip: 'Remove background mask',
                onPressed: () => ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(clearBackgroundMask: true),
                      ),
                    ),
              ),
            ],
          ],
        ),
        if (payload.backgroundMask != null) ...[
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          _InspectorSelect<ImageMaskMode>(
            label: 'Mask mode',
            value: payload.backgroundMask!.mode,
            options: const [
              (ImageMaskMode.alpha, 'Alpha'),
              (ImageMaskMode.luminance, 'Luminance'),
              (ImageMaskMode.invertedLuminance, 'Invert luminance'),
            ],
            onChanged: (mode) => ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(
                    payload: payload.copyWith(
                      backgroundMask: payload.backgroundMask!.copyWith(
                        mode: mode,
                      ),
                    ),
                  ),
                ),
          ),
          Row(
            children: [
              UiSwitch(
                value: payload.backgroundMask!.enabled,
                onChange: (enabled) => ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          backgroundMask: payload.backgroundMask!.copyWith(
                            enabled: enabled,
                          ),
                        ),
                      ),
                    ),
              ),
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              Text(
                'Enabled',
                style: TextStyle(color: tokens.textMuted, fontSize: 11),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _buildSlider(
                  value: payload.backgroundMask!.opacity,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (opacity) => ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(
                            backgroundMask: payload.backgroundMask!.copyWith(
                              opacity: opacity,
                            ),
                          ),
                        ),
                      ),
                ),
              ),
            ],
          ),
        ],

        Divider(color: tokens.panelBorder, height: AppSpacing.xl),

        // Drop Shadow
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'DROP SHADOW',
              style: TextStyle(
                color: tokens.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            UiSwitch(
              value: payload.hasShadow,
              onChange: (val) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(payload: payload.copyWith(hasShadow: val)),
                    );
              },
            ),
          ],
        ),
        if (payload.hasShadow) ...[
          Row(
            children: [
              _buildColorSquare(context, payload.shadowColor, (c) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(payload: payload.copyWith(shadowColor: c)),
                    );
              }),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _buildSlider(
                  value: payload.shadowBlur,
                  min: 0.0,
                  max: 50.0,
                  onChanged: (val) {
                    ref
                        .read(documentNodesProvider.notifier)
                        .updateNode(
                          node.copyWith(
                            payload: payload.copyWith(shadowBlur: val),
                          ),
                        );
                  },
                ),
              ),
              Text(
                '${payload.shadowBlur.toInt()}px',
                style: TextStyle(color: tokens.textMuted, fontSize: 10),
              ),
            ],
          ),
        ],

        Divider(color: tokens.panelBorder, height: AppSpacing.xl),

        // Caption Input
        Text(
          'CAPTION OVERLAY',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _InspectorTextField(
          key: ValueKey('image_caption_${node.id}'),
          value: payload.caption ?? '',
          hint: 'Add image caption...',
          onChanged: (val) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: payload.copyWith(caption: val)),
                );
          },
        ),
      ],
    );
  }

  Future<void> _openImageCropDialog(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
    ImagePayload payload,
  ) async {
    final operationGeneration = _beginArtifactOperation();
    final sync = ref.read(supabaseSyncServiceProvider);
    final accountId = sync.currentUserId;
    final bytes = await _cache().loadImageBytes(
      storagePath: payload.storagePath,
      localPath: payload.localPath,
      url: payload.url,
      imageArtifactReference: payload.imageArtifactReference,
    );

    if (!context.mounted ||
        _currentReplacementNode(
              ref: ref,
              capturedNode: node,
              generation: operationGeneration,
              accountId: accountId,
            ) ==
            null) {
      return;
    }
    if (bytes == null) {
      final hasSource =
          (payload.imageArtifactReference?.trim().isNotEmpty ?? false) ||
          (payload.storagePath?.trim().isNotEmpty ?? false) ||
          (payload.localPath?.trim().isNotEmpty ?? false) ||
          (payload.url?.trim().isNotEmpty ?? false);
      if (!hasSource) {
        await _replaceImage(context, ref, node, payload);
      } else {
        showUiToast(
          context,
          'Unable to load the image for editing. Try replacing it.',
          variant: UiToastVariant.error,
        );
      }
      return;
    }

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!context.mounted ||
        _currentReplacementNode(
              ref: ref,
              capturedNode: node,
              generation: operationGeneration,
              accountId: accountId,
            ) ==
            null) {
      frame.image.dispose();
      return;
    }
    final sourceSize = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    frame.image.dispose();
    if (!context.mounted ||
        _currentReplacementNode(
              ref: ref,
              capturedNode: node,
              generation: operationGeneration,
              accountId: accountId,
            ) ==
            null) {
      return;
    }
    final sourceRect = ImageCropSelection(
      x: payload.cropX,
      y: payload.cropY,
      width: payload.cropWidth,
      height: payload.cropHeight,
    ).toImageRect(sourceSize);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => ImageCropScreen(
          imageData: bytes,
          initialArea: sourceRect,
          onCroppedWithArea: (_, imageArea) {
            final current = _currentReplacementNode(
              ref: ref,
              capturedNode: node,
              generation: operationGeneration,
              accountId: accountId,
            );
            if (current == null || current.payload is! ImagePayload) return;
            final selection = ImageCropSelection.fromImageRect(
              imageArea,
              sourceSize,
            );
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  current.copyWith(
                    payload: (current.payload as ImagePayload).copyWith(
                      cropX: selection.x,
                      cropY: selection.y,
                      cropWidth: selection.width,
                      cropHeight: selection.height,
                    ),
                  ),
                );
          },
        ),
      ),
    );
  }

  Widget _buildFileCardControls(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
    FilePayload payload,
  ) {
    final tokens = context.appTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FILE ATTACHMENT',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),

        // File Details Card
        Container(
          key: const ValueKey('inspector-file-details'),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: tokens.panelElevated,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(
              color: tokens.panelBorder,
              width: AppBorder.thin,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color:
                          payload.customBadgeColor ?? const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      payload.fileExtension.toUpperCase().replaceAll('.', ''),
                      style: TextStyle(
                        color: payload.customBadgeColor ?? tokens.text,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          payload.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.text,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          '${payload.fileSizeText} • ${payload.fileExtension.toUpperCase()}',
                          style: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Action Buttons: Open & Replace
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: UiButton(
                        prefix: const Icon(Icons.open_in_new, size: 14),
                        onPressed: () => openFilePreview(
                          context,
                          payload,
                          fileArtifactStore: _fileStore(ref),
                          onAnnotationsChanged: (annotations) {
                            final current = _currentNode(ref, node.id);
                            if (current == null ||
                                current.payload is! FilePayload) {
                              return;
                            }
                            ref
                                .read(documentNodesProvider.notifier)
                                .updateNode(
                                  current.copyWith(
                                    payload: (current.payload as FilePayload)
                                        .copyWith(pdfAnnotations: annotations),
                                  ),
                                );
                          },
                        ),
                        child: const Text('Open / Preview'),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  UiButton(
                    variant: UiButtonVariant.outline,
                    prefix: const Icon(Icons.swap_horiz, size: 14),
                    onPressed: () async {
                      final operationGeneration = _beginArtifactOperation();
                      final sync = ref.read(supabaseSyncServiceProvider);
                      final accountId = sync.currentUserId;
                      final picker = AssetService(sync);
                      final result = await picker.pickAnyFile(
                        projectId: projectId,
                      );
                      if (result == null ||
                          _currentReplacementNode(
                                ref: ref,
                                capturedNode: node,
                                generation: operationGeneration,
                                accountId: accountId,
                              ) ==
                              null) {
                        return;
                      }
                      final artifactReference =
                          result.bytes == null || result.bytes!.isEmpty
                          ? null
                          : validFileArtifactReference(
                              (await _fileStore(ref).save(
                                result.bytes!,
                                fileName: result.name,
                              )).reference,
                            );
                      if (_currentReplacementNode(
                            ref: ref,
                            capturedNode: node,
                            generation: operationGeneration,
                            accountId: accountId,
                          ) ==
                          null) {
                        return;
                      }
                      final storagePath = _validatedImageStoragePath(
                        ref,
                        result.storagePath,
                      );
                      if (artifactReference == null && storagePath == null) {
                        if (context.mounted) {
                          showUiToast(
                            context,
                            'The selected file could not be stored.',
                            variant: UiToastVariant.error,
                          );
                        }
                        return;
                      }
                      final current = _currentReplacementNode(
                        ref: ref,
                        capturedNode: node,
                        generation: operationGeneration,
                        accountId: accountId,
                      );
                      if (current == null || current.payload is! FilePayload) {
                        return;
                      }
                      final currentPayload = current.payload as FilePayload;
                      final assetId = stableDocumentAssetId(
                        candidate: currentPayload.assetId,
                        manifest: ref.read(documentAssetsProvider),
                        nodes: ref.read(documentNodesProvider),
                        ownerNodeId: current.id,
                      );
                      _upsertDocumentAsset(
                        ref,
                        assetId: assetId,
                        kind: DocumentAssetKind.document,
                        name: result.name,
                        mimeType: result.detectedMimeType,
                        artifactReference: artifactReference,
                        storagePath: storagePath,
                        declaredSize: result.size,
                        bytes: result.bytes,
                      );
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateNode(
                            current.copyWith(
                              payload: currentPayload.copyWith(
                                fileName: result.name,
                                fileExtension: result.fileExt,
                                fileSizeText: result.formattedSize,
                                assetId: assetId,
                                artifactReference: artifactReference,
                                storagePath: storagePath,
                                clearArtifactReference:
                                    artifactReference == null,
                                clearStoragePath: storagePath == null,
                                clearLocalPath: true,
                                clearBase64Data: true,
                                clearRemoteUrl: true,
                                clearPdfAnnotations: true,
                              ),
                            ),
                          );
                    },
                    child: const Text('Replace'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Metadata Fields
        Text(
          'LABELS & TEXT',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _InspectorTextField(
          key: ValueKey('file_name_${node.id}'),
          value: payload.fileName,
          label: 'File Name / Title',
          onSubmitted: (val) {
            if (val.trim().isNotEmpty) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(fileName: val.trim()),
                    ),
                  );
            }
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        _InspectorTextField(
          key: ValueKey('file_description_${node.id}'),
          value: payload.description ?? '',
          label: 'Description / Note (Optional)',
          minLines: 2,
          maxLines: 3,
          onSubmitted: (val) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(
                    payload: payload.copyWith(description: val.trim()),
                  ),
                );
          },
        ),
        const SizedBox(height: AppSpacing.lg),

        // Styling Section
        Text(
          'CARD STYLING',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildColorPickerTile(
          context,
          'Badge Color',
          payload.customBadgeColor ?? const Color(0xFFEF4444),
          (c) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: payload.copyWith(customBadgeColor: c)),
                );
          },
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        _buildColorPickerTile(
          context,
          'Card Background',
          payload.backgroundColor,
          (c) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: payload.copyWith(backgroundColor: c)),
                );
          },
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        _buildColorPickerTile(context, 'Border Color', payload.borderColor, (
          c,
        ) {
          ref
              .read(documentNodesProvider.notifier)
              .updateNode(
                node.copyWith(payload: payload.copyWith(borderColor: c)),
              );
        }),
        const SizedBox(height: AppSpacing.md),

        // Border Width & Corner Radius
        Row(
          children: [
            Text(
              'Border Width',
              style: TextStyle(color: tokens.textMuted, fontSize: 11),
            ),
            const Spacer(),
            Text(
              '${payload.borderWidth.toStringAsFixed(1)}px',
              style: TextStyle(color: tokens.text, fontSize: 11),
            ),
          ],
        ),
        _buildSlider(
          value: payload.borderWidth,
          min: 0.0,
          max: 8.0,
          onChanged: (val) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: payload.copyWith(borderWidth: val)),
                );
          },
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        Row(
          children: [
            Text(
              'Corner Radius',
              style: TextStyle(color: tokens.textMuted, fontSize: 11),
            ),
            const Spacer(),
            Text(
              '${payload.cornerRadius.toInt()}px',
              style: TextStyle(color: tokens.text, fontSize: 11),
            ),
          ],
        ),
        _buildSlider(
          value: payload.cornerRadius,
          min: 0.0,
          max: 24.0,
          onChanged: (val) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: payload.copyWith(cornerRadius: val)),
                );
          },
        ),
        const SizedBox(height: AppSpacing.md),

        // Shadow Toggle
        Container(
          key: const ValueKey('inspector-shadow-toggle'),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + AppSpacing.xxs,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: tokens.panelElevated,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: tokens.panelBorder,
              width: AppBorder.thin,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Drop Shadow',
                style: TextStyle(color: tokens.text, fontSize: 11),
              ),
              UiSwitch(
                value: payload.hasShadow,
                onChange: (val) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(hasShadow: val),
                        ),
                      );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFrameControls(
    BuildContext context,
    WidgetRef ref,
    CanvasNode node,
    FramePayload payload,
  ) {
    final tokens = context.appTokens;
    final activePreset = FramePresetsCatalog.findById(payload.presetId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Presets & Orientation Header
        Text(
          'FRAME PRESET & SIZE',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: UiButton(
                  variant: UiButtonVariant.outline,
                  size: UiButtonSize.sm,
                  prefix: const Icon(Icons.devices_outlined, size: 14),
                  onPressed: () {
                    showUiDialog(
                      context: context,
                      builder: (ctx) => FramePresetDialog(
                        currentPreset: activePreset,
                        isLandscape: payload.isLandscape,
                        onSelectPreset: (preset, isLandscape) {
                          final newW = preset.getWidth(isLandscape);
                          final newH = preset.getHeight(isLandscape);
                          ref
                              .read(documentNodesProvider.notifier)
                              .updateNode(
                                node.copyWith(
                                  width: newW,
                                  height: newH,
                                  payload: payload.copyWith(
                                    name: preset.name,
                                    presetId: preset.id,
                                    isLandscape: isLandscape,
                                  ),
                                ),
                              );
                        },
                      ),
                    );
                  },
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      activePreset != null
                          ? activePreset.name
                          : 'Choose Preset...',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
            UiIconButton(
              icon: payload.isLandscape
                  ? Icons.stay_current_landscape
                  : Icons.stay_current_portrait,
              tooltip:
                  'Swap Orientation (${payload.isLandscape ? "Landscape" : "Portrait"})',
              onPressed: () {
                final newLandscape = !payload.isLandscape;
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        width: node.height,
                        height: node.width,
                        payload: payload.copyWith(isLandscape: newLandscape),
                      ),
                    );
              },
            ),
          ],
        ),
        Divider(color: tokens.panelBorder, height: AppSpacing.pageWide),

        // Surface & Clip Styling
        Text(
          'SURFACE & APPEARANCE',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildColorPickerTile(context, 'Background Fill', payload.background, (
          newColor,
        ) {
          ref
              .read(documentNodesProvider.notifier)
              .updateNode(
                node.copyWith(payload: payload.copyWith(background: newColor)),
              );
        }),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        Row(
          children: [
            Expanded(
              child: _buildColorPickerTile(
                context,
                'Gradient End',
                payload.backgroundGradientEnd ?? payload.background,
                (newColor) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(
                            backgroundGradientEnd: newColor,
                          ),
                        ),
                      );
                },
              ),
            ),
            if (payload.backgroundGradientEnd != null)
              UiIconButton(
                icon: Icons.clear,
                tooltip: 'Remove Gradient',
                variant: UiButtonVariant.destructive,
                size: UiButtonSize.sm,
                onPressed: () {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(clearGradient: true),
                        ),
                      );
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildNumberInput('Corner Radius', payload.cornerRadius, (val) {
          ref
              .read(documentNodesProvider.notifier)
              .updateNode(
                node.copyWith(
                  payload: payload.copyWith(
                    cornerRadius: val.clamp(0.0, 500.0),
                  ),
                ),
              );
        }),
        const SizedBox(height: AppSpacing.sm),
        _buildColorPickerTile(context, 'Border Color', payload.borderColor, (
          newColor,
        ) {
          ref
              .read(documentNodesProvider.notifier)
              .updateNode(
                node.copyWith(payload: payload.copyWith(borderColor: newColor)),
              );
        }),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _buildNumberInput('Border Width', payload.borderWidth, (
                val,
              ) {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          borderWidth: val.clamp(0.0, 20.0),
                        ),
                      ),
                    );
              }),
            ),
            const SizedBox(width: AppSpacing.sm),
            UiButton(
              variant: payload.isDashedBorder
                  ? UiButtonVariant.primary
                  : UiButtonVariant.outline,
              size: UiButtonSize.sm,
              onPressed: () {
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        payload: payload.copyWith(
                          isDashedBorder: !payload.isDashedBorder,
                        ),
                      ),
                    );
              },
              child: const Text('Dashed', style: TextStyle(fontSize: 10)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              UiCheckbox(
                value: payload.clipContent,
                onChange: (val) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(clipContent: val),
                        ),
                      );
                },
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Clip Content',
                style: TextStyle(color: tokens.text, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              UiCheckbox(
                value: payload.hasShadow,
                onChange: (val) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        node.copyWith(
                          payload: payload.copyWith(hasShadow: val),
                        ),
                      );
                },
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Drop Shadow',
                style: TextStyle(color: tokens.text, fontSize: 12),
              ),
            ],
          ),
        ),
        Divider(color: tokens.panelBorder, height: AppSpacing.pageWide),

        // Auto-Layout Section
        Text(
          'AUTO-LAYOUT ENGINE',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            for (final option in const [
              (AutoLayoutDirection.none, 'Off', Icons.close),
              (
                AutoLayoutDirection.horizontal,
                'Row',
                Icons.view_column_outlined,
              ),
              (AutoLayoutDirection.vertical, 'Col', Icons.table_rows_outlined),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: UiButton(
                    variant: payload.layoutDirection == option.$1
                        ? UiButtonVariant.primary
                        : UiButtonVariant.outline,
                    size: UiButtonSize.sm,
                    onPressed: () {
                      ref
                          .read(documentNodesProvider.notifier)
                          .updateFrameLayout(
                            node.id,
                            payload.copyWith(layoutDirection: option.$1),
                          );
                    },
                    prefix: Icon(option.$3, size: 14),
                    child: Text(option.$2),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'LAYOUT PRESET',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(
          key: ValueKey('inspector-frame-layout-preset-gap'),
          height: AppSpacing.xs + AppSpacing.xxs,
        ),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final preset in CanvasLayoutPreset.values)
              UiButton(
                variant: UiButtonVariant.outline,
                size: UiButtonSize.sm,
                onPressed: () => ref
                    .read(documentNodesProvider.notifier)
                    .applyLayoutPreset(node.id, preset),
                child: Text(
                  preset.name[0].toUpperCase() + preset.name.substring(1),
                ),
              ),
          ],
        ),
        if (payload.layoutDirection != AutoLayoutDirection.none) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildNumberInput('Item Spacing (Gap)', payload.itemSpacing, (val) {
            ref
                .read(documentNodesProvider.notifier)
                .updateFrameLayout(
                  node.id,
                  payload.copyWith(itemSpacing: val.clamp(0.0, 200.0)),
                );
          }),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'SPACING PRESET',
            style: TextStyle(
              color: tokens.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(
            key: ValueKey('inspector-frame-spacing-preset-gap'),
            height: AppSpacing.xs + AppSpacing.xxs,
          ),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final preset in CanvasSpacingPreset.values)
                UiButton(
                  key: ValueKey('spacing-preset-${node.id}-${preset.name}'),
                  variant: (payload.itemSpacing - preset.value).abs() < 0.01
                      ? UiButtonVariant.primary
                      : UiButtonVariant.outline,
                  size: UiButtonSize.sm,
                  onPressed: () => ref
                      .read(documentNodesProvider.notifier)
                      .updateFrameLayout(
                        node.id,
                        payload.copyWith(itemSpacing: preset.value),
                      ),
                  child: Text(preset.label),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _buildNumberInput('Pad X', payload.paddingLeft, (val) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateFrameLayout(
                        node.id,
                        payload.copyWith(
                          paddingLeft: val.clamp(0.0, 200.0),
                          paddingRight: val.clamp(0.0, 200.0),
                        ),
                      );
                }),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _buildNumberInput('Pad Y', payload.paddingTop, (val) {
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateFrameLayout(
                        node.id,
                        payload.copyWith(
                          paddingTop: val.clamp(0.0, 200.0),
                          paddingBottom: val.clamp(0.0, 200.0),
                        ),
                      );
                }),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _InspectorSelect<AutoLayoutAlign>(
            label: 'Align',
            value: payload.layoutAlign,
            options: [
              for (final option in AutoLayoutAlign.values)
                (option, option.name.toUpperCase()),
            ],
            onChanged: (align) {
              ref
                  .read(documentNodesProvider.notifier)
                  .updateFrameLayout(
                    node.id,
                    payload.copyWith(layoutAlign: align),
                  );
            },
          ),
        ],
        Divider(color: tokens.panelBorder, height: AppSpacing.pageWide),

        // Quick Export Section
        Text(
          'QUICK FRAME EXPORT',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: UiButton(
                variant: UiButtonVariant.outline,
                prefix: const Icon(Icons.image_outlined, size: 14),
                onPressed: () => _exportSingleFrame(context, ref, node, 'png'),
                child: const Text('PNG'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
            Expanded(
              child: UiButton(
                variant: UiButtonVariant.outline,
                prefix: const Icon(Icons.code, size: 14),
                onPressed: () => _exportSingleFrame(context, ref, node, 'svg'),
                child: const Text('SVG'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
            Expanded(
              child: UiButton(
                variant: UiButtonVariant.outline,
                prefix: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                onPressed: () => _exportSingleFrame(context, ref, node, 'pdf'),
                child: const Text('PDF'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _exportSingleFrame(
    BuildContext context,
    WidgetRef ref,
    CanvasNode frameNode,
    String format,
  ) {
    final allNodes = ref.read(documentNodesProvider);
    final frameRect = Rect.fromLTWH(
      frameNode.x,
      frameNode.y,
      frameNode.width,
      frameNode.height,
    );
    final containedNodes = allNodes.where((n) {
      if (!n.visible) return false;
      if (n.id == frameNode.id) return true;
      final center = Offset(n.x + n.width / 2, n.y + n.height / 2);
      return frameRect.contains(center);
    }).toList();

    showUiToast(
      context,
      'Exported ${frameNode.name ?? "Frame"} as ${format.toUpperCase()} (${containedNodes.length} layers).',
      variant: UiToastVariant.success,
    );
  }

  Widget _buildColorPickerDialog({
    required BuildContext dialogContext,
    required String dialogLabel,
    required String title,
    required Color currentColor,
    required ValueChanged<Color> onColorChanged,
  }) => ColorPickerDialog(
    dialogContext: dialogContext,
    dialogLabel: dialogLabel,
    title: title,
    currentColor: currentColor,
    onColorChanged: onColorChanged,
  );

  Widget _buildColorSquare(
    BuildContext context,
    Color currentColor,
    ValueChanged<Color> onColorChanged,
  ) {
    final tokens = context.appTokens;
    return UiButton(
      semanticsLabel: 'Pick color',
      variant: UiButtonVariant.ghost,
      size: UiButtonSize.sm,
      iconOnly: true,
      onPressed: () {
        showUiDialog<void>(
          context: context,
          builder: (dialogContext) => _buildColorPickerDialog(
            dialogContext: dialogContext,
            dialogLabel: 'Pick color',
            title: 'Pick Color',
            currentColor: currentColor,
            onColorChanged: onColorChanged,
          ),
        );
      },
      child: Container(
        width: 28,
        height: 20,
        decoration: BoxDecoration(
          color: currentColor,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: tokens.panelBorder, width: 1.2),
        ),
      ),
    );
  }

  Widget _buildColorPickerTile(
    BuildContext context,
    String label,
    Color currentColor,
    ValueChanged<Color> onColorChanged,
  ) {
    final tokens = context.appTokens;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: tokens.text, fontSize: 12)),
        UiButton(
          semanticsLabel: 'Pick $label',
          variant: UiButtonVariant.ghost,
          size: UiButtonSize.sm,
          iconOnly: true,
          onPressed: () {
            showUiDialog<void>(
              context: context,
              builder: (dialogContext) => _buildColorPickerDialog(
                dialogContext: dialogContext,
                dialogLabel: 'Pick $label',
                title: label,
                currentColor: currentColor,
                onColorChanged: onColorChanged,
              ),
            );
          },
          child: Container(
            width: 32,
            height: 22,
            decoration: BoxDecoration(
              color: currentColor,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: tokens.panelBorder, width: 1.2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectorHeader(
    BuildContext context,
    WidgetRef ref,
    CanvasEdge edge,
  ) {
    final tokens = context.appTokens;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(Icons.hub_outlined, color: tokens.accent, size: 16),
            const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
            Text(
              'SMART CONNECTOR',
              style: TextStyle(
                color: tokens.accent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        UiIconButton(
          icon: Icons.delete_outline,
          variant: UiButtonVariant.destructive,
          size: UiButtonSize.sm,
          tooltip: 'Delete connector',
          onPressed: () {
            ref.read(documentNodesProvider.notifier).deleteEdges([edge.id]);
            ref.read(selectionProvider.notifier).clear();
          },
        ),
      ],
    );
  }

  Widget _buildConnectorControls(
    BuildContext context,
    WidgetRef ref,
    CanvasEdge edge,
  ) {
    final tokens = context.appTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ROUTING & ANCHORS',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _InspectorSelect<ConnectorRouting>(
          label: 'Routing',
          value: edge.routing,
          options: const [
            (ConnectorRouting.orthogonal, 'Elbow ┌─┘'),
            (ConnectorRouting.curved, 'Curved ~~~'),
            (ConnectorRouting.straight, 'Straight ───'),
          ],
          onChanged: (routing) {
            ref
                .read(documentEdgesProvider.notifier)
                .updateEdge(edge.copyWith(routing: routing));
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _InspectorSelect<AnchorPosition>(
                label: 'Source Anchor',
                value: edge.sourceAnchor,
                options: [
                  for (final option in AnchorPosition.values)
                    (option, option.name.toUpperCase()),
                ],
                onChanged: (anchor) {
                  ref
                      .read(documentEdgesProvider.notifier)
                      .updateEdge(edge.copyWith(sourceAnchor: anchor));
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _InspectorSelect<AnchorPosition>(
                label: 'Target Anchor',
                value: edge.targetAnchor,
                options: [
                  for (final option in AnchorPosition.values)
                    (option, option.name.toUpperCase()),
                ],
                onChanged: (anchor) {
                  ref
                      .read(documentEdgesProvider.notifier)
                      .updateEdge(edge.copyWith(targetAnchor: anchor));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'ENDPOINTS & CAPS',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _InspectorSelect<LineMarker>(
          label: 'Start Marker',
          value: edge.startMarker,
          options: const [
            (LineMarker.none, 'None ───'),
            (LineMarker.arrow, 'Arrow 🡐'),
            (LineMarker.circle, 'Circle ●'),
            (LineMarker.diamond, 'Diamond ◆'),
          ],
          onChanged: (marker) {
            ref
                .read(documentEdgesProvider.notifier)
                .updateEdge(edge.copyWith(startMarker: marker));
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        _InspectorSelect<LineMarker>(
          label: 'End Marker',
          value: edge.endMarker,
          options: const [
            (LineMarker.none, 'None ───'),
            (LineMarker.arrow, 'Arrow 🡒'),
            (LineMarker.circle, 'Circle ●'),
            (LineMarker.diamond, 'Diamond ◆'),
          ],
          onChanged: (marker) {
            ref
                .read(documentEdgesProvider.notifier)
                .updateEdge(edge.copyWith(endMarker: marker));
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'STROKE & STYLING',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildColorPickerTile(context, 'Line Color', edge.strokeColor, (c) {
          ref
              .read(documentEdgesProvider.notifier)
              .updateEdge(edge.copyWith(strokeColor: c));
        }),
        const SizedBox(height: AppSpacing.sm),
        _buildNumberInput('Stroke Width', edge.strokeWidth, (val) {
          ref
              .read(documentEdgesProvider.notifier)
              .updateEdge(edge.copyWith(strokeWidth: val.clamp(0.5, 30.0)));
        }),
        const SizedBox(height: AppSpacing.sm),
        _InspectorSelect<StrokeStyle>(
          label: 'Stroke Style',
          value: edge.strokeStyle,
          options: const [
            (StrokeStyle.solid, 'Solid ───'),
            (StrokeStyle.dashed, 'Dashed ╌╌╌'),
            (StrokeStyle.dotted, 'Dotted ···'),
          ],
          onChanged: (style) {
            ref
                .read(documentEdgesProvider.notifier)
                .updateEdge(edge.copyWith(strokeStyle: style));
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'LABEL & BADGE',
          style: TextStyle(
            color: tokens.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _InspectorTextField(
          key: ValueKey('edge_label_${edge.id}'),
          value: edge.label ?? '',
          hint: 'e.g. Yes / No / HTTP...',
          onChanged: (val) {
            ref
                .read(documentEdgesProvider.notifier)
                .updateEdge(edge.copyWith(label: val.isEmpty ? null : val));
          },
        ),
      ],
    );
  }

  Widget _buildBranchInput(
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) => _InspectorTextField(value: value, label: label, onChanged: onChanged);
}
