import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/theme_mode_provider.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/data/remote/backend_config.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/domain/models/collaboration.dart';
import 'package:varian/domain/models/component_payload.dart';
import 'package:varian/domain/models/design_tokens.dart';
import 'package:varian/domain/models/connector_edge.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/document_asset.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/domain/models/drawing_payload.dart';
import 'package:varian/domain/models/ai_job.dart';
import 'package:varian/domain/models/model3d_payload.dart';
import 'package:varian/domain/models/model3d_studio.dart';
import 'package:varian/domain/models/media_timeline.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/domain/models/rich_text.dart';
import 'package:varian/domain/models/vector_path_payload.dart';
import 'package:varian/domain/models/viewport.dart' as canvas_model;
import 'package:varian/domain/models/workspace_governance.dart';
import 'package:varian/features/ai/data/image_artifact_store.dart';
import 'package:varian/domain/models/durable_asset_reference.dart';
import 'package:varian/features/ai/data/video_artifact_store.dart';
import 'package:varian/features/ai/data/video_download_service.dart';
import 'package:varian/features/ai/data/semantic_index_sources.dart';
import 'package:varian/features/ai/presentation/ai_panel.dart';
import 'package:varian/features/ai/state/ai_provider.dart';
import 'package:varian/features/ai/state/semantic_index_provider.dart';
import 'package:varian/features/assets/data/asset_service.dart';
import 'package:varian/features/assets/data/file_artifact_store.dart';
import 'package:varian/features/assets/data/asset_library_node_factory.dart';
import 'package:varian/features/assets/data/asset_library_materializer.dart';
import 'package:varian/features/assets/domain/asset_library.dart';
import 'package:varian/features/assets/presentation/asset_library_dialog.dart';
import 'package:varian/features/assets/state/asset_library_provider.dart';
import 'package:varian/features/canvas/data/canvas_file_source.dart';
import 'package:varian/features/canvas/domain/canvas_navigation.dart';
import 'package:varian/features/canvas/domain/canvas_precision.dart';
import 'package:varian/features/canvas/domain/document_asset_registry.dart';
import 'package:varian/features/canvas/domain/canvas_selection.dart';
import 'package:varian/features/canvas/domain/input_behavior_matrix.dart';
import 'package:varian/features/canvas/domain/rich_text_editing.dart';
import 'package:varian/features/canvas/domain/vector_path_editing.dart';
import 'package:varian/features/canvas/presentation/widgets/table_matrix_editor_modal.dart';
import 'package:varian/features/canvas/presentation/widgets/todo_list_editor_modal.dart';
import 'package:varian/features/charts/data/chart_canvas_interaction.dart';
import 'package:varian/features/charts/data/chart_database_adapter.dart';
import 'package:varian/features/charts/presentation/chart_data_editor_dialog.dart';
import 'package:varian/features/charts/presentation/chart_node_widget.dart';
import 'package:varian/features/canvas/presentation/widgets/column_card_editor_modal.dart';
import 'package:varian/features/canvas/presentation/widgets/desktop_document_tabs.dart';
import 'package:varian/features/canvas/presentation/widgets/nested_board_screen.dart';
import 'package:varian/features/canvas/presentation/widgets/component_editor_modal.dart';
import 'package:varian/features/canvas/presentation/widgets/design_token_manager_dialog.dart';
import 'package:varian/features/components/domain/component_library.dart';
import 'package:varian/features/components/presentation/component_library_dialog.dart';
import 'package:varian/features/canvas/presentation/painters/canvas_painter.dart';
import 'package:varian/features/canvas/presentation/painters/grid_painter.dart';
import 'package:varian/features/canvas/presentation/painters/node_painter.dart';
import 'package:varian/features/canvas/presentation/dialogs/frame_preset_dialog.dart';
import 'package:varian/features/canvas/presentation/dialogs/variant_browser_dialog.dart';
import 'package:varian/features/canvas/state/autosave_controller.dart';
import 'package:varian/data/local/durable/project_session.dart';
import 'package:varian/features/canvas/state/canvas_panel_preferences_provider.dart';
import 'package:varian/features/canvas/state/canvas_precision_provider.dart';
import 'package:varian/features/canvas/state/canvas_selection_provider.dart';
import 'package:varian/features/canvas/state/document_edges_provider.dart';
import 'package:varian/features/canvas/state/document_nodes_provider.dart';
import 'package:varian/features/canvas/state/document_assets_provider.dart';
import 'package:varian/features/canvas/state/design_token_provider.dart';
import 'package:varian/features/canvas/utils/canvas_spatial_index.dart';
import 'package:varian/features/canvas/state/selection_provider.dart';
import 'package:varian/features/canvas/state/tool_provider.dart';
import 'package:varian/features/canvas/state/viewport_provider.dart';
import 'package:varian/features/canvas/utils/brush_eraser_engine.dart';
import 'package:varian/features/canvas/utils/align_engine.dart';
import 'package:varian/features/canvas/utils/connector_router.dart';
import 'package:varian/features/canvas/utils/hit_tester.dart';
import 'package:varian/features/canvas/utils/snap_engine.dart';
import 'package:varian/features/collaboration/presentation/widgets/collaborator_overlay.dart';
import 'package:varian/features/collaboration/presentation/widgets/collaborators_panel.dart';
import 'package:varian/features/collaboration/presentation/widgets/comment_ui.dart';
import 'package:varian/features/collaboration/presentation/widgets/comment_notifications_ui.dart';
import 'package:varian/features/collaboration/domain/comment_notifications.dart';
import 'package:varian/features/collaboration/state/collaboration_provider.dart';
import 'package:varian/features/collaboration/state/collaboration_session_provider.dart';
import 'package:varian/features/capture/data/capture_canvas_materializer.dart';
import 'package:varian/features/capture/domain/capture_canvas_handoff.dart';
import 'package:varian/features/capture/domain/capture_item.dart';
import 'package:varian/features/capture/state/capture_provider.dart';
import 'package:varian/features/meeting/domain/meeting_models.dart';
import 'package:varian/features/meeting/state/meeting_controller.dart';
import 'package:varian/features/drawing_paper/domain/services/drawing_paper_persistence.dart';
import 'package:varian/features/drawing_paper/domain/services/drawing_paper_renderer.dart';
import 'package:varian/features/drawing_paper/presentation/dialogs/paper_template_dialog.dart';
import 'package:varian/features/drawing_paper/presentation/studio/drawing_studio_screen.dart';
import 'package:varian/features/canvas/presentation/widgets/sketch_card_editor_dialog.dart';
import 'package:varian/features/canvas/presentation/widgets/annotation_pin_editor_dialog.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/file_preview_router.dart';
import 'package:varian/features/canvas/presentation/widgets/file_preview/transient_file_source_resolver.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_panel_controller.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_editor_services.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_minimap.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_precision_dialog.dart';
import 'package:varian/features/mermaid/domain/mermaid_conversion.dart';
import 'package:varian/features/mermaid/presentation/mermaid_editor_dialog.dart';
import 'package:varian/features/mermaid/presentation/mermaid_node_preview.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';
import 'package:varian/features/canvas/utils/minimap_geometry.dart';
import 'package:varian/features/document/presentation/document_editor_screen.dart';
import 'package:varian/features/diagrams/domain/diagram_shape_catalog.dart';
import 'package:varian/features/export/data/export_file_saver.dart';
import 'package:varian/features/export/domain/portable_asset_collector.dart';
import 'package:varian/features/export/export_presets.dart';
import 'package:varian/features/export/export_queue.dart';
import 'package:varian/features/export/export_service.dart';
import 'package:varian/features/export/presentation/canvas_export_surface.dart';
import 'package:varian/features/export/presentation/export_center_dialog.dart';
import 'package:varian/features/export/presentation/export_queue_dialog.dart';
import 'package:varian/features/inspect/domain/inspect_handoff.dart';
import 'package:varian/features/governance/domain/plugin_registry.dart';
import 'package:varian/features/governance/domain/operability.dart';
import 'package:varian/features/governance/domain/remote_operability.dart';
import 'package:varian/features/governance/domain/usage_billing.dart';
import 'package:varian/features/inspect/presentation/inspect_handoff_dialog.dart';
import 'package:varian/features/history/history_provider.dart';
import 'package:varian/features/history/snapshot_manager.dart';
import 'package:varian/features/history/presentation/version_diff_dialog.dart';
import 'package:varian/features/home/presentation/widgets/backend_settings_dialog.dart';
import 'package:varian/features/home/presentation/widgets/collaboration_profile_dialog.dart';
import 'package:varian/features/home/state/home_provider.dart';
import 'package:varian/features/import/import_merge_planner.dart';
import 'package:varian/features/import/import_publication_transaction.dart';
import 'package:varian/features/import/import_service.dart';
import 'package:varian/features/import/presentation/import_dialog.dart';
import 'package:varian/features/canvas/commands/editor_commands.dart';
import 'package:varian/features/media/audio_player_screen.dart';
import 'package:varian/features/media/embed_webview_screen.dart';
import 'package:varian/features/media/embed_url_service.dart';
import 'package:varian/features/canvas/utils/canvas_image_cache.dart';
import 'package:varian/features/canvas/utils/canvas_storage_resolver_provider.dart';
import 'package:varian/features/media/image_crop_screen.dart';
import 'package:varian/features/media/map_viewer_screen.dart';
import 'package:varian/features/media/map_location_preview.dart';
import 'package:varian/features/media/video_player_screen.dart';
import 'package:varian/features/model3d/data/model3d_artifact_store.dart';
import 'package:varian/features/model3d/data/model3d_import_service.dart';
import 'package:varian/features/model3d/data/model3d_validation.dart';
import 'package:varian/features/model3d/presentation/model3d_node_widget.dart';
import 'package:varian/features/media/data/media_artifact_store.dart';
import 'package:varian/data/artifacts/artifact_store_bundle.dart';
import 'package:varian/features/media/data/transient_media_source_resolver.dart';
import 'package:varian/features/media/data/transient_media_source_types.dart';
import 'package:varian/features/media/inline_video_card_widget.dart';
import 'package:varian/features/media/inline_audio_card_widget.dart';
import 'package:varian/features/link_card/domain/link_url_policy.dart';
import 'package:varian/features/link_card/presentation/link_card_widget.dart';
import 'package:varian/features/link_card/state/link_preview_controller.dart';
import 'package:varian/features/presentation/presentation_screen.dart';
import 'package:varian/features/presentation/presentation_remote_dialogs.dart';
import 'package:varian/features/publishing/domain/published_snapshot.dart';
import 'package:varian/features/publishing/presentation/published_snapshot_dialog.dart';
import 'package:varian/features/governance/presentation/workspace_governance_dialog.dart';
import 'package:varian/features/review/presentation/review_workflow_dialog.dart';
import 'package:varian/features/search/presentation/search_dialog.dart';
import 'package:varian/features/canvas/domain/command_palette.dart';
import 'package:varian/features/canvas/presentation/widgets/canvas_command_palette.dart';
import 'package:varian/features/templates/data/diagram_templates.dart';
import 'package:varian/features/templates/domain/project_template.dart';
import 'package:varian/features/templates/presentation/project_template_save_dialog.dart';
import 'package:varian/features/canvas/presentation/widgets/inspector_panel.dart';
import 'package:varian/features/canvas/presentation/widgets/layers_panel.dart';
import 'package:varian/features/canvas/presentation/widgets/panel_visibility_toggle.dart';
import 'package:varian/features/canvas/presentation/widgets/toolbar.dart';
import 'package:varian/features/canvas/presentation/widgets/viewport_bookmarks_dialog.dart';
import 'package:varian/features/canvas/presentation/widgets/vector_path_tools_dialog.dart';

enum _DocumentRestoreMode { inPlace, copy }

/// Shared canvas editor implementation for root and nested documents.
///
/// Hosts provide [CanvasEditorServices] to compose project-level capabilities;
/// document editing, tools, gestures, and editor panels stay in this surface.
class CanvasEditorSurface extends ConsumerStatefulWidget {
  final String projectId;
  final String projectName;
  final CanvasDocument? initialDocument;
  final List<CanvasComment> initialComments;
  final bool readOnly;
  final CollaborationRole? collaborationRole;
  final bool captureTargetIsCollaborationRoom;
  final CaptureCanvasHandoff? captureHandoff;
  final CanvasEditorServices services;
  final CanvasEditorPanelController? panelController;
  final Future<bool> Function(String newName)? onProjectNameChanged;
  final Future<void> Function(BuildContext context)? onCreateProject;
  final Future<void> Function(BuildContext context)? onOpenProjectLibrary;
  final Future<void> Function(BuildContext context, OpenDocumentTab tab)?
  onSelectDocument;
  final Future<void> Function(
    BuildContext context,
    OpenDocumentTab tab,
    OpenDocumentTab? replacement,
    bool active,
  )?
  onCloseDocument;

  const CanvasEditorSurface({
    super.key,
    required this.projectId,
    this.projectName = 'Untitled Project',
    this.initialDocument,
    this.initialComments = const [],
    this.readOnly = false,
    this.collaborationRole,
    this.captureTargetIsCollaborationRoom = false,
    this.captureHandoff,
    this.services = CanvasEditorServices.embedded,
    this.panelController,
    this.onProjectNameChanged,
    this.onCreateProject,
    this.onOpenProjectLibrary,
    this.onSelectDocument,
    this.onCloseDocument,
  });

  @override
  ConsumerState<CanvasEditorSurface> createState() =>
      _CanvasEditorSurfaceState();
}

class _CanvasEditorSurfaceState extends ConsumerState<CanvasEditorSurface> {
  final GlobalKey _canvasKey = GlobalKey();
  final GlobalKey _repaintBoundaryKey = GlobalKey();
  CollaborationSessionController? _collaborationSession;
  final String _localUserId = const Uuid().v4();
  Offset? _dragStart;
  Offset? _pointerDownLocalPosition;
  Offset _lastTapLocalPosition = Offset.zero;
  Offset? _lastSelectionWorldPosition;
  int _selectionCycleIndex = 0;
  String? _pointerDownSelectionNodeId;
  Rect? _selectionMarquee;
  Rect? _dragOriginBounds;
  Offset _dragAccum = Offset.zero;
  bool _altPressed = false;
  List<SpacingMeasurement> _activeMeasurements = [];
  List<CanvasNode> _clipboardNodes = [];
  List<CanvasEdge> _clipboardEdges = [];
  int _pasteCount = 1;
  List<SnapGuide> _activeSnapGuides = [];
  List<Offset> _activeBrushStroke = [];
  Offset? _shapeDragStart;
  Rect? _creationPreviewRect;
  (Offset, Offset)? _creationPreviewLine;
  String? _connectorSourceNodeId;
  String? _connectorEditEdgeId;
  ConnectorControlHit? _connectorEditControl;
  CanvasEdge? _connectorEditOriginal;
  CanvasEdge? _connectorEditPreview;
  String? _connectorSnapNodeId;
  Offset? _connectorSnapPoint;
  Offset? _connectorEditLastWorldPosition;
  Offset? _mouseWorldPos;
  String? _drawingOnSketchCardId;
  List<BezierPoint> _activePenPoints = [];
  bool _isDraggingPenHandle = false;
  bool _isDraggingNodes = false;
  String? _resizingNodeId;
  ResizeHandle? _activeResizeHandle;
  double? _rotationStartPointerAngle;
  double? _rotationStartNodeRotation;
  int? _activeDrawingPointIndex;
  int? _activeVectorPointIndex;
  Rect? _initialNodeBounds;
  Offset? _fixedLineAnchor;
  late CanvasEditorPanelController _panelController;
  bool _ownsPanelController = false;
  final FocusNode _aiPromptFocusNode = FocusNode();
  String _documentTitle = '';
  bool _editingDocumentTitle = false;
  final TextEditingController _documentTitleController =
      TextEditingController();
  final FocusNode _documentTitleFocusNode = FocusNode();
  String? _editingNodeId;
  CanvasNode? _inlineEditOriginalNode;
  bool _editingFrameLabel = false;
  final TextEditingController _editController = TextEditingController();
  final FocusNode _editFocusNode = FocusNode();
  Timer? _chartTapTimer;
  String? _chartPointerNodeId;
  Offset? _chartPointerDownPosition;
  bool _chartPointerMoved = false;
  bool _documentTitleCommitInProgress = false;
  CanvasSpatialIndex? _canvasSpatialIndex;
  List<CanvasNode>? _indexedNodes;
  String? _feedbackNodeId;
  String? _focusedCommentId;
  bool _showUnresolvedCommentsOnly = false;
  bool _commentFilterPreferenceLoaded = false;
  AutosaveController? _autosaveController;
  final Set<String> _ownedVideoObjectUrls = {};
  late final ImageArtifactStore _imageArtifactStore;
  late final FileArtifactStore _fileArtifactStore;
  late final MediaArtifactStore _mediaArtifactStore;
  late final VideoArtifactStore _videoArtifactStore;
  late final Model3DArtifactStore _model3DArtifactStore;
  late final AssetLibraryMaterializer _assetLibraryMaterializer;
  final Map<String, int> _model3DResetCommands = {};
  int _artifactOperationGeneration = 0;
  int _canvasMutationGeneration = 0;
  int? _assetLibraryMaterializerGeneration;

  bool _isArtifactOperationCurrent({
    required int generation,
    required String projectId,
    required String? accountId,
  }) {
    if (!mounted || generation != _artifactOperationGeneration) return false;
    if (widget.projectId != projectId) return false;
    return ref.read(supabaseSyncServiceProvider).currentUserId == accountId;
  }

  String? _validatedImageStoragePath(String? rawPath) {
    final value = rawPath?.trim();
    if (value == null || value.isEmpty || value != rawPath) return null;
    final resolver = ref.read(canvasStorageResolverProvider(widget.projectId));
    return resolver
        .parseReference(path: value, projectId: widget.projectId)
        ?.path;
  }

  bool _isImageLibraryKind(AssetLibraryItemKind kind) => switch (kind) {
    AssetLibraryItemKind.image ||
    AssetLibraryItemKind.graphic ||
    AssetLibraryItemKind.icon ||
    AssetLibraryItemKind.illustration => true,
    _ => false,
  };

  bool _isBundledShapeItem(AssetLibraryItem item) {
    if (item.source != AssetLibrarySource.bundled ||
        item.kind != AssetLibraryItemKind.graphic) {
      return false;
    }
    const allowlistedShapeTypes = {
      'rectangle',
      'ellipse',
      'diamond',
      'cylinder',
      'parallelogram',
      'arrow',
    };
    return allowlistedShapeTypes.contains(
      item.metadata['insertNodeType']?.toString(),
    );
  }

  Future<Uint8List?> _readAssetLibraryBytes(AssetLibraryItem item) async {
    final storageResolver = ref.read(
      canvasStorageResolverProvider(widget.projectId),
    );
    final fileResolver = TransientFileSourceResolver(
      storageResolver: storageResolver,
      projectId: widget.projectId,
      expectedUserId: storageResolver.activeUserId,
      fileArtifactStore: _fileArtifactStore,
    );
    if (_isImageLibraryKind(item.kind)) {
      return _imageCache.loadImageBytes(
        storagePath: _validatedImageStoragePath(item.storagePath),
        localPath: item.localPath,
        url: item.runtimeUrl,
      );
    }
    final extension = item.name.contains('.')
        ? item.name.split('.').last
        : item.kind == AssetLibraryItemKind.model3d
        ? 'glb'
        : item.kind == AssetLibraryItemKind.video
        ? 'mp4'
        : item.kind == AssetLibraryItemKind.audio
        ? 'mp3'
        : 'bin';
    final payload = FilePayload(
      fileName: item.name,
      fileExtension: extension,
      storagePath: item.storagePath,
      localPath: item.localPath,
      remoteUrl: item.runtimeUrl,
    );
    return fileResolver.resolveBytes(
      payload,
      maxBytes: maxAssetLibraryMaterializationBytes,
    );
  }

  final Map<String, int> _model3DRetryCommands = {};
  final DrawingPaperPersistence _drawingPaperPersistence =
      DrawingPaperPersistence();
  final ExportQueue _exportQueue = ExportQueue();
  final Map<String, int> _drawingPaperPreviewLoads = {};
  CanvasNavigationState _navigationState = const CanvasNavigationState();
  bool _navigationLoaded = false;
  Timer? _semanticIndexSyncTimer;
  bool _semanticIndexSyncInFlight = false;
  bool _semanticIndexSyncQueued = false;
  late final TransientMediaSourceResolver _mediaSourceResolver;
  late final PortableAssetCollector _portableAssetCollector;
  late final CanvasImageCache _imageCache;

  bool get _showLayers => _panelController.showLayers;
  bool get _showInspector => _panelController.showInspector;

  bool get _collaborationReadOnly {
    if (widget.readOnly) return true;
    final session = _collaborationSession;
    return session?.isStarted == true && !session!.canEditCanvas;
  }

  bool get _collaborationCanComment {
    if (widget.readOnly) return false;
    final session = _collaborationSession;
    return session == null || !session.isStarted || session.canComment;
  }

  bool get _collaborationCanManageRoom {
    if (widget.readOnly) return false;
    final session = _collaborationSession;
    if (session?.isStarted == true) return session!.permissions.canManageRoom;
    final role = widget.collaborationRole;
    return role == null || CollaborationPermissions(role).canManageRoom;
  }

  String get _commentNotificationUserId {
    final client = ref.read(supabaseClientProvider);
    return client?.auth.currentUser?.id ??
        client?.auth.currentSession?.user.id ??
        _localUserId;
  }

  CommentNotificationScope get _commentNotificationScope =>
      CommentNotificationScope(
        projectId: widget.projectId,
        userId: _commentNotificationUserId,
      );

  CollaborationProjectionScope get _projectionScope {
    final client = ref.read(supabaseClientProvider);
    final accountId =
        client?.auth.currentUser?.id ??
        client?.auth.currentSession?.user.id ??
        'local-device';
    return CollaborationProjectionScope(
      projectId: widget.projectId,
      accountId: accountId,
    );
  }

  CanvasNode? _hitTestForSelection(Offset worldPosition) {
    final nodes = ref.read(documentNodesProvider);
    final preferences = ref.read(
      canvasSelectionPreferencesProvider(widget.projectId),
    );
    final isolateNodeId =
        preferences.isolateNodeId != null &&
            nodes.any((node) => node.id == preferences.isolateNodeId)
        ? preferences.isolateNodeId
        : null;
    final isSamePoint =
        _lastSelectionWorldPosition != null &&
        (_lastSelectionWorldPosition! - worldPosition).distance <= 6.0;
    final cycleIndex =
        preferences.mode == CanvasSelectionMode.selectThrough && isSamePoint
        ? _selectionCycleIndex + 1
        : 0;
    final hit = CanvasSelectionMath.pickAt(
      nodes,
      worldPosition,
      mode: preferences.mode,
      cycleIndex: cycleIndex,
      includeLocked: preferences.showLocked,
      includeHidden: preferences.showHidden,
      isolateNodeId: isolateNodeId,
    );
    _lastSelectionWorldPosition = worldPosition;
    _selectionCycleIndex = preferences.mode == CanvasSelectionMode.selectThrough
        ? cycleIndex
        : 0;
    _pointerDownSelectionNodeId = hit?.id;
    return hit;
  }

  void _configurePanelController(CanvasEditorPanelController? controller) {
    if (controller == null) {
      _panelController = CanvasEditorPanelController(
        initialShowLayers: widget.services.showLayersByDefault,
        initialShowInspector: !widget.services.showProjectHeader,
      );
      _ownsPanelController = true;
    } else {
      _panelController = controller;
      _ownsPanelController = false;
    }
    _panelController.addListener(_onPanelControllerChanged);
  }

  void _onPanelControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final artifactStores = ref.read(artifactStoreBundleProvider);
    _imageArtifactStore =
        widget.services.imageArtifactStore ?? artifactStores.imageArtifactStore;
    _fileArtifactStore =
        widget.services.fileArtifactStore ?? artifactStores.fileArtifactStore;
    _mediaArtifactStore =
        widget.services.mediaArtifactStore ?? artifactStores.mediaArtifactStore;
    _videoArtifactStore =
        widget.services.videoArtifactStore ?? artifactStores.videoArtifactStore;
    _model3DArtifactStore =
        widget.services.model3DArtifactStore ??
        artifactStores.model3DArtifactStore;
    _imageCache = CanvasImageCache.scoped(
      imageArtifactStore: _imageArtifactStore,
    );
    _assetLibraryMaterializer = AssetLibraryMaterializer(
      imageArtifactStore: _imageArtifactStore,
      fileArtifactStore: _fileArtifactStore,
      mediaArtifactStore: _mediaArtifactStore,
      videoArtifactStore: _videoArtifactStore,
      model3DArtifactStore: _model3DArtifactStore,
      readBytes: (item) => _readAssetLibraryBytes(item),
      isCurrent: () =>
          mounted &&
          _assetLibraryMaterializerGeneration != null &&
          _assetLibraryMaterializerGeneration == _artifactOperationGeneration,
      activeProjectId: widget.projectId,
    );
    _configurePanelController(widget.panelController);
    ref.listenManual<CanvasPanelPreferences>(
      canvasPanelPreferencesProvider,
      (_, next) => _closeDisabledPanels(next),
      fireImmediately: true,
    );
    ref.listenManual<List<CanvasNode>>(documentNodesProvider, (previous, next) {
      if (previous != null && !identical(previous, next)) {
        _canvasMutationGeneration++;
      }
      _syncDrawingPaperPreviews(next);
      final previousIds = (previous ?? const <CanvasNode>[])
          .map((node) => node.id)
          .toSet();
      final nextIds = next.map((node) => node.id).toSet();
      final removedIds = previousIds.difference(nextIds);
      if (removedIds.isNotEmpty) {
        ref
            .read(collaborationCommentsProvider(_projectionScope).notifier)
            .deleteForNodes(removedIds);
      }
      _scheduleSemanticIndexRebuild();
    }, fireImmediately: true);
    ref.listenManual<DocumentAssetManifest>(
      documentAssetsProvider,
      (_, _) => _scheduleSemanticIndexRebuild(),
      fireImmediately: true,
    );
    ref.listenManual<List<CanvasComment>>(
      collaborationCommentsProvider(_projectionScope),
      (_, _) => _scheduleSemanticIndexRebuild(),
      fireImmediately: true,
    );
    ref.listenManual<BoardHistoryState>(
      boardHistoryProvider,
      (_, _) => _scheduleSemanticIndexRebuild(),
      fireImmediately: true,
    );
    ref.listenManual<AICreativeEngineState>(
      aiCreativeEngineProvider,
      (_, _) => _scheduleSemanticIndexRebuild(),
      fireImmediately: true,
    );
    if (widget.services.enableCollaboration) {
      ref.listenManual<CollaborationSessionState>(
        collaborationSessionProvider(widget.projectId),
        (previous, next) {
          final notice = next.notice;
          if (!mounted || notice == null || notice.id == previous?.notice?.id) {
            return;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) showUiToast(context, notice.message);
          });
        },
        fireImmediately: false,
      );
    }
    ref.listenManual<CommentNotificationInboxState>(
      commentNotificationsProvider(_commentNotificationScope),
      (_, next) {
        if (!mounted || next.isLoading || _commentFilterPreferenceLoaded) {
          return;
        }
        _commentFilterPreferenceLoaded = true;
        if (_showUnresolvedCommentsOnly != next.preferences.unresolvedOnly) {
          setState(
            () => _showUnresolvedCommentsOnly = next.preferences.unresolvedOnly,
          );
        }
      },
      fireImmediately: true,
    );
    _documentTitle = widget.projectName.trim().isEmpty
        ? 'Untitled Project'
        : widget.projectName.trim();
    _documentTitleController.text = _documentTitle;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _imageCache.addListener(_onImageCacheUpdate);
    final storageResolver = ref.read(
      canvasStorageResolverProvider(widget.projectId),
    );
    _imageCache.configureStorageResolver(
      resolver: storageResolver,
      projectId: widget.projectId,
      expectedUserId: storageResolver.activeUserId,
    );
    _mediaSourceResolver = TransientMediaSourceResolver(
      artifactStoreBundle: artifactStores,
      fileResolver: resolverForStorage(
        resolver: storageResolver,
        projectId: widget.projectId,
        expectedUserId: storageResolver.activeUserId,
        artifactStoreBundle: artifactStores,
      ),
    );
    _portableAssetCollector = PortableAssetCollector(
      imageArtifactStore: _imageArtifactStore,
      fileArtifactStore: _fileArtifactStore,
      mediaArtifactStore: _mediaArtifactStore,
      videoArtifactStore: _videoArtifactStore,
      model3DArtifactStore: _model3DArtifactStore,
      storageResolver: storageResolver,
      projectId: widget.projectId,
      expectedUserId: storageResolver.activeUserId,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (widget.services.showProjectHeader) {
        await ref
            .read(openDocumentTabsProvider.notifier)
            .open(projectId: widget.projectId, name: _documentTitle);
        if (!mounted) return;
      }
      ref.read(boardHistoryProvider.notifier).clear();
      ref.read(historyProvider.notifier).clear();
      ref.read(nodeHistoryProvider.notifier).clear();
      final shouldInitAutosave =
          widget.initialDocument == null &&
          !_collaborationReadOnly &&
          (widget.collaborationRole == null ||
              CollaborationPermissions(
                widget.collaborationRole!,
              ).canEditCanvas) &&
          widget.services.enableAutosave;
      Map<String, dynamic>? documentNavigation;
      if (widget.initialDocument != null) {
        final doc = widget.initialDocument!;
        documentNavigation = doc.navigation;
        ref.read(documentNodesProvider.notifier).setNodes(doc.nodes);
        ref.read(documentEdgesProvider.notifier).setEdges(doc.edges);
        ref.read(documentAssetsProvider.notifier).setManifest(doc.assets);
        ref.read(designTokenSetProvider.notifier).setSet(doc.tokens);
        ref
            .read(viewportProvider.notifier)
            .setPosition(doc.viewport.x, doc.viewport.y);
        ref.read(viewportProvider.notifier).setZoom(doc.viewport.zoom);
        ref
            .read(collaborationCommentsProvider(_projectionScope).notifier)
            .reconcile(widget.initialComments);
      } else if (widget.readOnly) {
        final sync = ref.read(supabaseSyncServiceProvider);
        if (sync.isConfigured) {
          final doc = await sync.fetchDocumentSnapshot(widget.projectId);
          if (!mounted) return;
          if (doc != null) {
            documentNavigation = doc.navigation;
            ref.read(documentNodesProvider.notifier).setNodes(doc.nodes);
            ref.read(documentEdgesProvider.notifier).setEdges(doc.edges);
            ref.read(documentAssetsProvider.notifier).setManifest(doc.assets);
            ref.read(designTokenSetProvider.notifier).setSet(doc.tokens);
            ref
                .read(viewportProvider.notifier)
                .setPosition(doc.viewport.x, doc.viewport.y);
            ref.read(viewportProvider.notifier).setZoom(doc.viewport.zoom);
          }
        }
      }
      await _loadCanvasNavigation(documentNavigation: documentNavigation);
      if (!mounted) return;
      if (widget.services.enableCollaboration) _initCollaboration();
      if (shouldInitAutosave) {
        _autosaveController?.init(
          widget.projectId,
          syncCloud: widget.services.enableCloudSync,
        );
        _autosaveController?.updateNavigation(
          _navigationState,
          scheduleSave: false,
        );
      }
      final handoff = widget.captureHandoff;
      if (handoff != null) {
        final accountId = ref.read(supabaseSyncServiceProvider).currentUserId;
        final accepted = handoff.consume(
          projectId: widget.projectId,
          accountId: accountId,
        );
        if (accepted) {
          if (_canCommitCaptureTarget()) {
            unawaited(_insertCaptureHandoff(handoff, accountId: accountId));
          } else {
            showUiToast(
              context,
              'This capture cannot be added to the selected project.',
              variant: UiToastVariant.error,
            );
          }
        }
      }
    });
  }

  bool _canEditCaptureTarget() => canAcceptLocalCaptureCanvasHandoff(
    readOnly: widget.readOnly,
    collaborationRoom: widget.captureTargetIsCollaborationRoom,
    hasCollaborationRole: widget.collaborationRole != null,
  );

  CanvasNode _captureNodeWithAssetId(CanvasNode node, String assetId) {
    final payload = node.payload;
    final updatedPayload = switch (payload) {
      ImagePayload() => payload.copyWith(assetId: assetId),
      AudioPayload() => payload.copyWith(assetId: assetId),
      FilePayload() => payload.copyWith(assetId: assetId),
      _ => payload,
    };
    return identical(payload, updatedPayload)
        ? node
        : node.copyWith(payload: updatedPayload);
  }

  String? _captureAssetIdFor(CanvasNode node) => switch (node.payload) {
    ImagePayload(:final assetId) => assetId,
    AudioPayload(:final assetId) => assetId,
    FilePayload(:final assetId) => assetId,
    _ => null,
  };

  CanvasNode _captureNodeWithManifestAssetId(CanvasNode node, String assetId) {
    if (_captureAssetIdFor(node) == null) return node;
    return _captureNodeWithAssetId(node, assetId);
  }

  bool _isCaptureCollaborationRoute() =>
      widget.captureTargetIsCollaborationRoom ||
      widget.collaborationRole != null;

  bool _canCommitCaptureTarget() =>
      _canEditCaptureTarget() &&
      !_isCaptureCollaborationRoute() &&
      !_collaborationReadOnly;

  Future<void> _insertCaptureHandoff(
    CaptureCanvasHandoff handoff, {
    required String? accountId,
  }) async {
    final captureId = handoff.captureId;
    final projectId = widget.projectId;
    final operationGeneration = ++_artifactOperationGeneration;
    final canvasMutationGeneration = _canvasMutationGeneration;
    final captureNotifier = ref.read(captureItemsProvider.notifier);

    try {
      if (!_canEditCaptureTarget() || handoff.projectId != projectId) {
        throw const CaptureCanvasMaterializationException();
      }
      final capture = await captureNotifier.getCapture(captureId);
      if (capture == null || capture.status == CaptureStatus.deleted) {
        throw const CaptureCanvasMaterializationException();
      }
      final bytes = capture.assetId == null
          ? null
          : await captureNotifier.readCaptureAsset(captureId);
      if (!_isArtifactOperationCurrent(
            generation: operationGeneration,
            projectId: projectId,
            accountId: accountId,
          ) ||
          _canvasMutationGeneration != canvasMutationGeneration) {
        return;
      }
      final nodeId = newCaptureCanvasNodeId();
      final prepared = await materializeCaptureCanvasNode(
        capture: capture,
        center: _assetLibraryInsertionPosition(),
        nodeId: nodeId,
        bytes: bytes,
        imageStore: _imageArtifactStore,
        fileStore: _fileArtifactStore,
        mediaStore: _mediaArtifactStore,
      );
      if (!_isArtifactOperationCurrent(
            generation: operationGeneration,
            projectId: projectId,
            accountId: accountId,
          ) ||
          _canvasMutationGeneration != canvasMutationGeneration ||
          !_canCommitCaptureTarget()) {
        return;
      }
      final originalManifest = ref.read(documentAssetsProvider);
      final currentNodes = ref.read(documentNodesProvider);
      final preparedAsset = prepared.asset;
      final assetId = preparedAsset == null
          ? null
          : stableDocumentAssetIdForCapture(
              preferredId: preparedAsset.id,
              occupiedManifestIds: originalManifest.entries.keys.toSet(),
              occupiedNodeIds: currentNodes.map((node) => node.id).toSet(),
              fallback: prepared.node.id,
            );
      final node = assetId == null
          ? prepared.node
          : _captureNodeWithManifestAssetId(prepared.node, assetId);
      final committedAsset = preparedAsset == null || assetId == null
          ? null
          : preparedAsset.copyWith(id: assetId);
      final committedManifest = committedAsset == null
          ? originalManifest
          : originalManifest.upsert(committedAsset);
      if (!_isArtifactOperationCurrent(
            generation: operationGeneration,
            projectId: projectId,
            accountId: accountId,
          ) ||
          _canvasMutationGeneration != canvasMutationGeneration ||
          !_canCommitCaptureTarget()) {
        return;
      }
      publishDocumentAssetAndNode(
        originalManifest: originalManifest,
        committedManifest: committedManifest,
        setManifest: (next) =>
            ref.read(documentAssetsProvider.notifier).setManifest(next),
        publishNode: () =>
            ref.read(documentNodesProvider.notifier).addNode(node),
      );
      ref.read(selectionProvider.notifier).select(node.id);
    } on CaptureCanvasMaterializationException {
      if (mounted) {
        showUiToast(
          context,
          'This capture is unavailable or cannot be added to the canvas.',
          variant: UiToastVariant.error,
        );
      }
    } catch (_) {
      if (mounted) {
        showUiToast(
          context,
          'Could not add this capture to the canvas.',
          variant: UiToastVariant.error,
        );
      }
    }
  }

  Future<void> _loadCanvasNavigation({
    Map<String, dynamic>? documentNavigation,
  }) async {
    try {
      final loaded = documentNavigation != null && documentNavigation.isNotEmpty
          ? CanvasNavigationState.fromJson(documentNavigation)
          : await _loadPersistedNavigation();
      final pages = loaded.pages.where((page) => !page.archived).toList();
      if (pages.isEmpty) {
        pages.add(const CanvasPage(id: 'page-1', name: 'Page 1'));
      }
      final activePageId = pages.any((page) => page.id == loaded.activePageId)
          ? loaded.activePageId
          : pages.first.id;
      if (!mounted) return;
      ref.read(documentNodesProvider.notifier).setActivePageId(activePageId);
      final next = loaded.copyWith(pages: pages, activePageId: activePageId);
      _autosaveController?.updateNavigation(next, scheduleSave: false);
      setState(() {
        _navigationState = next;
        _navigationLoaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _navigationLoaded = true);
      showUiToast(
        context,
        'Canvas navigation could not be restored: $error',
        variant: UiToastVariant.warning,
      );
    }
  }

  Future<CanvasNavigationState> _loadPersistedNavigation() async {
    final durable = ref.read(projectSessionProvider(widget.projectId));
    final raw = await durable.store.readViewport(widget.projectId);
    if (raw != null && raw.isNotEmpty) {
      try {
        return CanvasNavigationState.fromJson(jsonDecode(raw));
      } catch (_) {
        // Fall through to the compatibility adapter below.
      }
    }
    return ref
        .read(localStorageServiceProvider)
        .loadCanvasNavigation(widget.projectId);
  }

  Future<void> _persistCanvasNavigation() async {
    try {
      await ref
          .read(localStorageServiceProvider)
          .saveCanvasNavigation(widget.projectId, _navigationState);
      await ref
          .read(projectSessionProvider(widget.projectId))
          .store
          .writeViewport(
            projectId: widget.projectId,
            viewportJson: jsonEncode(_navigationState.toJson()),
          );
    } catch (error) {
      if (mounted) {
        showUiToast(
          context,
          'Canvas navigation could not be saved: $error',
          variant: UiToastVariant.warning,
        );
      }
    }
  }

  void _commitCanvasNavigation(CanvasNavigationState next) {
    if (!mounted) return;
    setState(() => _navigationState = next);
    _autosaveController?.updateNavigation(next);
    unawaited(_persistCanvasNavigation());
  }

  CanvasPage? get _activeCanvasPage {
    final activePageId = _navigationState.activePageId;
    for (final page in _navigationState.pages) {
      if (page.id == activePageId) return page;
    }
    return _navigationState.pages.isEmpty ? null : _navigationState.pages.first;
  }

  String _canvasPageBreadcrumb(CanvasPage page) {
    final sectionId = page.sectionId;
    if (sectionId == null) return page.name;
    for (final section in _navigationState.sections) {
      if (section.id == sectionId) return '${section.name} / ${page.name}';
    }
    return page.name;
  }

  List<UiMenuAction<String>> _canvasPageMenuItems() {
    final pages =
        [..._navigationState.pages].where((page) => !page.archived).toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    return pages
        .map(
          (page) => UiMenuAction<String>(
            value: page.id,
            icon: Icons.description_outlined,
            label: _canvasPageBreadcrumb(page),
            selected: page.id == _navigationState.activePageId,
          ),
        )
        .toList(growable: false);
  }

  void _selectCanvasPage(String pageId) {
    if (_navigationState.activePageId == pageId) return;
    ref.read(documentNodesProvider.notifier).setActivePageId(pageId);
    _commitCanvasNavigation(_navigationState.copyWith(activePageId: pageId));
  }

  Future<String?> _promptCanvasName({
    required String title,
    String initialName = '',
  }) async {
    final controller = TextEditingController(text: initialName);
    final result = await showUiDialog<String>(
      context: context,
      builder: (dialogContext) => UiDialog(
        semanticsLabel: title,
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(AppSpacing.pageWide),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
              UiTextField(
                controller: controller,
                autofocus: true,
                label: 'Name',
                hint: 'Enter a name',
                onSubmitted: (_) {
                  final value = controller.text.trim();
                  if (value.isNotEmpty) Navigator.pop(dialogContext, value);
                },
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
                      final value = controller.text.trim();
                      if (value.isNotEmpty) {
                        Navigator.pop(dialogContext, value);
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  int _nextCanvasNavigationOrder(Iterable<int> orders) {
    var highest = -1;
    for (final order in orders) {
      if (order > highest) highest = order;
    }
    return highest + 1;
  }

  Future<void> _createCanvasPage({String? sectionId}) async {
    if (_collaborationReadOnly) return;
    final name = await _promptCanvasName(title: 'Create canvas page');
    if (!mounted || name == null) return;
    final page = CanvasPage(
      id: const Uuid().v4(),
      name: name,
      sectionId: sectionId,
      order: _nextCanvasNavigationOrder(
        _navigationState.pages.map((item) => item.order),
      ),
    );
    _commitCanvasNavigation(
      _navigationState.copyWith(
        pages: [..._navigationState.pages, page],
        activePageId: page.id,
      ),
    );
  }

  Future<void> _renameActiveCanvasPage() async {
    if (_collaborationReadOnly) return;
    final page = _activeCanvasPage;
    if (page == null) return;
    final name = await _promptCanvasName(
      title: 'Rename canvas page',
      initialName: page.name,
    );
    if (!mounted || name == null) return;
    _commitCanvasNavigation(
      _navigationState.copyWith(
        pages: _navigationState.pages
            .map(
              (item) => item.id == page.id ? item.copyWith(name: name) : item,
            )
            .toList(growable: false),
      ),
    );
  }

  Future<void> _archiveActiveCanvasPage() async {
    if (_collaborationReadOnly) return;
    final page = _activeCanvasPage;
    final pages = _navigationState.pages
        .where((item) => !item.archived)
        .toList(growable: false);
    if (page == null || pages.length <= 1) {
      showUiToast(context, 'Keep at least one canvas page.');
      return;
    }
    final remaining = pages.where((item) => item.id != page.id).toList();
    final nextPage = remaining.first;
    _commitCanvasNavigation(
      _navigationState.copyWith(
        pages: _navigationState.pages
            .map(
              (item) =>
                  item.id == page.id ? item.copyWith(archived: true) : item,
            )
            .toList(growable: false),
        activePageId: nextPage.id,
      ),
    );
  }

  Future<void> _createCanvasSection() async {
    if (_collaborationReadOnly) return;
    final name = await _promptCanvasName(title: 'Create canvas section');
    if (!mounted || name == null) return;
    final section = CanvasSection(
      id: const Uuid().v4(),
      name: name,
      order: _nextCanvasNavigationOrder(
        _navigationState.sections.map((item) => item.order),
      ),
    );
    _commitCanvasNavigation(
      _navigationState.copyWith(
        sections: [..._navigationState.sections, section],
      ),
    );
  }

  Future<void> _renameCanvasSection(String sectionId) async {
    if (_collaborationReadOnly) return;
    final section = _navigationState.sections
        .where((item) => item.id == sectionId)
        .firstOrNull;
    if (section == null) return;
    final name = await _promptCanvasName(
      title: 'Rename canvas section',
      initialName: section.name,
    );
    if (!mounted || name == null) return;
    _commitCanvasNavigation(
      _navigationState.copyWith(
        sections: _navigationState.sections
            .map(
              (item) => item.id == sectionId ? item.copyWith(name: name) : item,
            )
            .toList(growable: false),
      ),
    );
  }

  void _moveActiveCanvasPageToSection(String? sectionId) {
    if (_collaborationReadOnly) return;
    final page = _activeCanvasPage;
    if (page == null || page.sectionId == sectionId) return;
    _commitCanvasNavigation(
      _navigationState.copyWith(
        pages: _navigationState.pages
            .map(
              (item) => item.id == page.id
                  ? item.copyWith(sectionId: sectionId)
                  : item,
            )
            .toList(growable: false),
      ),
    );
  }

  List<UiMenuAction<String>> _canvasNavigationMenuItems() {
    final items = <UiMenuAction<String>>[
      const UiMenuAction<String>(
        value: 'zoom_content',
        icon: Icons.fit_screen_outlined,
        label: 'Zoom to content',
      ),
      UiMenuAction<String>(
        value: 'bookmarks',
        icon: Icons.bookmarks_outlined,
        label: 'Viewport bookmarks',
        suffix: _navigationState.bookmarks.isEmpty
            ? null
            : UiBadge(_navigationState.bookmarks.length.toString()),
      ),
      UiMenuAction<String>(
        value: 'focus',
        icon: _navigationState.focusMode
            ? Icons.fullscreen_exit_outlined
            : Icons.fullscreen_outlined,
        label: _navigationState.focusMode
            ? 'Exit focus mode'
            : 'Enter focus mode',
        selected: _navigationState.focusMode,
      ),
    ];
    if (_navigationLoaded && !_collaborationReadOnly) {
      items.addAll([
        const UiMenuAction<String>(
          value: 'new_page',
          icon: Icons.note_add_outlined,
          label: 'New page',
        ),
        const UiMenuAction<String>(
          value: 'rename_page',
          icon: Icons.edit_outlined,
          label: 'Rename current page',
        ),
        const UiMenuAction<String>(
          value: 'archive_page',
          icon: Icons.archive_outlined,
          label: 'Archive current page',
        ),
        const UiMenuAction<String>(
          value: 'new_section',
          icon: Icons.folder_outlined,
          label: 'New section',
        ),
      ]);
      for (final section in _navigationState.sections) {
        items.add(
          UiMenuAction<String>(
            value: 'rename_section:${section.id}',
            icon: Icons.drive_file_rename_outline,
            label: 'Rename section: ${section.name}',
          ),
        );
        items.add(
          UiMenuAction<String>(
            value: 'move_section:${section.id}',
            icon: Icons.drive_file_move_outlined,
            label: 'Move current page to ${section.name}',
          ),
        );
      }
      if (_activeCanvasPage?.sectionId != null) {
        items.add(
          const UiMenuAction<String>(
            value: 'move_section:none',
            icon: Icons.folder_off_outlined,
            label: 'Remove page from section',
          ),
        );
      }
    }
    return items;
  }

  void _zoomToCanvasContent() {
    final canvasSize = _canvasKey.currentContext?.size;
    if (canvasSize == null || canvasSize.isEmpty) return;
    final bounds = CanvasNavigationMath.visibleBounds(
      ref.read(documentNodesProvider),
    );
    if (bounds.isEmpty) {
      showUiToast(context, 'No visible content to frame.');
      return;
    }
    ref.read(viewportProvider.notifier).zoomToContent([bounds], canvasSize);
  }

  void _adjustCanvasZoom(double factor) {
    final canvasSize = _canvasKey.currentContext?.size;
    if (canvasSize == null || canvasSize.isEmpty) return;
    ref
        .read(viewportProvider.notifier)
        .zoomBy(factor, Offset(canvasSize.width / 2, canvasSize.height / 2));
  }

  void _resetCanvasZoom() {
    final zoom = ref.read(viewportProvider).zoom;
    if (zoom <= 0 || !zoom.isFinite) return;
    _adjustCanvasZoom(1 / zoom);
  }

  void _toggleCanvasFocusMode() {
    _commitCanvasNavigation(
      _navigationState.copyWith(focusMode: !_navigationState.focusMode),
    );
  }

  Future<ViewportBookmark?> _createViewportBookmark(String name) async {
    if (_collaborationReadOnly) return null;
    final now = DateTime.now().toUtc();
    final bookmark = ViewportBookmark(
      id: const Uuid().v4(),
      name: name,
      viewport: ref.read(viewportProvider),
      pageId: _navigationState.activePageId,
      selectedNodeIds: ref.read(selectionProvider).toList(growable: false),
      createdAt: now,
      updatedAt: now,
    );
    _commitCanvasNavigation(
      _navigationState.copyWith(
        bookmarks: [bookmark, ..._navigationState.bookmarks],
      ),
    );
    return bookmark;
  }

  Future<ViewportBookmark?> _renameViewportBookmark(
    ViewportBookmark bookmark,
    String name,
  ) async {
    if (_collaborationReadOnly) return null;
    final renamed = bookmark.copyWith(
      name: name,
      updatedAt: DateTime.now().toUtc(),
    );
    _commitCanvasNavigation(
      _navigationState.copyWith(
        bookmarks: _navigationState.bookmarks
            .map((item) => item.id == bookmark.id ? renamed : item)
            .toList(growable: false),
      ),
    );
    return renamed;
  }

  Future<bool> _deleteViewportBookmark(ViewportBookmark bookmark) async {
    if (_collaborationReadOnly) return false;
    _commitCanvasNavigation(
      _navigationState.copyWith(
        bookmarks: _navigationState.bookmarks
            .where((item) => item.id != bookmark.id)
            .toList(growable: false),
      ),
    );
    return true;
  }

  Future<void> _openViewportBookmarks() async {
    if (!_navigationLoaded || !mounted) return;
    await showUiDialog<void>(
      context: context,
      builder: (_) => ViewportBookmarksDialog(
        bookmarks: _navigationState.bookmarks,
        readOnly: _collaborationReadOnly,
        onCreate: _collaborationReadOnly ? null : _createViewportBookmark,
        onRename: _collaborationReadOnly ? null : _renameViewportBookmark,
        onDelete: _collaborationReadOnly ? null : _deleteViewportBookmark,
        onSelect: (bookmark) {
          ref.read(viewportProvider.notifier).setViewport(bookmark.viewport);
          final nodes = ref.read(documentNodesProvider);
          final selectedIds = bookmark.selectedNodeIds
              .where((id) => nodes.any((node) => node.id == id))
              .toList(growable: false);
          if (selectedIds.isEmpty) {
            ref.read(selectionProvider.notifier).clear();
          } else {
            ref.read(selectionProvider.notifier).selectAll(selectedIds);
          }
          if (bookmark.pageId != null &&
              _navigationState.pages.any(
                (page) => page.id == bookmark.pageId,
              )) {
            _commitCanvasNavigation(
              _navigationState.copyWith(activePageId: bookmark.pageId),
            );
          }
        },
      ),
    );
  }

  @override
  void didUpdateWidget(covariant CanvasEditorSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.projectId != widget.projectId) {
      _documentTitle = widget.projectName.trim().isEmpty
          ? 'Untitled Project'
          : widget.projectName.trim();
      _documentTitleController.text = _documentTitle;
      _editingDocumentTitle = false;
      _artifactOperationGeneration++;
      _drawingPaperPreviewLoads.clear();
      _imageCache.clear();
      final storageResolver = ref.read(
        canvasStorageResolverProvider(widget.projectId),
      );
      _imageCache.configureStorageResolver(
        resolver: storageResolver,
        projectId: widget.projectId,
        expectedUserId: storageResolver.activeUserId,
      );
    } else if (oldWidget.projectName != widget.projectName &&
        !_editingDocumentTitle &&
        !_documentTitleCommitInProgress) {
      _documentTitle = widget.projectName.trim().isEmpty
          ? 'Untitled Project'
          : widget.projectName.trim();
      _documentTitleController.text = _documentTitle;
    }
    if (identical(oldWidget.panelController, widget.panelController)) return;

    _panelController.removeListener(_onPanelControllerChanged);
    if (_ownsPanelController) _panelController.dispose();
    _configurePanelController(widget.panelController);
  }

  void _closeDisabledPanels(CanvasPanelPreferences preferences) {
    final closeLayers = !preferences.showLayersButton && _showLayers;
    final closeInspector = !preferences.showInspectorButton && _showInspector;
    if (!closeLayers && !closeInspector) return;

    if (closeLayers) _panelController.setLayers(false);
    if (closeInspector) _panelController.setInspector(false);
  }

  void _setPanelButtonEnabled({
    required bool enabled,
    required bool isOpen,
    required VoidCallback closePanel,
    required Future<void> Function(bool enabled) persist,
  }) {
    if (!enabled && isOpen) closePanel();
    unawaited(persist(enabled));
  }

  void _setLayersButtonEnabled(bool enabled) => _setPanelButtonEnabled(
    enabled: enabled,
    isOpen: _showLayers,
    closePanel: () => _panelController.setLayers(false),
    persist: ref
        .read(canvasPanelPreferencesProvider.notifier)
        .setLayersButtonEnabled,
  );

  void _setInspectorButtonEnabled(bool enabled) => _setPanelButtonEnabled(
    enabled: enabled,
    isOpen: _showInspector,
    closePanel: () => _panelController.setInspector(false),
    persist: ref
        .read(canvasPanelPreferencesProvider.notifier)
        .setInspectorButtonEnabled,
  );

  bool _usesCompactEditorLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).width < AppBreakpoints.expanded;

  void _toggleLayersPanel(BuildContext context) {
    if (!_usesCompactEditorLayout(context)) {
      _panelController.toggleLayers();
      return;
    }
    final next = !_showLayers;
    _panelController.setLayers(next);
    if (next) {
      _panelController.setInspector(false);
    }
  }

  void _toggleInspectorPanel(BuildContext context) {
    if (!_usesCompactEditorLayout(context)) {
      _panelController.toggleInspector();
      return;
    }
    final next = !_showInspector;
    _panelController.setInspector(next);
    if (next) {
      _panelController.setLayers(false);
    }
  }

  void _focusAiComposer() {
    if (!_collaborationReadOnly && widget.services.enableAiStudio) {
      _aiPromptFocusNode.requestFocus();
    }
  }

  void _closeCompactPanels() {
    _panelController.setLayers(false);
    _panelController.setInspector(false);
  }

  bool _handleKeyEvent(KeyEvent event) {
    final focusedCanvas = FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<_CanvasEditorSurfaceState>();
    if (focusedCanvas != this) return false;

    final isDown = event is KeyDownEvent;
    if (event.logicalKey == LogicalKeyboardKey.altLeft ||
        event.logicalKey == LogicalKeyboardKey.altRight) {
      if (_altPressed != isDown) {
        setState(() => _altPressed = isDown);
      }
      return false;
    }

    if (!isDown) return false;
    if (_hasEditableFocus()) return false;

    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final meta = HardwareKeyboard.instance.isMetaPressed;
    final primaryModifier = ctrl || meta;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;
    final key = event.logicalKey;

    if (!primaryModifier && !shift) {
      final tool = _toolForShortcut(key);
      if (tool != null) {
        ref.read(activeToolProvider.notifier).setTool(tool);
        return true;
      }
    }

    if (primaryModifier && key == LogicalKeyboardKey.keyC) {
      _copySelection();
      return true;
    }
    if (primaryModifier && key == LogicalKeyboardKey.keyX) {
      _copySelection(cut: true);
      return true;
    }
    if (primaryModifier && key == LogicalKeyboardKey.keyV) {
      _pasteClipboard();
      return true;
    }
    if (primaryModifier && key == LogicalKeyboardKey.keyZ) {
      if (shift) {
        ref.read(documentNodesProvider.notifier).redo();
      } else {
        ref.read(documentNodesProvider.notifier).undo();
      }
      return true;
    }
    if (primaryModifier && key == LogicalKeyboardKey.keyY) {
      ref.read(documentNodesProvider.notifier).redo();
      return true;
    }
    if (primaryModifier && !alt && !shift && key == LogicalKeyboardKey.keyK) {
      _openQuickCapturePalette();
      return true;
    }
    if (primaryModifier && alt && key == LogicalKeyboardKey.keyK) {
      final ids = ref.read(selectionProvider).toList();
      if (ids.isNotEmpty) {
        _createComponentFromSelection(ids);
      }
      return true;
    }
    if (primaryModifier && key == LogicalKeyboardKey.keyD) {
      final ids = ref.read(selectionProvider).toList();
      if (ids.isNotEmpty) {
        final newIds = _duplicateNodesAndTrackUsage(ids);
        ref.read(selectionProvider.notifier).selectAll(newIds);
      }
      return true;
    }
    final selectedIds = ref.read(selectionProvider).toList(growable: false);
    if (!primaryModifier &&
        selectedIds.isNotEmpty &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown)) {
      final step = shift ? 10.0 : (alt ? 0.25 : 1.0);
      ref
          .read(documentNodesProvider.notifier)
          .nudgeNodes(
            selectedIds,
            dx: key == LogicalKeyboardKey.arrowLeft
                ? -1
                : key == LogicalKeyboardKey.arrowRight
                ? 1
                : 0,
            dy: key == LogicalKeyboardKey.arrowUp
                ? -1
                : key == LogicalKeyboardKey.arrowDown
                ? 1
                : 0,
            step: step,
          );
      return true;
    }
    if (!primaryModifier &&
        selectedIds.isNotEmpty &&
        (key == LogicalKeyboardKey.bracketLeft ||
            key == LogicalKeyboardKey.bracketRight)) {
      final degrees = shift ? 15.0 : 1.0;
      final radians = degrees * math.pi / 180;
      ref
          .read(documentNodesProvider.notifier)
          .rotateNodes(
            selectedIds,
            key == LogicalKeyboardKey.bracketLeft ? -radians : radians,
          );
      return true;
    }
    if (primaryModifier && key == LogicalKeyboardKey.keyF) {
      _openSearchDialog();
      return true;
    }
    if (!ctrl &&
        (key == LogicalKeyboardKey.delete ||
            key == LogicalKeyboardKey.backspace)) {
      final ids = ref.read(selectionProvider).toList();
      if (ids.isNotEmpty) {
        final nodeIds = ref
            .read(documentNodesProvider)
            .where((node) => ids.contains(node.id))
            .map((node) => node.id)
            .toList();
        final edgeIds = ref
            .read(documentEdgesProvider)
            .where((edge) => ids.contains(edge.id))
            .map((edge) => edge.id)
            .toList();
        if (nodeIds.isNotEmpty) {
          ref.read(documentNodesProvider.notifier).deleteNodes(nodeIds);
        }
        if (edgeIds.isNotEmpty) {
          ref.read(documentNodesProvider.notifier).deleteEdges(edgeIds);
        }
        ref.read(selectionProvider.notifier).clear();
      }
      return true;
    }
    if (ctrl && key == LogicalKeyboardKey.bracketRight) {
      final ids = ref.read(selectionProvider).toList();
      if (ids.length == 1) {
        ref.read(documentNodesProvider.notifier).bringForward(ids.first);
      }
      return true;
    }
    if (ctrl && key == LogicalKeyboardKey.bracketLeft) {
      final ids = ref.read(selectionProvider).toList();
      if (ids.length == 1) {
        ref.read(documentNodesProvider.notifier).sendBackward(ids.first);
      }
      return true;
    }
    if (ctrl && shift && key == LogicalKeyboardKey.keyG) {
      final ids = ref.read(selectionProvider).toList();
      final nodes = ref.read(documentNodesProvider);
      for (final id in ids) {
        final match = nodes
            .where((n) => n.id == id && n.type == NodeType.group)
            .toList();
        if (match.isNotEmpty) {
          final payload = match.first.payload as GroupPayload;
          ref.read(documentNodesProvider.notifier).ungroupNodes(match.first.id);
          ref.read(selectionProvider.notifier).selectAll(payload.childNodeIds);
          break;
        }
      }
      return true;
    }
    if (ctrl && !shift && key == LogicalKeyboardKey.keyG) {
      final ids = ref.read(selectionProvider).toList();
      if (ids.length > 1) {
        final groupId = ref
            .read(documentNodesProvider.notifier)
            .groupNodes(ids);
        if (groupId != null) {
          ref.read(selectionProvider.notifier).select(groupId);
        }
      }
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (_connectorEditEdgeId != null) {
        _cancelConnectorEdit();
      } else if (_activePenPoints.isNotEmpty) {
        _finalizePenPath(isClosed: false);
      } else if (_connectorSourceNodeId != null) {
        setState(() => _connectorSourceNodeId = null);
      } else {
        ref.read(activeToolProvider.notifier).setTool(CanvasTool.select);
        ref.read(selectionProvider.notifier).clear();
      }
      return true;
    }
    if (key == LogicalKeyboardKey.enter && _activePenPoints.isNotEmpty) {
      _finalizePenPath(isClosed: false);
      return true;
    }
    return false;
  }

  bool _hasEditableFocus() {
    final node = FocusManager.instance.primaryFocus;
    return node?.context?.findAncestorStateOfType<EditableTextState>() != null;
  }

  CanvasTool? _toolForShortcut(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.keyV) return CanvasTool.select;
    if (key == LogicalKeyboardKey.keyH) return CanvasTool.hand;
    if (key == LogicalKeyboardKey.keyF) return CanvasTool.frame;
    if (key == LogicalKeyboardKey.keyR) return CanvasTool.rectangle;
    if (key == LogicalKeyboardKey.keyO) return CanvasTool.ellipse;
    if (key == LogicalKeyboardKey.keyL) return CanvasTool.line;
    if (key == LogicalKeyboardKey.keyA) return CanvasTool.arrow;
    if (key == LogicalKeyboardKey.keyC) return CanvasTool.connector;
    if (key == LogicalKeyboardKey.keyB) return CanvasTool.brush;
    if (key == LogicalKeyboardKey.keyP) return CanvasTool.pen;
    if (key == LogicalKeyboardKey.keyT) return CanvasTool.text;
    if (key == LogicalKeyboardKey.keyN) return CanvasTool.stickyNote;
    if (key == LogicalKeyboardKey.keyX) return CanvasTool.todoList;
    if (key == LogicalKeyboardKey.keyG) return CanvasTool.tableGrid;
    if (key == LogicalKeyboardKey.keyU) return CanvasTool.columnContainer;
    if (key == LogicalKeyboardKey.keyK) return CanvasTool.component;
    if (key == LogicalKeyboardKey.keyI) return CanvasTool.image;
    if (key == LogicalKeyboardKey.keyM) return CanvasTool.comment;
    return null;
  }

  List<UiMenuAction<String>> _buildSettingsMenuItems({
    required ThemeMode themeMode,
    required CanvasPanelPreferences panelPreferences,
  }) => [
    if (!_collaborationReadOnly)
      const UiMenuAction(
        value: 'import',
        icon: Icons.input_outlined,
        label: 'Import Diagram / JSON',
      ),
    if (!_collaborationReadOnly)
      const UiMenuAction(
        value: 'board_history',
        icon: Icons.history,
        label: 'Board History',
      ),
    const UiMenuAction(
      value: 'presentation',
      icon: Icons.play_circle_outline,
      label: 'Play Presentation Mode',
    ),
    const UiMenuAction(
      value: 'presentation_remote_host',
      icon: Icons.slideshow_outlined,
      label: 'Join Presenter Remote',
    ),
    const UiMenuAction(
      value: 'presentation_remote_controller',
      icon: Icons.settings_remote_outlined,
      label: 'Remote Presenter Controller',
    ),
    if (!_collaborationReadOnly)
      const UiMenuAction(
        value: 'publish_snapshot',
        icon: Icons.publish_outlined,
        label: 'Publish Snapshot',
      ),
    const UiMenuAction(
      value: 'review_workflow',
      icon: Icons.rate_review_outlined,
      label: 'Review & Handoff',
    ),
    const UiMenuAction(
      value: 'quick_capture',
      icon: Icons.bolt_outlined,
      label: 'Quick Capture (Ctrl/Cmd+K)',
    ),
    const UiMenuAction(
      value: 'asset_library',
      icon: Icons.perm_media_outlined,
      label: 'Asset Library',
    ),
    const UiMenuAction(
      value: 'design_tokens',
      icon: Icons.toll_outlined,
      label: 'Design Tokens',
    ),
    const UiMenuAction(
      value: 'component_library',
      icon: Icons.widgets_outlined,
      label: 'Component Library',
    ),
    const UiMenuAction(
      value: 'flowchart',
      icon: Icons.account_tree_outlined,
      label: 'Insert Flowchart Template',
    ),
    if (!_collaborationReadOnly)
      const UiMenuAction(
        value: 'save_selection_template',
        icon: Icons.bookmark_add_outlined,
        label: 'Save Selection as Template',
      ),
    if (!_collaborationReadOnly) ...[
      UiMenuAction(
        value: 'layers',
        icon: Icons.layers_outlined,
        label: 'Layers',
        suffix: PanelVisibilityToggle(
          id: 'layers',
          label: 'Layers',
          enabled: panelPreferences.showLayersButton,
          onChanged: _setLayersButtonEnabled,
        ),
        rowInteractive: false,
      ),
      UiMenuAction(
        value: 'inspector',
        icon: Icons.tune_outlined,
        label: 'Inspector',
        suffix: PanelVisibilityToggle(
          id: 'inspector',
          label: 'Inspector',
          enabled: panelPreferences.showInspectorButton,
          onChanged: _setInspectorButtonEnabled,
        ),
        rowInteractive: false,
      ),
    ] else
      UiMenuAction(
        value: 'layers',
        icon: Icons.layers_outlined,
        label: 'Layers',
        suffix: PanelVisibilityToggle(
          id: 'layers',
          label: 'Layers',
          enabled: panelPreferences.showLayersButton,
          onChanged: _setLayersButtonEnabled,
        ),
        rowInteractive: false,
      ),
    UiMenuAction(
      value: 'theme',
      icon: switch (themeMode) {
        ThemeMode.system => Icons.brightness_auto_outlined,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      },
      label: 'Theme: ${themeModeLabel(themeMode)}',
    ),
    const UiMenuAction(
      value: 'backend',
      icon: Icons.settings_ethernet,
      label: 'Backend & Live Integrations',
    ),
    const UiMenuAction(
      value: 'collaboration_profile',
      icon: Icons.account_circle_outlined,
      label: 'Edit Collaboration Profile',
    ),
    const UiMenuAction(
      value: 'governance',
      icon: Icons.accessibility_new_outlined,
      label: 'Workspace Governance',
    ),
  ];

  Future<void> _applyOwnedImport(ImportResult result) async {
    if (_collaborationReadOnly || !mounted) {
      throw StateError('Read-only projects cannot import content.');
    }
    final session = ref.read(projectSessionProvider(widget.projectId));
    final generation = session.generation;
    final currentNodes = ref.read(documentNodesProvider);
    final currentEdges = ref.read(documentEdgesProvider);
    final currentAssets = ref.read(documentAssetsProvider);
    final plan = ImportMergePlanner.plan(
      importedNodes: result.nodes,
      importedEdges: result.edges,
      existingNodeIds: currentNodes.map((node) => node.id),
      existingEdgeIds: currentEdges.map((edge) => edge.id),
      existingAssets: currentAssets,
      importedAssets: result.assets,
      collisionPrefix: 'import-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (session.isDisposed || session.generation != generation) {
      throw StateError('Import ownership is no longer active.');
    }
    final unresolved = ImportMergePlanner.unresolvedDependencies(
      nodes: plan.nodes,
      assets: plan.assets,
    );
    if (unresolved.isNotEmpty) {
      throw StateError(
        'Import contains unresolved asset references: ${unresolved.join(', ')}',
      );
    }
    final nodesNotifier = ref.read(documentNodesProvider.notifier);
    final edgesNotifier = ref.read(documentEdgesProvider.notifier);
    final assetsNotifier = ref.read(documentAssetsProvider.notifier);
    final previousNodes = List<CanvasNode>.from(currentNodes);
    final previousEdges = List<CanvasEdge>.from(currentEdges);
    final previousAssets = currentAssets;
    nodesNotifier.beginTransaction(name: 'Import content');
    try {
      ImportPublicationTransaction.run(
        commit: () {
          nodesNotifier.executeCommand(
            CreateNodesCommand(nodes: plan.nodes, edges: plan.edges),
          );
          assetsNotifier.setManifest(plan.assets);
        },
        rollback: () {
          nodesNotifier.cancelTransaction();
          nodesNotifier.setNodes(previousNodes);
          edgesNotifier.setEdges(previousEdges);
          assetsNotifier.setManifest(previousAssets);
        },
      );
      nodesNotifier.commitTransaction();
    } catch (_) {
      nodesNotifier.cancelTransaction();
      rethrow;
    }
  }

  void _returnToDashboard() {
    if (!mounted) return;
    final openLibrary = widget.onOpenProjectLibrary;
    if (openLibrary != null) {
      unawaited(openLibrary(context));
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      GoRouter.maybeOf(context)?.go('/');
    }
  }

  Widget _buildDocumentTitle(BuildContext context, AppTokens tokens) {
    if (_editingDocumentTitle) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: TapRegion(
          groupId: 'document_title_editor',
          onTapOutside: (_) => _commitDocumentTitle(),
          child: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    _cancelDocumentTitleEdit();
                    return null;
                  },
                ),
              },
              child: UiTextField(
                key: const ValueKey('canvas-document-title-editor'),
                controller: _documentTitleController,
                focusNode: _documentTitleFocusNode,
                autofocus: true,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                hint: 'Document title',
                onSubmitted: (_) => _commitDocumentTitle(),
              ),
            ),
          ),
        ),
      );
    }

    final canRename =
        !_collaborationReadOnly && widget.onProjectNameChanged != null;
    return Semantics(
      button: canRename,
      label: canRename
          ? 'Rename document title: $_documentTitle'
          : _documentTitle,
      hint: canRename ? 'Double tap to edit document title' : null,
      child: GestureDetector(
        key: const ValueKey('canvas-document-title-target'),
        behavior: HitTestBehavior.opaque,
        onTap: canRename ? _startDocumentTitleEdit : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppControlSize.minimumHitTarget,
            maxWidth: 260,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Text(
              _documentTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: tokens.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _startDocumentTitleEdit() {
    if (_collaborationReadOnly ||
        _editingDocumentTitle ||
        widget.onProjectNameChanged == null) {
      return;
    }
    _documentTitleController.text = _documentTitle;
    _documentTitleController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _documentTitleController.text.length,
    );
    setState(() => _editingDocumentTitle = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_editingDocumentTitle) return;
      _documentTitleFocusNode.requestFocus();
      _documentTitleController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _documentTitleController.text.length,
      );
    });
  }

  void _cancelDocumentTitleEdit() {
    if (!_editingDocumentTitle) return;
    _documentTitleController.text = _documentTitle;
    setState(() => _editingDocumentTitle = false);
  }

  Future<void> _commitDocumentTitle() async {
    if (!_editingDocumentTitle || _documentTitleCommitInProgress) return;
    final nextTitle = _documentTitleController.text.trim();
    if (nextTitle.isEmpty) {
      _cancelDocumentTitleEdit();
      return;
    }
    if (nextTitle == _documentTitle) {
      _cancelDocumentTitleEdit();
      return;
    }
    final callback = widget.onProjectNameChanged;
    if (callback == null) {
      _cancelDocumentTitleEdit();
      return;
    }

    final previousTitle = _documentTitle;
    setState(() => _documentTitleCommitInProgress = true);
    try {
      final saved = await callback(nextTitle);
      if (!mounted) return;
      if (!saved) {
        setState(() {
          _documentTitleController.text = previousTitle;
          _editingDocumentTitle = false;
          _documentTitleCommitInProgress = false;
        });
        return;
      }
      await ref
          .read(openDocumentTabsProvider.notifier)
          .rename(widget.projectId, nextTitle);
      if (!mounted) return;
      setState(() {
        _documentTitle = nextTitle;
        _documentTitleController.text = nextTitle;
        _editingDocumentTitle = false;
        _documentTitleCommitInProgress = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _documentTitleController.text = previousTitle;
        _editingDocumentTitle = false;
        _documentTitleCommitInProgress = false;
      });
      showUiToast(
        context,
        'Document title could not be saved.',
        variant: UiToastVariant.error,
      );
      debugPrint('[CanvasEditorSurface] Document title rename failed: $error');
    }
  }

  void _initCollaboration() {
    final displayName = _effectiveCollaborationDisplayName();
    final controller = ref.read(
      collaborationSessionProvider(widget.projectId).notifier,
    );
    _collaborationSession = controller;
    unawaited(
      controller.start(
        initialDocument: _currentCanvasDocument(),
        userId: _localUserId,
        userName: displayName,
        userColor: AppTheme.braunOrange,
        initialComments: ref.read(
          collaborationCommentsProvider(_projectionScope),
        ),
        role: widget.collaborationRole ?? CollaborationRole.viewer,
        readOnly: widget.readOnly,
      ),
    );
  }

  String _effectiveCollaborationDisplayName() {
    final sessionName = _collaborationSession?.localUserName?.trim();
    if (sessionName != null && sessionName.isNotEmpty) return sessionName;
    final cfg = ref.read(backendConfigProvider);
    final client = ref.read(supabaseClientProvider);
    final accountId =
        client?.auth.currentUser?.id ?? client?.auth.currentSession?.user.id;
    return CollaborationDisplayNameGenerator.resolve(
      stableId: accountId ?? _localUserId,
      preferredName: cfg.currentUserName,
    );
  }

  void _setUnresolvedCommentsOnly(bool value) {
    if (_showUnresolvedCommentsOnly != value && mounted) {
      setState(() => _showUnresolvedCommentsOnly = value);
    }
    _commentFilterPreferenceLoaded = true;
    final notifier = ref.read(
      commentNotificationsProvider(_commentNotificationScope).notifier,
    );
    unawaited(() async {
      await notifier.ready;
      if (!mounted) return;
      final current = ref.read(
        commentNotificationsProvider(_commentNotificationScope),
      );
      await notifier.setPreferences(
        current.preferences.copyWith(unresolvedOnly: value),
      );
    }());
  }

  void _focusCommentFromNotification(CommentNotification notification) {
    CanvasComment? target;
    for (final comment in ref.read(
      collaborationCommentsProvider(_projectionScope),
    )) {
      if (comment.id == notification.commentId) {
        target = comment;
        break;
      }
    }
    if (target == null) {
      if (mounted) showUiToast(context, 'Komentar sudah tidak tersedia.');
      return;
    }
    CanvasNode? anchor;
    for (final node in ref.read(documentNodesProvider)) {
      if (node.id == target.nodeId) {
        anchor = node;
        break;
      }
    }
    final bounds = anchor?.bounds ?? Rect.fromLTWH(target.x, target.y, 1, 1);
    ref
        .read(viewportProvider.notifier)
        .panToNodeCenter(bounds, MediaQuery.sizeOf(context));
    if (mounted) setState(() => _focusedCommentId = target!.id);
  }

  void _persistComment(CanvasComment comment) {
    if (!_collaborationCanComment) return;
    final session = _collaborationSession;
    if (session != null) {
      session.upsertComment(comment);
      return;
    }
    final sync = ref.read(supabaseSyncServiceProvider);
    if (sync.isConfigured) {
      unawaited(sync.syncComment(comment, widget.projectId));
    }
  }

  void _updateCommentMetadata(CanvasComment previous, CanvasComment updated) {
    if (!_collaborationCanComment || previous.id != updated.id) return;
    final session = _collaborationSession;
    if (session != null) {
      session.upsertComment(updated);
      return;
    }
    ref
        .read(collaborationCommentsProvider(_projectionScope).notifier)
        .upsertComment(updated);
    _persistComment(updated);
  }

  Future<CommentAttachment?> _pickCommentAttachment(
    CanvasComment comment,
  ) async {
    if (!_collaborationCanComment) return null;
    final sync = ref.read(supabaseSyncServiceProvider);
    final result = await AssetService(
      sync,
    ).pickAnyFile(projectId: widget.projectId);
    if (result == null) return null;
    return CommentAttachment(
      id: const Uuid().v4(),
      name: result.name,
      mimeType: inferAssetMimeType(result.name),
      sizeBytes: result.size ?? result.bytes?.lengthInBytes ?? 0,
      assetId: result.remoteUrl,
      uri: result.remoteUrl ?? result.path,
      createdAt: DateTime.now(),
    );
  }

  void _scheduleSemanticIndexRebuild() {
    _semanticIndexSyncTimer?.cancel();
    _semanticIndexSyncTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_rebuildSemanticIndex()),
    );
  }

  Future<void> _rebuildSemanticIndex() async {
    if (_semanticIndexSyncInFlight) {
      _semanticIndexSyncQueued = true;
      return;
    }
    _semanticIndexSyncInFlight = true;
    try {
      final storage = ref.read(localStorageServiceProvider);
      final loaded = await Future.wait<Object>([
        storage.loadVersions(widget.projectId),
        storage.loadAutoCheckpoints(widget.projectId),
        storage.loadAIJobHistory(widget.projectId),
      ]);
      if (!mounted) return;

      final versions = <DocumentSnapshotRecord>[
        ...ref.read(boardHistoryProvider).snapshots,
        ...(loaded[0] as List<DocumentSnapshotRecord>),
        ...(loaded[1] as List<DocumentSnapshotRecord>),
      ];
      final currentJobs = ref.read(aiCreativeEngineProvider).jobs;
      final persistedJobs = loaded[2] as List<AIJob>;
      final records = SemanticIndexSources.fromCanvas(
        nodes: ref.read(documentNodesProvider),
        assets: ref.read(documentAssetsProvider).items,
        comments: ref.read(commentsProvider),
        versions: versions,
        jobs: [...persistedJobs, ...currentJobs],
        indexedAt: DateTime.now().toUtc(),
      );
      final indexNotifier = ref.read(
        semanticIndexProvider(widget.projectId).notifier,
      );
      await indexNotifier.ready;
      if (!mounted) return;
      await indexNotifier.replaceAll(records);
    } catch (error) {
      debugPrint('[CanvasEditorSurface] Semantic index rebuild failed: $error');
    } finally {
      _semanticIndexSyncInFlight = false;
      if (_semanticIndexSyncQueued) {
        _semanticIndexSyncQueued = false;
        if (mounted) _scheduleSemanticIndexRebuild();
      }
    }
  }

  void _syncDrawingPaperPreviews(List<CanvasNode> nodes) {
    for (final node in nodes) {
      final payload = node.payload;
      if (payload is! DrawingPaperPayload) continue;
      _prepareDrawingPaperPreview(node, payload);
    }
  }

  void _prepareDrawingPaperPreview(
    CanvasNode node,
    DrawingPaperPayload payload,
  ) {
    final reference = DrawingPaperPersistence.previewReferenceForPayload(
      payload,
      nodeId: node.id,
    );
    if (_imageCache.getImage(reference) != null) return;
    final operationGeneration = _artifactOperationGeneration;
    final previousGeneration = _drawingPaperPreviewLoads[reference];
    if (previousGeneration != null &&
        previousGeneration == operationGeneration) {
      return;
    }
    _drawingPaperPreviewLoads[reference] = operationGeneration;
    final projectId = widget.projectId;
    final accountId = ref.read(supabaseSyncServiceProvider).currentUserId;

    unawaited(() async {
      try {
        final prepared = await _drawingPaperPersistence.preparePayload(
          payload,
          nodeId: node.id,
        );
        if (!_isArtifactOperationCurrent(
              generation: operationGeneration,
              projectId: projectId,
              accountId: accountId,
            ) ||
            prepared.compositePreviewRef != reference) {
          return;
        }
        final bytes = await _drawingPaperPersistence.readPreview(prepared);
        if (!_isArtifactOperationCurrent(
          generation: operationGeneration,
          projectId: projectId,
          accountId: accountId,
        )) {
          return;
        }
        if (bytes != null && bytes.isNotEmpty) {
          await _imageCache.decodeAndCacheBytes(reference, bytes);
        }
      } finally {
        if (_drawingPaperPreviewLoads[reference] == operationGeneration) {
          _drawingPaperPreviewLoads.remove(reference);
        }
      }
    }());
  }

  void _onImageCacheUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @visibleForTesting
  CanvasImageCache get debugImageCache => _imageCache;

  List<String> _duplicateNodesAndTrackUsage(List<String> ids) {
    if (ids.isEmpty || _collaborationReadOnly) return const [];
    final nodesById = {
      for (final node in ref.read(documentNodesProvider)) node.id: node,
    };
    final sourceNodes = [for (final id in ids) ?nodesById[id]];
    final duplicatedBySource = ref
        .read(documentNodesProvider.notifier)
        .duplicateNodesWithMap(ids);
    _recordDuplicatedAssetUsage(sourceNodes, duplicatedBySource);
    return duplicatedBySource.values.toList(growable: false);
  }

  void _recordDuplicatedAssetUsage(
    Iterable<CanvasNode> sourceNodes,
    Map<String, String> duplicatedBySource,
  ) {
    final repository = ref.read(
      assetLibraryRepositoryProvider(widget.projectId),
    );
    for (final source in sourceNodes) {
      final libraryItemId = _libraryItemIdForNode(source);
      final duplicatedNodeId = duplicatedBySource[source.id];
      if (libraryItemId == null || duplicatedNodeId == null) continue;
      unawaited(
        repository.recordUsage(
          libraryItemId,
          projectId: widget.projectId,
          nodeId: duplicatedNodeId,
        ),
      );
    }
  }

  String? _libraryItemIdForNode(CanvasNode node) {
    final payload = node.payload;
    final assetId = switch (payload) {
      ImagePayload value => value.assetId,
      FilePayload value => value.assetId,
      VideoPayload value => value.assetId,
      AudioPayload value => value.assetId,
      Model3DPayload value => value.assetId,
      _ => null,
    };
    if (assetId == null || assetId.trim().isEmpty) return null;
    final metadata = ref.read(documentAssetsProvider)[assetId]?.metadata;
    final value = metadata?['libraryItemId']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  void _focusCreatedAiNode(CanvasNode node) {
    ref.read(selectionProvider.notifier).select(node.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final canvasSize = _canvasKey.currentContext?.size;
      if (canvasSize == null ||
          !canvasSize.width.isFinite ||
          !canvasSize.height.isFinite ||
          canvasSize.width <= 0 ||
          canvasSize.height <= 0) {
        return;
      }
      ref.read(viewportProvider.notifier).zoomToNode(node.bounds, canvasSize);
    });
  }

  void _trackVideoObjectUrls(List<CanvasNode> nodes) {
    if (!kIsWeb) return;
    for (final node in nodes) {
      final payload = node.payload;
      if (payload is VideoPayload) {
        final url = payload.videoUrl;
        if (payload.videoArtifactReference?.isNotEmpty == true &&
            url?.startsWith('blob:') == true) {
          _ownedVideoObjectUrls.add(url!);
        }
      }
    }
  }

  void _disposeVideoObjectUrls() {
    if (!kIsWeb) return;
    for (final url in _ownedVideoObjectUrls) {
      unawaited(
        disposeHydratedVideoArtifact(
          VideoArtifact(url: url, fileName: 'generated-video.mp4'),
        ),
      );
    }
    _ownedVideoObjectUrls.clear();
  }

  @override
  void dispose() {
    _artifactOperationGeneration++;
    if (!_collaborationReadOnly && widget.services.enableAutosave) {
      final autosaveController = _autosaveController;
      if (autosaveController != null) {
        unawaited(
          autosaveController.saveImmediately(
            syncCloud: widget.services.enableCloudSync,
          ),
        );
      }
    }
    if (widget.services.trackVideoObjectUrls) _disposeVideoObjectUrls();
    _chartTapTimer?.cancel();
    _semanticIndexSyncTimer?.cancel();
    _imageCache.removeListener(_onImageCacheUpdate);
    _imageCache.dispose();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _panelController.removeListener(_onPanelControllerChanged);
    if (_ownsPanelController) _panelController.dispose();
    _documentTitleController.dispose();
    _documentTitleFocusNode.dispose();
    _editController.dispose();
    _editFocusNode.dispose();
    _aiPromptFocusNode.dispose();
    _exportQueue.dispose();
    super.dispose();
  }

  void _moveNodeByDelta(CanvasNode node, Offset delta, double zoom) {
    final current = ref
        .read(documentNodesProvider)
        .firstWhere((candidate) => candidate.id == node.id, orElse: () => node);
    ref
        .read(documentNodesProvider.notifier)
        .updateNode(
          current.copyWith(
            x: current.x + delta.dx / zoom,
            y: current.y + delta.dy / zoom,
          ),
        );
  }

  void _saveMermaidRenderState(CanvasNode node, MermaidPayload rendered) {
    final current = ref
        .read(documentNodesProvider)
        .where((candidate) => candidate.id == node.id)
        .firstOrNull;
    if (current == null || current.payload is! MermaidPayload) return;

    final currentPayload = current.payload as MermaidPayload;
    if (currentPayload.renderMode != MermaidRenderMode.sourcePreview ||
        rendered.renderMode != MermaidRenderMode.sourcePreview ||
        currentPayload.sourceRevision != rendered.sourceRevision ||
        currentPayload.source != rendered.source ||
        currentPayload.theme != rendered.theme ||
        currentPayload.direction != rendered.direction ||
        jsonEncode(currentPayload.config) != jsonEncode(rendered.config)) {
      return;
    }
    ref
        .read(documentNodesProvider.notifier)
        .updateDerivedNode(current.copyWith(payload: rendered));
  }

  Future<void> _openMermaidEditor(CanvasNode node) async {
    if (_collaborationReadOnly || node.payload is! MermaidPayload) return;
    await showUiDialog<void>(
      context: context,
      builder: (_) => MermaidEditorDialog(
        node: node,
        readOnly: _collaborationReadOnly,
        onSave: (updatedPayload) {
          if (_collaborationReadOnly) return;
          final current = ref
              .read(documentNodesProvider)
              .where((candidate) => candidate.id == node.id)
              .firstOrNull;
          if (current == null || current.payload is! MermaidPayload) return;
          ref
              .read(documentNodesProvider.notifier)
              .updateMermaidSource(current.id, updatedPayload);
        },
      ),
    );
  }

  Future<void> _openChartDataEditor(CanvasNode node) async {
    if (_collaborationReadOnly || node.payload is! ChartPayload) return;
    final payload = node.payload as ChartPayload;
    final sourceId = payload.tableSourceNodeId;
    if (sourceId != null) {
      final source = ref
          .read(documentNodesProvider)
          .where((candidate) => candidate.id == sourceId)
          .firstOrNull;
      if (source?.payload is TablePayload) {
        await TableMatrixEditorModal.show(
          context,
          node: source!,
          onUpdate: (updatedNode) {
            if (_collaborationReadOnly) return;
            ref.read(documentNodesProvider.notifier).updateNode(updatedNode);
          },
        );
        return;
      }
    }
    await showUiDialog<void>(
      context: context,
      builder: (_) => ChartDataEditorDialog(
        payload: node.payload as ChartPayload,
        readOnly: _collaborationReadOnly,
        onSave: (updatedPayload) {
          if (_collaborationReadOnly) return;
          final current = ref
              .read(documentNodesProvider)
              .where((candidate) => candidate.id == node.id)
              .firstOrNull;
          if (current == null || current.payload is! ChartPayload) return;
          ref
              .read(documentNodesProvider.notifier)
              .updateNode(current.copyWith(payload: updatedPayload));
        },
      ),
    );
  }

  CanvasNode? _mermaidSourceForNode(CanvasNode node) {
    final nodes = ref.read(documentNodesProvider);
    for (final candidate in nodes) {
      if (candidate.type != NodeType.mermaid ||
          candidate.payload is! MermaidPayload) {
        continue;
      }
      final payload = candidate.payload as MermaidPayload;
      if (candidate.id == node.id || payload.nativeNodeIds.contains(node.id)) {
        return candidate;
      }
    }
    return null;
  }

  void _showMermaidConversionResult(MermaidConversionResult result) {
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

  Future<void> _runMermaidConversion(
    CanvasNode source, {
    required bool regenerate,
  }) async {
    final notifier = ref.read(documentNodesProvider.notifier);
    final result = regenerate
        ? await notifier.regenerateMermaidNodeAsync(source.id)
        : await notifier.convertMermaidNodeAsync(source.id);
    if (mounted) _showMermaidConversionResult(result);
  }

  List<Widget> _buildCanvasNodeLayers({
    required List<CanvasNode> nodes,
    required Set<String> selectedIds,
    required canvas_model.Viewport viewport,
    required Size viewportSize,
    required CanvasRenderTokens renderTokens,
    required DesignTokenSet designTokens,
  }) {
    if (!identical(_indexedNodes, nodes)) {
      _canvasSpatialIndex = CanvasSpatialIndex.build(nodes);
      _indexedNodes = nodes;
    }
    final worldWidth = viewportSize.width / viewport.zoom;
    final worldHeight = viewportSize.height / viewport.zoom;
    const cullingMargin = 640.0;
    final visibleWorldRect = Rect.fromLTWH(
      viewport.x - cullingMargin,
      viewport.y - cullingMargin,
      worldWidth + cullingMargin * 2,
      worldHeight + cullingMargin * 2,
    );
    final candidateNodes =
        _canvasSpatialIndex?.query(visibleWorldRect) ?? nodes;
    final candidateIds = candidateNodes.map((node) => node.id).toSet()
      ..addAll(selectedIds);
    final renderedNodes = nodes
        .where((node) => candidateIds.contains(node.id))
        .toList(growable: false);
    final nodeMap = {for (final node in nodes) node.id: node};
    final orderedNodes = renderedNodes.where((node) => node.visible).toList()
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));

    String? liveAudioId;
    for (final node in renderedNodes) {
      if (node.visible && node.type == NodeType.audioCard) {
        liveAudioId = node.id;
        break;
      }
    }

    String? liveVideoId;
    for (final node in nodes) {
      if (node.visible &&
          node.type == NodeType.videoCard &&
          selectedIds.contains(node.id)) {
        liveVideoId = node.id;
        break;
      }
    }

    return [
      for (final node in orderedNodes)
        _buildCanvasNodeLayer(
          node: node,
          selected: selectedIds.contains(node.id),
          viewport: viewport,
          renderTokens: renderTokens,
          designTokens: designTokens,
          clipParent: _clipParentFor(node, nodeMap),
          useLiveAudio: node.id == liveAudioId,
          useLiveVideo: node.id == liveVideoId,
        ),
    ];
  }

  CanvasNode? _clipParentFor(CanvasNode node, Map<String, CanvasNode> nodeMap) {
    final parent = node.parentId == null ? null : nodeMap[node.parentId];
    if (parent == null ||
        parent.type != NodeType.frame ||
        parent.payload is! FramePayload) {
      return null;
    }
    return (parent.payload as FramePayload).clipContent ? parent : null;
  }

  ChartPayload _resolvedChartPayload(ChartPayload payload) {
    final sourceId = payload.tableSourceNodeId;
    if (sourceId == null) return payload.filteredByCategory();
    final source = ref
        .read(documentNodesProvider)
        .where((candidate) => candidate.id == sourceId)
        .firstOrNull;
    if (source?.payload is! TablePayload) return payload.filteredByCategory();
    return payload
        .resolvedFromTable(source!.payload as TablePayload)
        .filteredByCategory();
  }

  void _cacheChartRemoteData(CanvasNode node, ChartPayload remote) {
    if (_collaborationReadOnly) return;
    final current = ref
        .read(documentNodesProvider)
        .where((candidate) => candidate.id == node.id)
        .firstOrNull;
    if (current?.payload is! ChartPayload) return;
    final currentPayload = current!.payload as ChartPayload;
    final updated = current.copyWith(
      payload: currentPayload.copyWith(
        categories: remote.categories,
        series: remote.series,
      ),
    );
    if (updated.toJson().toString() == current.toJson().toString()) return;
    ref.read(documentNodesProvider.notifier).updateDerivedNode(updated);
  }

  void _handleChartCategoryTap(CanvasNode node, String category) {
    if (_collaborationReadOnly || category.trim().isEmpty) return;
    _chartTapTimer?.cancel();
    _chartTapTimer = Timer(const Duration(milliseconds: 240), () {
      if (!mounted) return;
      final current = ref
          .read(documentNodesProvider)
          .where((candidate) => candidate.id == node.id)
          .firstOrNull;
      if (current?.payload is! ChartPayload) return;
      final payload = current!.payload as ChartPayload;
      final nextFilter = payload.categoryFilter == category ? '' : category;
      ref.read(selectionProvider.notifier).select(node.id);
      ref
          .read(documentNodesProvider.notifier)
          .updateNode(
            current.copyWith(
              payload: payload.copyWith(categoryFilter: nextFilter),
            ),
          );
    });
  }

  String? _chartCategoryAt(CanvasNode node, Offset localPosition) {
    final rawPayload = node.payload;
    if (rawPayload is! ChartPayload) return null;
    final payload = _resolvedChartPayload(rawPayload);
    final zoom = ref.read(viewportProvider).zoom;
    return ChartCanvasCategoryHitTester.categoryAt(
      payload: payload,
      size: Size(node.width * zoom, node.height * zoom),
      localPosition: localPosition,
    );
  }

  Widget _buildCanvasNodeLayer({
    required CanvasNode node,
    required bool selected,
    required canvas_model.Viewport viewport,
    required CanvasRenderTokens renderTokens,
    required DesignTokenSet designTokens,
    required CanvasNode? clipParent,
    required bool useLiveAudio,
    required bool useLiveVideo,
  }) {
    final screenPos = ref
        .read(viewportProvider.notifier)
        .toScreen(Offset(node.x, node.y));
    final payload = node.payload;
    final renderNode = node.type == NodeType.chart && payload is ChartPayload
        ? node.copyWith(payload: _resolvedChartPayload(payload))
        : node;
    final nodeToPaint =
        renderNode.id == _editingNodeId && renderNode.payload is ShapePayload
        ? renderNode.copyWith(
            payload: (renderNode.payload as ShapePayload).copyWith(label: ''),
          )
        : renderNode;
    late final Widget child;

    if (node.type == NodeType.linkCard && payload is LinkPayload) {
      child = IgnorePointer(
        ignoring: !selected || _collaborationReadOnly,
        child: Transform.rotate(
          angle: node.rotation,
          child: Opacity(
            opacity: node.opacity,
            child: LinkCardWidget(
              node: node,
              selected: selected,
              onSubmitUrl: (url) => _submitLinkUrl(node, url),
              onRefresh: () => ref
                  .read(linkPreviewControllerProvider.notifier)
                  .refresh(node),
              onOpenInApp: () => _openLinkInApp(node),
              onOpenExternal: () => _openLinkExternal(node),
              onDragDelta: (delta) =>
                  _moveNodeByDelta(node, delta, viewport.zoom),
              onSecondaryTap: (screenPosition) => _showNodeContextMenu(
                screenPosition,
                node,
                Offset(node.x, node.y),
              ),
            ),
          ),
        ),
      );
    } else if (node.type == NodeType.audioCard &&
        payload is AudioPayload &&
        useLiveAudio) {
      final audioCard = IgnorePointer(
        ignoring: _collaborationReadOnly,
        child: Transform.rotate(
          angle: node.rotation,
          child: Opacity(
            opacity: node.opacity,
            child: InlineAudioCardWidget(
              sourcePath: payload.audioPath,
              networkUrl: payload.audioUrl,
              storagePath: payload.storagePath,
              audioArtifactReference: payload.audioArtifactReference,
              sourceResolver: _mediaSourceResolver,
              title: payload.trackName,
              artist: payload.artist,
              description: payload.description,
              durationText: payload.durationText,
              looping: payload.isLooping,
              playbackSpeed: payload.playbackSpeed,
              timeline: payload.mediaTimeline,
              onOpenPlayer: () => _openAudioPlayer(node),
              onTap: () => ref.read(selectionProvider.notifier).select(node.id),
              onDragDelta: (delta) =>
                  _moveNodeByDelta(node, delta, viewport.zoom),
              onSecondaryTap: () => _showNodeContextMenu(
                Offset(screenPos.dx, screenPos.dy),
                node,
                Offset(node.x, node.y),
              ),
            ),
          ),
        ),
      );
      child = Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: audioCard),
          if (payload.description.trim().isNotEmpty)
            Positioned(
              left: 8,
              top: node.height * viewport.zoom + 5,
              width: (node.width - 16) * viewport.zoom,
              child: IgnorePointer(
                child: Text(
                  payload.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 11,
                  ),
                ),
              ),
            ),
        ],
      );
    } else if (node.type == NodeType.model3d && payload is Model3DPayload) {
      child = Transform.rotate(
        angle: node.rotation,
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: node.width,
            height: node.height,
            child: Opacity(
              opacity: node.opacity,
              child: Model3DNodeWidget(
                artifactStore: _model3DArtifactStore,
                payload: payload,
                readOnly: _collaborationReadOnly,
                canMove: !_collaborationReadOnly && selected,
                selected: selected,
                interactive: selected,
                width: node.width,
                height: node.height,
                resetCommand: _model3DResetCommands[node.id] ?? 0,
                retryCommand: _model3DRetryCommands[node.id] ?? 0,
                canvasColor: renderTokens.canvas,
                panelColor: renderTokens.canvas,
                borderColor: selected
                    ? renderTokens.accent
                    : renderTokens.textMuted.withValues(alpha: 0.45),
                textColor: renderTokens.text,
                mutedColor: renderTokens.textMuted,
                onSelect: () =>
                    ref.read(selectionProvider.notifier).select(node.id),
                onAutoRotateChanged: _collaborationReadOnly
                    ? null
                    : (value) => _setModel3DAutoRotate(node, value),
                onCameraBookmarkCaptured: _collaborationReadOnly
                    ? null
                    : (bookmark) => _captureModel3DCamera(node, bookmark),
                onSnapshotCaptured: _collaborationReadOnly
                    ? null
                    : (bytes, width, height) =>
                          _captureModel3DSnapshot(node, bytes, width, height),
                // The header receives deltas in the logical node space after
                // the viewport transform, so it is already in world units.
                onDragDelta: (delta) => _moveNodeByDelta(node, delta, 1.0),
                onSecondaryTap: (globalPosition) =>
                    _showModel3DContextMenu(globalPosition, node),
              ),
            ),
          ),
        ),
      );
    } else if (node.type == NodeType.mermaid && payload is MermaidPayload) {
      child = Transform.rotate(
        angle: node.rotation,
        child: Opacity(
          opacity: node.opacity,
          child: MermaidNodePreview(
            key: ValueKey('mermaid-preview-${node.id}'),
            payload: payload,
            onRenderStateChanged: (rendered) =>
                _saveMermaidRenderState(node, rendered),
          ),
        ),
      );
    } else if (node.type == NodeType.embed && payload is EmbedPayload) {
      child = Transform.rotate(
        angle: node.rotation,
        child: Opacity(
          opacity: node.opacity,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _collaborationReadOnly
                ? null
                : () {
                    ref.read(selectionProvider.notifier).select(node.id);
                    if (payload.url.trim().isNotEmpty) {
                      _openEmbed(node);
                    }
                  },
            onPanUpdate: _collaborationReadOnly
                ? null
                : (details) =>
                      _moveNodeByDelta(node, details.delta, viewport.zoom),
            onSecondaryTapUp: _collaborationReadOnly
                ? null
                : (details) {
                    ref.read(selectionProvider.notifier).select(node.id);
                    _showNodeContextMenu(
                      details.globalPosition,
                      node,
                      Offset(node.x, node.y),
                    );
                  },
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (payload.thumbnailUrl?.trim().isNotEmpty == true)
                  Image.network(
                    payload.thumbnailUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                Container(color: renderTokens.canvas),
                Center(
                  child: Icon(
                    payload.url.trim().isEmpty
                        ? Icons.link_off
                        : Icons.play_circle_fill,
                    color: renderTokens.accent,
                    size: 42,
                  ),
                ),
                Positioned(
                  left: 12,
                  top: 10,
                  right: 12,
                  child: Text(
                    '${payload.provider} Embed',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: renderTokens.warning,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 10,
                  child: Text(
                    payload.title?.trim().isNotEmpty == true
                        ? payload.title!
                        : (payload.url.isEmpty ? 'Set embed URL' : payload.url),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: renderTokens.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else if (node.type == NodeType.mapCard && payload is MapPayload) {
      child = Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _collaborationReadOnly
            ? null
            : (event) {
                ref.read(selectionProvider.notifier).select(node.id);
                if (event.buttons == kSecondaryMouseButton) {
                  _showNodeContextMenu(
                    event.position,
                    node,
                    Offset(node.x, node.y),
                  );
                }
              },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _collaborationReadOnly
              ? null
              : () => ref.read(selectionProvider.notifier).select(node.id),
          onPanStart: _collaborationReadOnly
              ? null
              : (_) => ref.read(selectionProvider.notifier).select(node.id),
          onPanUpdate: _collaborationReadOnly
              ? null
              : (details) =>
                    _moveNodeByDelta(node, details.delta, viewport.zoom),
          child: Transform.rotate(
            angle: node.rotation,
            child: Opacity(
              opacity: node.opacity,
              child: MapLocationPreview(payload: payload),
            ),
          ),
        ),
      );
    } else if (node.type == NodeType.videoCard &&
        payload is VideoPayload &&
        useLiveVideo) {
      final videoCard = IgnorePointer(
        ignoring: _collaborationReadOnly,
        child: Transform.rotate(
          angle: node.rotation,
          child: Opacity(
            opacity: node.opacity,
            child: InlineVideoCardWidget(
              sourcePath: payload.videoPath ?? '',
              networkUrl: payload.videoUrl,
              storagePath: payload.storagePath,
              artifactReference: payload.videoArtifactReference,
              sourceResolver: _mediaSourceResolver,
              onOpenPlayer: () => _openVideoPlayer(node),
              onDownload: () => _downloadVideo(node),
              caption: payload.caption,
              posterPath: payload.posterPath,
              timeline: payload.mediaTimeline,
              onDragDelta: (delta) =>
                  _moveNodeByDelta(node, delta, viewport.zoom),
              onSecondaryTap: (screenPosition) => _showNodeContextMenu(
                screenPosition,
                node,
                Offset(node.x, node.y),
              ),
            ),
          ),
        ),
      );
      child = Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: videoCard),
          if (payload.caption?.trim().isNotEmpty == true)
            Positioned(
              left: 0,
              top: node.height * viewport.zoom,
              width: node.width * viewport.zoom,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: IgnorePointer(
                  child: Text(
                    payload.caption!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFE2E8F0),
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    } else if (node.type == NodeType.chart && payload is ChartPayload) {
      child = Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          _chartPointerNodeId = node.id;
          _chartPointerDownPosition = event.localPosition;
          _chartPointerMoved = false;
        },
        onPointerMove: (event) {
          if (_chartPointerNodeId == node.id &&
              _chartPointerDownPosition != null &&
              (event.localPosition - _chartPointerDownPosition!).distance > 8) {
            _chartPointerMoved = true;
          }
        },
        onPointerUp: (event) {
          if (_chartPointerNodeId == node.id &&
              !_chartPointerMoved &&
              ref.read(activeToolProvider) == CanvasTool.select) {
            final category = _chartCategoryAt(node, event.localPosition);
            if (category != null) _handleChartCategoryTap(node, category);
          }
          if (_chartPointerNodeId == node.id) {
            _chartPointerNodeId = null;
            _chartPointerDownPosition = null;
            _chartPointerMoved = false;
          }
        },
        onPointerCancel: (_) {
          if (_chartPointerNodeId == node.id) {
            _chartPointerNodeId = null;
            _chartPointerDownPosition = null;
            _chartPointerMoved = false;
          }
        },
        child: IgnorePointer(
          child: Transform.rotate(
            angle: node.rotation,
            child: Opacity(
              opacity: node.opacity,
              child: ChartNodeWidget(
                key: ValueKey('chart-node-widget-${node.id}'),
                payload: nodeToPaint.payload as ChartPayload,
                databaseAdapter: SupabaseChartDatabaseAdapter(
                  ref.read(supabaseClientProvider),
                ),
                onResolvedPayload: (remote) =>
                    _cacheChartRemoteData(node, remote),
              ),
            ),
          ),
        ),
      );
    } else {
      child = IgnorePointer(
        child: CustomPaint(
          size: Size(node.width, node.height),
          painter: _CanvasNodeLayerPainter(
            node: nodeToPaint,
            clipParent: clipParent,
            renderTokens: renderTokens,
            designTokens: designTokens,
            zoom: viewport.zoom,
            imageCache: _imageCache,
          ),
        ),
      );
    }

    return Positioned(
      key: ValueKey('canvas-node-layer-${node.id}'),
      left: screenPos.dx,
      top: screenPos.dy,
      width: node.width * viewport.zoom,
      height: node.height * viewport.zoom,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.services.enableCollaboration) {
      ref.watch(collaborationSessionProvider(widget.projectId));
    }
    if (!_collaborationReadOnly && widget.services.enableAutosave) {
      _autosaveController = ref.watch(autosaveControllerProvider);
    }
    final viewport = ref.watch(viewportProvider);
    final allNodes = ref.watch(documentNodesProvider);
    final nodes = CanvasNavigationMath.nodesForPage(
      allNodes,
      _navigationLoaded ? _navigationState.activePageId : null,
    );
    if (widget.services.trackVideoObjectUrls) _trackVideoObjectUrls(nodes);
    final allEdges = ref.watch(documentEdgesProvider);
    final visibleNodeIds = nodes.map((node) => node.id).toSet();
    final edges = allEdges
        .where(
          (edge) =>
              (edge.sourceNodeId == null ||
                  visibleNodeIds.contains(edge.sourceNodeId)) &&
              (edge.targetNodeId == null ||
                  visibleNodeIds.contains(edge.targetNodeId)),
        )
        .toList(growable: false);
    final allComments = ref.watch(
      collaborationCommentsProvider(_projectionScope),
    );
    final comments = _showUnresolvedCommentsOnly
        ? allComments
              .where((comment) => !comment.resolved)
              .toList(growable: false)
        : allComments;
    final selectedIds = ref.watch(selectionProvider);
    final activeTool = ref.watch(activeToolProvider);
    final activeDiagramShape = ref.watch(activeDiagramShapeProvider);
    final brushConfig = ref.watch(activeBrushConfigProvider);
    final history = ref.watch(historyProvider);
    final precision = ref.watch(canvasPrecisionProvider(widget.projectId));
    final themeMode = ref.watch(themeModeProvider);
    final panelPreferences = ref.watch(canvasPanelPreferencesProvider);
    final tokens = context.appTokens;
    final designTokens = ref.watch(designTokenSetProvider);
    final focusMode = _navigationState.focusMode;
    final compactHeader = AppResponsive.isNarrow(context);
    final expandedHeader =
        MediaQuery.sizeOf(context).width >= AppBreakpoints.expanded;
    final detailedHeader =
        MediaQuery.sizeOf(context).width >= AppBreakpoints.ultraWide;
    final condensedHeader = MediaQuery.sizeOf(context).height < 480;
    final headerWidth = MediaQuery.sizeOf(context).width;
    final compactActionKeys = <Key>{
      if (headerWidth >= AppBreakpoints.compact)
        ValueKey(
          widget.onOpenProjectLibrary == null
              ? 'canvas-return-to-dashboard'
              : 'canvas-open-library',
        ),
      const ValueKey('canvas-search'),
      if (!_collaborationReadOnly &&
          headerWidth >= AppBreakpoints.compactStatusTabs) ...[
        const ValueKey('canvas-undo'),
        const ValueKey('canvas-redo'),
      ],
      if (headerWidth >= AppBreakpoints.medium) ...[
        const ValueKey('canvas-zoom-out'),
        const ValueKey('canvas-zoom-level'),
        const ValueKey('canvas-zoom-in'),
      ] else
        const ValueKey('canvas-zoom-menu'),
      if (panelPreferences.showLayersButton)
        const ValueKey('canvas-panel-toggle-layers'),
      if (!_collaborationReadOnly && panelPreferences.showInspectorButton)
        const ValueKey('canvas-panel-toggle-inspector'),
      if (headerWidth >= AppBreakpoints.expanded)
        const ValueKey('canvas-settings-menu'),
    };
    final commentThreads = <String, List<CanvasComment>>{};
    for (final comment in comments) {
      commentThreads
          .putIfAbsent(comment.feedbackThreadKey, () => [])
          .add(comment);
    }
    final orderedCommentThreads = commentThreads.values.toList();

    (Offset, Offset)? liveConnectorPreview;
    if (_connectorSourceNodeId != null && _mouseWorldPos != null) {
      final match = nodes.where((n) => n.id == _connectorSourceNodeId).toList();
      if (match.isNotEmpty) {
        liveConnectorPreview = (match.first.bounds.center, _mouseWorldPos!);
      }
    }

    return Focus(
      autofocus: true,
      child: DropTarget(
        onDragDone: (detail) => _handleFileDrop(detail),
        child: UiPageScaffold(
          showHeader: widget.services.showProjectHeader && !focusMode,
          useCompactActionsMenu: true,
          compactActionsMenuAlways: true,
          overlayHeader: widget.services.showProjectHeader && !focusMode,
          compactActionKeys: compactActionKeys,
          leadingWidth:
              panelPreferences.showLayersButton &&
                  headerWidth >= AppBreakpoints.compact
              ? AppControlSize.regular * 2 + AppSpacing.sm * 3 + AppSpacing.xs
              : null,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              UiIconButton(
                key: ValueKey(
                  widget.onOpenProjectLibrary == null
                      ? 'canvas-return-to-dashboard'
                      : 'canvas-open-library',
                ),
                icon: widget.onOpenProjectLibrary == null
                    ? Icons.arrow_back
                    : Icons.folder_open_outlined,
                tooltip: widget.onOpenProjectLibrary == null
                    ? 'Back to Dashboard'
                    : 'Project Library',
                size: UiButtonSize.sm,
                onPressed: _returnToDashboard,
              ),
              if (panelPreferences.showLayersButton)
                UiIconButton(
                  key: const ValueKey('canvas-panel-toggle-layers'),
                  icon: Icons.layers_outlined,
                  tooltip: _showLayers
                      ? 'Hide Layers panel'
                      : 'Show Layers panel',
                  selected: _showLayers,
                  onPressed: () => _toggleLayersPanel(context),
                ),
            ],
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: compactHeader ? 160 : 260,
                  ),
                  child: _buildDocumentTitle(context, tokens),
                ),
              ),
              if (detailedHeader) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.chevron_right, size: 16, color: tokens.textMuted),
                const SizedBox(width: AppSpacing.xxs),
              ],
              if (MediaQuery.sizeOf(context).width >= AppBreakpoints.wide &&
                  !condensedHeader)
                DocumentBreadcrumbSwitcher(
                  activeProjectId: widget.projectId,
                  onCreateProject: widget.onCreateProject,
                  onSelectDocument: widget.onSelectDocument,
                  onCloseDocument: widget.onCloseDocument,
                ),
              if (_collaborationReadOnly && expandedHeader) ...[
                const SizedBox(width: AppSpacing.md - AppSpacing.xxs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.danger.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(
                      color: tokens.danger.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'READ-ONLY SHARED PREVIEW',
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: tokens.danger,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ] else if (expandedHeader) ...[
                const SizedBox(width: AppSpacing.md - AppSpacing.xxs),
                Consumer(
                  builder: (context, ref, _) {
                    final syncState = ref.watch(syncStatusProvider);
                    final isSynced = syncState.status == SyncStatus.synced;
                    final isSyncing = syncState.status == SyncStatus.syncing;
                    final isError = syncState.status == SyncStatus.error;
                    final isCloudPending =
                        syncState.status == SyncStatus.cloudPending;
                    final isLocalSaved =
                        syncState.status == SyncStatus.localSaved;
                    final isLocalDegraded =
                        syncState.status == SyncStatus.localDegraded;

                    final color = isSynced || isLocalSaved
                        ? tokens.success
                        : isLocalDegraded || isSyncing
                        ? tokens.warning
                        : isError || isCloudPending
                        ? tokens.danger
                        : tokens.textMuted;

                    final label = isSynced
                        ? 'CLOUD SYNCED'
                        : isSyncing
                        ? 'SYNCING...'
                        : isCloudPending
                        ? 'CLOUD PENDING'
                        : isError
                        ? 'LOCAL SAVE FAILED'
                        : isLocalDegraded
                        ? 'LOCAL DEGRADED'
                        : isLocalSaved
                        ? 'LOCAL SAVED'
                        : 'LOCAL ONLY';

                    return Tooltip(
                      message: isError
                          ? (syncState.errorMessage ?? 'Sync error')
                          : 'Status: $label',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs + AppSpacing.xxs,
                          vertical: AppSpacing.xxs,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                          border: Border.all(
                            color: color.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isSynced
                                  ? Icons.cloud_done_outlined
                                  : isSyncing
                                  ? Icons.cloud_sync_outlined
                                  : isError
                                  ? Icons.cloud_off_outlined
                                  : Icons.cloud_queue_outlined,
                              size: 12,
                              color: color,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              label,
                              style: Theme.of(context).textTheme.labelSmall!
                                  .copyWith(
                                    color: color,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                if (widget.services.enableCollaboration)
                  Consumer(
                    builder: (context, ref, _) {
                      final collaboration = ref.watch(
                        collaborationSessionProvider(widget.projectId),
                      );
                      final (
                        label,
                        color,
                        icon,
                      ) = switch (collaboration.connection) {
                        CollaborationConnectionState.live => (
                          'COLLAB LIVE',
                          tokens.success,
                          Icons.people_alt,
                        ),
                        CollaborationConnectionState.catchingUp => (
                          'CATCHING UP',
                          tokens.warning,
                          Icons.sync,
                        ),
                        CollaborationConnectionState.connecting => (
                          'CONNECTING',
                          tokens.warning,
                          Icons.sync,
                        ),
                        CollaborationConnectionState.offline => (
                          'OFFLINE QUEUED',
                          tokens.warning,
                          Icons.cloud_off,
                        ),
                        CollaborationConnectionState.error => (
                          'COLLAB ERROR',
                          tokens.danger,
                          Icons.error_outline,
                        ),
                        CollaborationConnectionState.disconnected => (
                          'COLLAB OFF',
                          tokens.textMuted,
                          Icons.people_outline,
                        ),
                      };
                      return Tooltip(
                        message: collaboration.errorMessage ?? label,
                        child: Container(
                          margin: const EdgeInsets.only(
                            left: AppSpacing.xs + AppSpacing.xxs,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs + AppSpacing.xxs,
                            vertical: AppSpacing.xxs,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: color.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 12, color: color),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                '$label · ${collaboration.participantCount}',
                                style: Theme.of(context).textTheme.labelSmall!
                                    .copyWith(
                                      color: color,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ],
          ),
          actions: [
            if (widget.onCreateProject != null)
              UiIconButton(
                key: const ValueKey('canvas-save-workspace'),
                icon: Icons.save_outlined,
                tooltip: 'Save as workspace',
                onPressed: () => unawaited(widget.onCreateProject!(context)),
              ),
            if (!_collaborationReadOnly) ...[
              UiIconButton(
                key: const ValueKey('canvas-undo'),
                tooltip: 'Undo (Ctrl+Z)',
                icon: Icons.undo,
                onPressed: history.canUndo
                    ? () => ref.read(documentNodesProvider.notifier).undo()
                    : null,
              ),
              UiIconButton(
                key: const ValueKey('canvas-redo'),
                tooltip: 'Redo (Ctrl+Y)',
                icon: Icons.redo,
                onPressed: history.canRedo
                    ? () => ref.read(documentNodesProvider.notifier).redo()
                    : null,
              ),
            ],
            const SizedBox(width: AppSpacing.sm),
            if (headerWidth < AppBreakpoints.medium)
              UiMenuButton<String>(
                key: const ValueKey('canvas-zoom-menu'),
                tooltip: 'Zoom controls',
                icon: Icons.zoom_in_outlined,
                items: const [
                  UiMenuAction(
                    value: 'zoom_out',
                    icon: Icons.zoom_out,
                    label: 'Zoom out',
                  ),
                  UiMenuAction(
                    value: 'zoom_reset',
                    icon: Icons.center_focus_weak_outlined,
                    label: 'Reset zoom to 100%',
                  ),
                  UiMenuAction(
                    value: 'zoom_in',
                    icon: Icons.zoom_in,
                    label: 'Zoom in',
                  ),
                ],
                onSelected: (choice) {
                  switch (choice) {
                    case 'zoom_out':
                      _adjustCanvasZoom(0.9);
                    case 'zoom_reset':
                      _resetCanvasZoom();
                    case 'zoom_in':
                      _adjustCanvasZoom(1.1);
                  }
                },
              )
            else ...[
              UiIconButton(
                key: const ValueKey('canvas-zoom-out'),
                tooltip: 'Zoom out',
                icon: Icons.remove,
                onPressed: () => _adjustCanvasZoom(0.9),
              ),
              GestureDetector(
                key: const ValueKey('canvas-zoom-level'),
                onDoubleTap: _resetCanvasZoom,
                child: Tooltip(
                  message: 'Zoom level. Double-click to reset to 100%',
                  child: UiBadge(
                    '${(viewport.zoom * 100).toInt()}%',
                    variant: UiBadgeVariant.secondary,
                  ),
                ),
              ),
              UiIconButton(
                key: const ValueKey('canvas-zoom-in'),
                tooltip: 'Zoom in',
                icon: Icons.add,
                onPressed: () => _adjustCanvasZoom(1.1),
              ),
            ],
            UiIconButton(
              key: const ValueKey('canvas-search'),
              tooltip: 'Search (Ctrl+F)',
              icon: Icons.search,
              onPressed: _openSearchDialog,
            ),
            CommentNotificationInboxButton(
              projectId: widget.projectId,
              userId: _commentNotificationUserId,
              onSelected: _focusCommentFromNotification,
            ),
            if (allComments.isNotEmpty)
              UiMenuButton<String>(
                buttonKey: const ValueKey('canvas-comment-filter'),
                tooltip: 'Filter komentar',
                icon: _showUnresolvedCommentsOnly
                    ? Icons.filter_alt
                    : Icons.filter_alt_outlined,
                items: [
                  UiMenuAction(
                    value: 'all',
                    icon: Icons.forum_outlined,
                    label: 'Semua komentar',
                    selected: !_showUnresolvedCommentsOnly,
                  ),
                  UiMenuAction(
                    value: 'unresolved',
                    icon: Icons.filter_alt_outlined,
                    label: 'Belum selesai',
                    selected: _showUnresolvedCommentsOnly,
                  ),
                ],
                onSelected: (value) =>
                    _setUnresolvedCommentsOnly(value == 'unresolved'),
              ),
            UiIconButton(
              tooltip: 'Collaboration members',
              icon: Icons.people_alt_outlined,
              onPressed: () => unawaited(
                showCollaboratorsPanel(context, projectId: widget.projectId),
              ),
            ),
            if (!_collaborationReadOnly) ...[
              Consumer(
                builder: (context, ref, _) {
                  final configuration = ref.watch(meetingConfigurationProvider);
                  if (!configuration.isAvailable) {
                    return const SizedBox.shrink();
                  }
                  final meetingState = ref.watch(
                    meetingControllerProvider(widget.projectId),
                  );
                  final active =
                      meetingState.status == MeetingStatus.connected ||
                      meetingState.status == MeetingStatus.reconnecting ||
                      meetingState.status == MeetingStatus.creating ||
                      meetingState.status == MeetingStatus.joining;
                  return UiIconButton(
                    tooltip: active
                        ? 'Open video meeting'
                        : 'Start video meeting',
                    icon: active
                        ? Icons.video_camera_front_outlined
                        : Icons.video_call_outlined,
                    onPressed: () => unawaited(_openMeetingEntry()),
                  );
                },
              ),
              UiIconButton(
                tooltip: 'Collaboration Room',
                icon: Icons.meeting_room_outlined,
                onPressed: () => unawaited(_openRoomDialog()),
              ),
            ],
            if (_navigationLoaded && _activeCanvasPage != null) ...[
              const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Tooltip(
                  message: _canvasPageBreadcrumb(_activeCanvasPage!),
                  child: Text(
                    _canvasPageBreadcrumb(_activeCanvasPage!),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.textMuted, fontSize: 11),
                  ),
                ),
              ),
              UiMenuButton<String>(
                tooltip: 'Pages and sections',
                icon: Icons.layers_clear_outlined,
                items: _canvasPageMenuItems(),
                onSelected: _selectCanvasPage,
              ),
            ],
            UiMenuButton<String>(
              tooltip: 'Canvas navigation',
              icon: Icons.explore_outlined,
              items: _canvasNavigationMenuItems(),
              onSelected: (choice) {
                if (choice.startsWith('rename_section:')) {
                  unawaited(_renameCanvasSection(choice.substring(15)));
                  return;
                }
                if (choice.startsWith('move_section:')) {
                  final sectionId = choice.substring(13);
                  _moveActiveCanvasPageToSection(
                    sectionId == 'none' ? null : sectionId,
                  );
                  return;
                }
                switch (choice) {
                  case 'zoom_content':
                    _zoomToCanvasContent();
                  case 'bookmarks':
                    unawaited(_openViewportBookmarks());
                  case 'focus':
                    _toggleCanvasFocusMode();
                  case 'new_page':
                    unawaited(_createCanvasPage());
                  case 'rename_page':
                    unawaited(_renameActiveCanvasPage());
                  case 'archive_page':
                    unawaited(_archiveActiveCanvasPage());
                  case 'new_section':
                    unawaited(_createCanvasSection());
                }
              },
            ),
            if (widget.services.enableExport)
              UiMenuButton<String>(
                tooltip: 'Export Options',
                icon: Icons.download_outlined,
                items: const [
                  UiMenuAction(
                    value: 'export_center',
                    icon: Icons.tune_outlined,
                    label: 'Open Export Center',
                  ),
                  UiMenuAction(
                    value: 'export_queue',
                    icon: Icons.pending_actions_outlined,
                    label: 'Open Export Queue',
                  ),
                  UiMenuAction(
                    value: 'inspect_handoff',
                    icon: Icons.radar_outlined,
                    label: 'Inspect & Handoff',
                  ),
                  UiMenuAction(
                    value: 'svg',
                    icon: Icons.polyline,
                    label: 'Export SVG Vector',
                  ),
                  UiMenuAction(
                    value: 'png',
                    icon: Icons.image,
                    label: 'Export PNG Image',
                  ),
                  UiMenuAction(
                    value: 'jpeg',
                    icon: Icons.photo_outlined,
                    label: 'Export JPEG Image',
                  ),
                  UiMenuAction(
                    value: 'webp',
                    icon: Icons.photo_library_outlined,
                    label: 'Export WebP Image',
                  ),
                  UiMenuAction(
                    value: 'markdown',
                    icon: Icons.notes,
                    label: 'Export Markdown',
                  ),
                  UiMenuAction(
                    value: 'text',
                    icon: Icons.text_fields,
                    label: 'Export Plain Text',
                  ),
                  UiMenuAction(
                    value: 'mermaid',
                    icon: Icons.account_tree_outlined,
                    label: 'Export Mermaid',
                  ),
                  UiMenuAction(
                    value: 'drawio',
                    icon: Icons.account_tree_outlined,
                    label: 'Export Draw.io XML',
                  ),
                  UiMenuAction(
                    value: 'json',
                    icon: Icons.code,
                    label: 'Export JSON',
                  ),
                ],
                onSelected: (choice) {
                  if (choice == 'export_center') {
                    _openExportCenter();
                  } else if (choice == 'export_queue') {
                    showUiDialog(
                      context: context,
                      builder: (_) => ExportQueueDialog(queue: _exportQueue),
                    );
                  } else if (choice == 'inspect_handoff') {
                    _openInspectHandoff();
                  } else if (choice == 'json') {
                    _openExportCenter(initialPreset: ExportPresetRegistry.json);
                  } else if (choice == 'png') {
                    _openExportCenter(initialPreset: ExportPresetRegistry.png);
                  } else if (choice == 'jpeg') {
                    _openExportCenter(initialPreset: ExportPresetRegistry.jpeg);
                  } else if (choice == 'webp') {
                    _openExportCenter(initialPreset: ExportPresetRegistry.webp);
                  } else if (choice == 'svg') {
                    _openExportCenter(initialPreset: ExportPresetRegistry.svg);
                  } else if (choice == 'markdown') {
                    _openExportCenter(
                      initialPreset: ExportPresetRegistry.markdown,
                    );
                  } else if (choice == 'text') {
                    _openExportCenter(
                      initialPreset: ExportPresetRegistry.plainText,
                    );
                  } else if (choice == 'mermaid') {
                    _openExportCenter(
                      initialPreset: ExportPresetRegistry.mermaid,
                    );
                  } else if (choice == 'drawio') {
                    _openExportCenter(
                      initialPreset: ExportPresetRegistry.drawio,
                    );
                  }
                },
              ),
            UiMenuButton<String>(
              key: const Key('canvas-settings-menu'),
              tooltip: 'Settings',
              icon: Icons.settings_outlined,
              items: _buildSettingsMenuItems(
                themeMode: themeMode,
                panelPreferences: panelPreferences,
              ),
              onSelected: (choice) {
                switch (choice) {
                  case 'import':
                    if (_collaborationReadOnly) break;
                    showUiDialog(
                      context: context,
                      builder: (_) => ImportDialog(
                        projectId: widget.projectId,
                        session: ref.read(
                          projectSessionProvider(widget.projectId),
                        ),
                        sessionGeneration: ref
                            .read(projectSessionProvider(widget.projectId))
                            .generation,
                        readOnly: _collaborationReadOnly,
                        onImport: _applyOwnedImport,
                      ),
                    );
                  case 'board_history':
                    if (!_collaborationReadOnly) _openBoardHistoryDialog();
                  case 'presentation':
                    _startPresentationMode();
                  case 'presentation_remote_host':
                    unawaited(_joinRemotePresenterAndStart());
                  case 'presentation_remote_controller':
                    unawaited(_openPresenterRemoteController());
                  case 'publish_snapshot':
                    unawaited(_openPublishedSnapshotDialog());
                  case 'review_workflow':
                    unawaited(_openReviewWorkflowDialog());
                  case 'quick_capture':
                    _openQuickCapturePalette();
                  case 'asset_library':
                    _openAssetLibrary();
                  case 'design_tokens':
                    _openDesignTokenManager();
                  case 'component_library':
                    unawaited(_openComponentLibrary());
                  case 'flowchart':
                    _insertFlowchartTemplate();
                  case 'save_selection_template':
                    unawaited(_saveSelectionAsTemplate());
                  case 'theme':
                    ref
                        .read(themeModeProvider.notifier)
                        .setMode(nextThemeMode(themeMode));
                  case 'backend':
                    showUiDialog(
                      context: context,
                      builder: (_) => const BackendSettingsDialog(),
                    );
                  case 'collaboration_profile':
                    showCollaborationProfileDialog(
                      context,
                      projectId: widget.projectId,
                    );
                  case 'governance':
                    unawaited(_openWorkspaceGovernanceDialog());
                }
              },
            ),
            if (!_collaborationReadOnly && panelPreferences.showInspectorButton)
              UiIconButton(
                key: const ValueKey('canvas-panel-toggle-inspector'),
                icon: Icons.tune_outlined,
                tooltip: _showInspector
                    ? 'Hide Inspector panel'
                    : 'Show Inspector panel',
                selected: _showInspector,
                onPressed: () => _toggleInspectorPanel(context),
              ),
          ],
          child: LayoutBuilder(
            builder: (context, editorConstraints) {
              final layersVisible =
                  !focusMode &&
                  _showLayers &&
                  panelPreferences.showLayersButton;
              final inspectorVisible =
                  !focusMode &&
                  _showInspector &&
                  panelPreferences.showInspectorButton &&
                  !_collaborationReadOnly;
              final panelColumnsWidth =
                  (layersVisible ? 250.0 : 0) + (inspectorVisible ? 280.0 : 0);
              final compactPanels =
                  editorConstraints.maxWidth < panelColumnsWidth + 420 &&
                  (layersVisible || inspectorVisible);
              final panelInset =
                  editorConstraints.maxWidth < AppBreakpoints.compact
                  ? AppSpacing.sm
                  : AppSpacing.md;
              final panelHeaderInset =
                  widget.services.showProjectHeader && !focusMode
                  ? Theme.of(context).appBarTheme.toolbarHeight ??
                        kToolbarHeight
                  : 0.0;
              final narrowStack =
                  widget.services.stackPanelsOnCompact &&
                  editorConstraints.maxWidth < AppBreakpoints.compact;
              final narrowPanelWidth = narrowStack
                  ? math.max(0.0, editorConstraints.maxWidth)
                  : 250.0;
              final compactPanelWidth = math.min(
                420.0,
                math.max(0.0, editorConstraints.maxWidth - panelInset * 2),
              );
              final availablePanelHeight = math.max(
                0.0,
                editorConstraints.maxHeight - panelHeaderInset - 24,
              );
              final preferredPanelHeight =
                  editorConstraints.maxWidth < AppBreakpoints.compact
                  ? editorConstraints.maxHeight * 0.52
                  : editorConstraints.maxHeight * 0.46;
              final compactPanelHeight = math.min(
                availablePanelHeight,
                math.min(420.0, math.max(220.0, preferredPanelHeight)),
              );
              final canvasToolbar = CanvasToolbar(
                aiActive: false,
                onAiPressed: widget.services.enableAiStudio
                    ? _focusAiComposer
                    : null,
                onModel3dPressed: _importModel3DFromToolbar,
              );
              final Widget? compactPanel = widget.services.stackPanelsOnCompact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (layersVisible)
                          Expanded(
                            child: LayersPanel(
                              readOnly: _collaborationReadOnly,
                              projectId: widget.projectId,
                              width: compactPanelWidth,
                            ),
                          ),
                        if (inspectorVisible)
                          Expanded(
                            child: InspectorPanel(
                              projectId: widget.projectId,
                              imageArtifactStore: _imageArtifactStore,
                              fileArtifactStore: _fileArtifactStore,
                              mediaArtifactStore: _mediaArtifactStore,
                              videoArtifactStore: _videoArtifactStore,
                              beginArtifactOperation: () =>
                                  ++_artifactOperationGeneration,
                              artifactOperationCurrent:
                                  _isArtifactOperationCurrent,
                              imageCache: _imageCache,
                              width: compactPanelWidth,
                              onResetModel3d: _resetModel3DView,
                              onRetryModel3d: _retryModel3DPreview,
                              onReplaceModel3d: _replaceModel3D,
                              onEditMermaid: _openMermaidEditor,
                              onEditChartData: _collaborationReadOnly
                                  ? null
                                  : _openChartDataEditor,
                            ),
                          ),
                      ],
                    )
                  : inspectorVisible
                  ? InspectorPanel(
                      projectId: widget.projectId,
                      imageArtifactStore: _imageArtifactStore,
                      fileArtifactStore: _fileArtifactStore,
                      mediaArtifactStore: _mediaArtifactStore,
                      videoArtifactStore: _videoArtifactStore,
                      beginArtifactOperation: () =>
                          ++_artifactOperationGeneration,
                      artifactOperationCurrent: _isArtifactOperationCurrent,
                      imageCache: _imageCache,
                      width: compactPanelWidth,
                      onResetModel3d: _resetModel3DView,
                      onRetryModel3d: _retryModel3DPreview,
                      onReplaceModel3d: _replaceModel3D,
                      onEditMermaid: _openMermaidEditor,
                      onEditChartData: _collaborationReadOnly
                          ? null
                          : _openChartDataEditor,
                    )
                  : layersVisible
                  ? LayersPanel(
                      readOnly: _collaborationReadOnly,
                      projectId: widget.projectId,
                      width: compactPanelWidth,
                    )
                  : null;

              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Row(
                      children: [
                        if (layersVisible && !compactPanels)
                          SizedBox(
                            width: narrowStack ? narrowPanelWidth : 250,
                            child: Padding(
                              padding: EdgeInsets.only(top: panelHeaderInset),
                              child: LayersPanel(
                                readOnly: _collaborationReadOnly,
                                projectId: widget.projectId,
                                width: narrowStack ? narrowPanelWidth : 250,
                              ),
                            ),
                          ),
                        Expanded(
                          child: DragTarget<Object>(
                            key: const ValueKey('diagram-shape-drop-target'),
                            onWillAcceptWithDetails: (details) =>
                                !_collaborationReadOnly &&
                                (details.data is DiagramShapeDefinition ||
                                    details.data is ChartType),
                            onAcceptWithDetails: _handleCanvasObjectDrop,
                            builder: (context, candidates, _) => Stack(
                              fit: StackFit.expand,
                              children: [
                                LayoutBuilder(
                                  builder: (context, canvasConstraints) {
                                    final canvasSize = Size(
                                      canvasConstraints.maxWidth,
                                      canvasConstraints.maxHeight,
                                    );
                                    CanvasPainter buildCanvasPainter({
                                      required bool renderEdges,
                                      required bool renderNodes,
                                      required bool renderForeground,
                                    }) => CanvasPainter(
                                      nodes: nodes,
                                      edges: edges,
                                      cursors: const [],
                                      viewport: viewport,
                                      selectedNodeIds: selectedIds,
                                      designTokens: designTokens,
                                      selectionMarquee: _selectionMarquee,
                                      snapGuides: _activeSnapGuides,
                                      measurements: _activeMeasurements,
                                      activeBrushStroke: List<Offset>.from(
                                        _activeBrushStroke,
                                      ),
                                      activeBrushType: brushConfig.brushType,
                                      activeBrushColor: brushConfig.color,
                                      activeBrushWidth: brushConfig.strokeWidth,
                                      activeBrushOpacity: brushConfig.opacity,
                                      activeBrushSmooth:
                                          brushConfig.smoothCurves,
                                      activeCreationTool: activeTool,
                                      activeDiagramShapeId:
                                          activeTool == CanvasTool.diagramShape
                                          ? activeDiagramShape.id
                                          : null,
                                      creationPreviewRect: _creationPreviewRect,
                                      creationPreviewLine: _creationPreviewLine,
                                      connectorPreview: liveConnectorPreview,
                                      connectorEditPreview:
                                          _connectorEditPreview,
                                      connectorSnapNodeId: _connectorSnapNodeId,
                                      connectorSnapPoint: _connectorSnapPoint,
                                      activePenPoints: List<BezierPoint>.from(
                                        _activePenPoints,
                                      ),
                                      penHoverPosition:
                                          _activePenPoints.isNotEmpty
                                          ? _mouseWorldPos
                                          : null,
                                      brushCursorPosition:
                                          activeTool == CanvasTool.brush
                                          ? _mouseWorldPos
                                          : null,
                                      editingNodeId: _editingNodeId,
                                      renderTokens:
                                          CanvasRenderTokens.fromAppTokens(
                                            tokens,
                                          ),
                                      renderEdges: renderEdges,
                                      renderNodes: renderNodes,
                                      renderForeground: renderForeground,
                                      showRotationHandle: true,
                                      imageCache: _imageCache,
                                    );
                                    return Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        MouseRegion(
                                          cursor: activeTool == CanvasTool.brush
                                              ? SystemMouseCursors.none
                                              : MouseCursor.defer,
                                          onHover: (event) {
                                            final world = ref
                                                .read(viewportProvider.notifier)
                                                .toWorld(event.localPosition);
                                            if (_connectorSourceNodeId !=
                                                    null ||
                                                _activePenPoints.isNotEmpty ||
                                                activeTool ==
                                                    CanvasTool.brush) {
                                              setState(() {
                                                _mouseWorldPos = world;
                                              });
                                            }
                                          },
                                          child: Listener(
                                            key: const ValueKey(
                                              'canvas-pointer-surface',
                                            ),
                                            onPointerDown: (event) {
                                              _pointerDownLocalPosition =
                                                  event.localPosition;
                                            },
                                            onPointerCancel: (_) {
                                              _pointerDownLocalPosition = null;
                                            },
                                            onPointerSignal: (pointerSignal) {
                                              if (pointerSignal
                                                      is PointerScrollEvent &&
                                                  !_isPointerOverSelectedModel(
                                                    pointerSignal.position,
                                                  )) {
                                                final delta =
                                                    pointerSignal
                                                            .scrollDelta
                                                            .dy >
                                                        0
                                                    ? 0.9
                                                    : 1.1;
                                                ref
                                                    .read(
                                                      viewportProvider.notifier,
                                                    )
                                                    .zoomBy(
                                                      delta,
                                                      pointerSignal
                                                          .localPosition,
                                                    );
                                              }
                                            },
                                            child: GestureDetector(
                                              key: _canvasKey,
                                              behavior: HitTestBehavior.opaque,
                                              onSecondaryTapUp: (details) =>
                                                  _handleSecondaryTapUp(
                                                    details,
                                                    activeTool,
                                                  ),
                                              onPanStart: (details) =>
                                                  _handlePanStart(
                                                    details,
                                                    activeTool,
                                                  ),
                                              onPanUpdate: (details) =>
                                                  _handlePanUpdate(
                                                    details,
                                                    activeTool,
                                                  ),
                                              onPanEnd: (details) {
                                                _handlePanEnd(
                                                  details,
                                                  activeTool,
                                                );
                                                _pointerDownLocalPosition =
                                                    null;
                                              },
                                              onPanCancel: () {
                                                _pointerDownLocalPosition =
                                                    null;
                                                ref
                                                    .read(
                                                      documentNodesProvider
                                                          .notifier,
                                                    )
                                                    .cancelTransaction();
                                                if (_connectorEditEdgeId !=
                                                    null) {
                                                  _cancelConnectorEdit();
                                                }
                                              },
                                              onTapUp: (details) {
                                                _handleTapUp(
                                                  details,
                                                  activeTool,
                                                );
                                                _pointerDownLocalPosition =
                                                    null;
                                              },
                                              onDoubleTapDown: (details) {
                                                _lastTapLocalPosition =
                                                    details.localPosition;
                                              },
                                              onDoubleTap: () =>
                                                  _handleDoubleTap(activeTool),
                                              child: RepaintBoundary(
                                                key: _repaintBoundaryKey,
                                                child: Stack(
                                                  key: const ValueKey(
                                                    'canvas-render-stack',
                                                  ),
                                                  clipBehavior: Clip.hardEdge,
                                                  children: [
                                                    CustomPaint(
                                                      painter: GridPainter(
                                                        panX: viewport.x,
                                                        panY: viewport.y,
                                                        zoom: viewport.zoom,
                                                        gridVisible: precision
                                                            .gridVisible,
                                                        gridPreset: precision
                                                            .gridPreset,
                                                        gridSpacing: precision
                                                            .gridSpacing,
                                                        gridSubdivisions:
                                                            precision
                                                                .gridSubdivisions,
                                                        tokens:
                                                            CanvasRenderTokens.fromAppTokens(
                                                              tokens,
                                                            ),
                                                      ),
                                                      size: Size.infinite,
                                                    ),
                                                    CustomPaint(
                                                      painter:
                                                          buildCanvasPainter(
                                                            renderEdges: true,
                                                            renderNodes: false,
                                                            renderForeground:
                                                                false,
                                                          ),
                                                      size: Size.infinite,
                                                    ),
                                                    ..._buildCanvasNodeLayers(
                                                      nodes: nodes,
                                                      selectedIds: selectedIds,
                                                      viewport: viewport,
                                                      viewportSize:
                                                          MediaQuery.sizeOf(
                                                            context,
                                                          ),
                                                      renderTokens:
                                                          CanvasRenderTokens.fromAppTokens(
                                                            tokens,
                                                          ),
                                                      designTokens:
                                                          designTokens,
                                                    ),
                                                    IgnorePointer(
                                                      child: CustomPaint(
                                                        painter:
                                                            buildCanvasPainter(
                                                              renderEdges:
                                                                  false,
                                                              renderNodes:
                                                                  false,
                                                              renderForeground:
                                                                  true,
                                                            ),
                                                        size: Size.infinite,
                                                      ),
                                                    ),
                                                    IgnorePointer(
                                                      child: CustomPaint(
                                                        painter:
                                                            CanvasGuidesPainter(
                                                              guides: precision
                                                                  .guides,
                                                              viewport:
                                                                  viewport,
                                                              visible: precision
                                                                  .guidesVisible,
                                                              color:
                                                                  tokens.accent,
                                                            ),
                                                        size: Size.infinite,
                                                      ),
                                                    ),
                                                    IgnorePointer(
                                                      child: CustomPaint(
                                                        painter: CanvasRulersPainter(
                                                          viewport: viewport,
                                                          visible: precision
                                                              .rulersVisible,
                                                          backgroundColor:
                                                              tokens
                                                                  .panelElevated
                                                                  .withValues(
                                                                    alpha: 0.92,
                                                                  ),
                                                          foregroundColor:
                                                              tokens.textMuted,
                                                        ),
                                                        size: Size.infinite,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (widget.services.enableCollaboration)
                                          Positioned.fill(
                                            child: CollaboratorOverlay(
                                              nodes: nodes,
                                              viewport: viewport,
                                              projectionScope: _projectionScope,
                                            ),
                                          ),
                                        ...orderedCommentThreads.asMap().entries.map((
                                          entry,
                                        ) {
                                          final threadIndex = entry.key;
                                          final thread = entry.value;
                                          final anchorComment = thread.first;
                                          final sameAnchorCount =
                                              anchorComment.nodeId == null
                                              ? 0
                                              : orderedCommentThreads
                                                    .take(threadIndex)
                                                    .where(
                                                      (candidate) =>
                                                          candidate
                                                              .first
                                                              .nodeId ==
                                                          anchorComment.nodeId,
                                                    )
                                                    .length;
                                          final anchorNode =
                                              anchorComment.nodeId == null
                                              ? null
                                              : nodes
                                                    .cast<CanvasNode?>()
                                                    .firstWhere(
                                                      (node) =>
                                                          node?.id ==
                                                          anchorComment.nodeId,
                                                      orElse: () => null,
                                                    );
                                          final anchorWorld = anchorNode == null
                                              ? Offset(
                                                  anchorComment.x,
                                                  anchorComment.y,
                                                )
                                              : Offset(
                                                  anchorNode.x +
                                                      anchorNode.width,
                                                  anchorNode.y +
                                                      anchorNode.height / 2,
                                                );
                                          final screenPos = ref
                                              .read(viewportProvider.notifier)
                                              .toScreen(anchorWorld);
                                          final itemSelected =
                                              anchorComment.nodeId == null ||
                                              selectedIds.contains(
                                                anchorComment.nodeId,
                                              );
                                          final editing =
                                              _feedbackNodeId ==
                                              anchorComment.id;
                                          final focused = thread.any(
                                            (comment) =>
                                                comment.id == _focusedCommentId,
                                          );
                                          final visible =
                                              itemSelected ||
                                              editing ||
                                              focused;
                                          final overlayLeft =
                                              (anchorNode == null
                                                      ? screenPos.dx - 22
                                                      : screenPos.dx - 2)
                                                  .clamp(
                                                    0.0,
                                                    math.max(
                                                      0.0,
                                                      canvasSize.width -
                                                          AppControlSize
                                                              .minimumHitTarget,
                                                    ),
                                                  )
                                                  .toDouble();
                                          final anchor = Semantics(
                                            key: ValueKey(
                                              'canvas-comment-anchor-${anchorComment.id}',
                                            ),
                                            button: true,
                                            label:
                                                'Comment by ${anchorComment.authorName}',
                                            hint: anchorComment.text.isEmpty
                                                ? 'Open comment editor'
                                                : 'Show comment thread',
                                            child: Tooltip(
                                              message:
                                                  anchorComment.text.isEmpty
                                                  ? 'Add comment'
                                                  : 'Show comment',
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onTap: () {
                                                  if (anchorComment
                                                      .text
                                                      .isEmpty) {
                                                    setState(
                                                      () => _feedbackNodeId =
                                                          anchorComment.id,
                                                    );
                                                  } else {
                                                    setState(() {
                                                      _focusedCommentId =
                                                          focused
                                                          ? null
                                                          : anchorComment.id;
                                                    });
                                                  }
                                                },
                                                child: ConstrainedBox(
                                                  constraints:
                                                      BoxConstraints.tightFor(
                                                        width: AppControlSize
                                                            .minimumHitTarget,
                                                        height: AppControlSize
                                                            .minimumHitTarget,
                                                      ),
                                                  child: Center(
                                                    child: Container(
                                                      key: ValueKey(
                                                        'canvas-comment-pin-visual-${anchorComment.id}',
                                                      ),
                                                      width: 24,
                                                      height: 24,
                                                      decoration: BoxDecoration(
                                                        color: tokens.warning,
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Icon(
                                                        Icons.chat_bubble,
                                                        size: 14,
                                                        color: tokens.text,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                          final Widget? threadOverlay;
                                          if (editing &&
                                              thread.length == 1 &&
                                              anchorComment.text.isEmpty) {
                                            threadOverlay = CommentDraftEditor(
                                              comment: anchorComment,
                                              readOnly:
                                                  widget.readOnly ||
                                                  !_collaborationCanComment,
                                              onCancel: () =>
                                                  _cancelCommentDraft(
                                                    anchorComment,
                                                  ),
                                              onSave: (text) =>
                                                  _saveCommentText(
                                                    anchorComment,
                                                    text,
                                                  ),
                                            );
                                          } else if (visible) {
                                            threadOverlay = CanvasCommentThreadCard(
                                              comments: thread,
                                              readOnly:
                                                  widget.readOnly ||
                                                  !_collaborationCanComment,
                                              onReply: (comment, text) =>
                                                  _addFeedbackReply(
                                                    comment,
                                                    text,
                                                  ),
                                              onEdit: (comment, text) =>
                                                  _saveCommentText(
                                                    comment,
                                                    text,
                                                  ),
                                              onReaction: (comment, emoji) =>
                                                  _toggleCommentReaction(
                                                    comment,
                                                    emoji,
                                                  ),
                                              onResolve: (comment, resolved) =>
                                                  _setCommentResolved(
                                                    comment,
                                                    resolved,
                                                  ),
                                              onDelete: (comment) =>
                                                  _confirmDeleteComment(
                                                    comment,
                                                  ),
                                              onMetadataChanged:
                                                  (comment, updated) =>
                                                      _updateCommentMetadata(
                                                        comment,
                                                        updated,
                                                      ),
                                              onPickAttachment:
                                                  _pickCommentAttachment,
                                              onEditReply:
                                                  (comment, reply, text) =>
                                                      _editCommentReply(
                                                        comment,
                                                        reply,
                                                        text,
                                                      ),
                                              onDeleteReply: (comment, reply) =>
                                                  _confirmDeleteCommentReply(
                                                    comment,
                                                    reply,
                                                  ),
                                              onCreateNewComment: (text) =>
                                                  _addNewCommentToThread(
                                                    anchorComment,
                                                    text,
                                                  ),
                                              onDismiss: itemSelected
                                                  ? null
                                                  : () => setState(
                                                      () => _focusedCommentId =
                                                          null,
                                                    ),
                                            );
                                          } else {
                                            threadOverlay = null;
                                          }
                                          final compactOverlay =
                                              canvasSize.width < 760;
                                          return Positioned(
                                            left: compactOverlay
                                                ? 0
                                                : overlayLeft,
                                            top:
                                                (screenPos.dy - 22) +
                                                sameAnchorCount * 340,
                                            child: compactOverlay
                                                ? Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (threadOverlay != null)
                                                        SizedBox(
                                                          width:
                                                              canvasSize.width,
                                                          child: threadOverlay,
                                                        ),
                                                      Row(
                                                        children: [
                                                          SizedBox(
                                                            width: overlayLeft,
                                                          ),
                                                          anchor,
                                                        ],
                                                      ),
                                                    ],
                                                  )
                                                : Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      anchor,
                                                      if (threadOverlay != null)
                                                        ConstrainedBox(
                                                          constraints: BoxConstraints(
                                                            maxWidth: math.max(
                                                              0.0,
                                                              canvasSize.width -
                                                                  overlayLeft -
                                                                  AppControlSize
                                                                      .minimumHitTarget,
                                                            ),
                                                          ),
                                                          child: threadOverlay,
                                                        ),
                                                    ],
                                                  ),
                                          );
                                        }),
                                        // Floating Focus Studio Button on Selected Drawing Paper Node
                                        ...nodes
                                            .where(
                                              (n) =>
                                                  n.type ==
                                                      NodeType.drawingPaper &&
                                                  selectedIds.contains(n.id),
                                            )
                                            .map((paperNode) {
                                              final screenTopRight = ref
                                                  .read(
                                                    viewportProvider.notifier,
                                                  )
                                                  .toScreen(
                                                    Offset(
                                                      paperNode.x +
                                                          paperNode.width,
                                                      paperNode.y,
                                                    ),
                                                  );
                                              return Positioned(
                                                left: screenTopRight.dx - 130,
                                                top: screenTopRight.dy - 36,
                                                child: UiButton(
                                                  onPressed: () {
                                                    final payload =
                                                        paperNode.payload
                                                            as DrawingPaperPayload;
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (ctx) =>
                                                            DrawingStudioScreen(
                                                              initialPayload:
                                                                  payload,
                                                              onSaveAndExit:
                                                                  (updated) {
                                                                    _saveDrawingStudioWorkspace(
                                                                      paperNode,
                                                                      payload,
                                                                      updated,
                                                                    );
                                                                  },
                                                            ),
                                                      ),
                                                    );
                                                  },
                                                  prefix: const Icon(
                                                    Icons.center_focus_strong,
                                                  ),
                                                  child: const Text(
                                                    'Focus Studio',
                                                  ),
                                                ),
                                              );
                                            }),
                                        ...nodes
                                            .where(
                                              (node) =>
                                                  node.type ==
                                                      NodeType.drawingPaper &&
                                                  selectedIds.contains(node.id),
                                            )
                                            .expand((paperNode) {
                                              const directions = <Offset>[
                                                Offset(1, 0),
                                                Offset(-1, 0),
                                                Offset(0, -1),
                                                Offset(0, 1),
                                              ];
                                              return directions.map((
                                                direction,
                                              ) {
                                                final anchor = Offset(
                                                  direction.dx > 0
                                                      ? paperNode.x +
                                                            paperNode.width +
                                                            16
                                                      : direction.dx < 0
                                                      ? paperNode.x - 16
                                                      : paperNode.x +
                                                            paperNode.width / 2,
                                                  direction.dy > 0
                                                      ? paperNode.y +
                                                            paperNode.height +
                                                            16
                                                      : direction.dy < 0
                                                      ? paperNode.y - 16
                                                      : paperNode.y +
                                                            paperNode.height /
                                                                2,
                                                );
                                                final screenAnchor = ref
                                                    .read(
                                                      viewportProvider.notifier,
                                                    )
                                                    .toScreen(anchor);
                                                return Positioned(
                                                  left: screenAnchor.dx - 16,
                                                  top: screenAnchor.dy - 16,
                                                  child: UiIconButton(
                                                    icon: Icons.add,
                                                    tooltip:
                                                        'Add same-size paper',
                                                    size: UiButtonSize.sm,
                                                    onPressed: () =>
                                                        _addAdjacentDrawingPaper(
                                                          paperNode,
                                                          direction,
                                                        ),
                                                  ),
                                                );
                                              });
                                            }),
                                        if (!_collaborationReadOnly)
                                          Positioned(
                                            left: AppSpacing.lg,
                                            top: AppSpacing.lg + kToolbarHeight,
                                            child: canvasSize.width < 760
                                                ? SizedBox(
                                                    width: math.max(
                                                      0.0,
                                                      canvasSize.width - 32,
                                                    ),
                                                    child:
                                                        SingleChildScrollView(
                                                          scrollDirection:
                                                              Axis.horizontal,
                                                          hitTestBehavior:
                                                              HitTestBehavior
                                                                  .deferToChild,
                                                          child: canvasToolbar,
                                                        ),
                                                  )
                                                : canvasToolbar,
                                          ),
                                        if (focusMode)
                                          Positioned(
                                            top: AppSpacing.md,
                                            right: AppSpacing.md,
                                            child: UiSurface(
                                              padding: const EdgeInsets.all(
                                                AppSpacing.xxs,
                                              ),
                                              color: tokens.panelElevated
                                                  .withValues(alpha: 0.96),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    AppRadius.control,
                                                  ),
                                              child: UiIconButton(
                                                icon: Icons
                                                    .fullscreen_exit_outlined,
                                                tooltip: 'Exit focus mode',
                                                onPressed:
                                                    _toggleCanvasFocusMode,
                                              ),
                                            ),
                                          ),
                                        if (!_collaborationReadOnly)
                                          ..._buildInlineEditor(),
                                        if (canvasSize.width >= 128 &&
                                            canvasSize.height >=
                                                AppControlSize
                                                        .minimumHitTarget +
                                                    (canvasSize.width < 760
                                                        ? AppSpacing.md * 2
                                                        : AppSpacing.lg * 2))
                                          Positioned(
                                            right: canvasSize.width < 760
                                                ? 12
                                                : 16,
                                            bottom: canvasSize.width < 760
                                                ? 12
                                                : 16,
                                            width: math.min(
                                              canvasSize.width < 760
                                                  ? 170.0
                                                  : 230.0,
                                              canvasSize.width -
                                                  (canvasSize.width < 760
                                                      ? 24
                                                      : 32),
                                            ),
                                            height: math.min(
                                              canvasSize.width < 760
                                                  ? 128.0
                                                  : 170.0,
                                              canvasSize.height -
                                                  (canvasSize.width < 760
                                                      ? 24
                                                      : 32),
                                            ),
                                            child: CanvasMinimap(
                                              nodes: nodes,
                                              edges: edges,
                                              viewport: viewport,
                                              selectedNodeIds: selectedIds,
                                              canvasSize: canvasSize,
                                              initiallyCollapsed:
                                                  canvasSize.width < 760,
                                              onViewportCenterChanged:
                                                  (center) {
                                                    final zoom =
                                                        viewport
                                                                .zoom
                                                                .isFinite &&
                                                            viewport.zoom > 0
                                                        ? viewport.zoom
                                                        : 1.0;
                                                    final width =
                                                        canvasSize
                                                                .width
                                                                .isFinite &&
                                                            canvasSize.width > 0
                                                        ? canvasSize.width
                                                        : 1.0;
                                                    final height =
                                                        canvasSize
                                                                .height
                                                                .isFinite &&
                                                            canvasSize.height >
                                                                0
                                                        ? canvasSize.height
                                                        : 1.0;
                                                    ref
                                                        .read(
                                                          viewportProvider
                                                              .notifier,
                                                        )
                                                        .setPosition(
                                                          width / 2 -
                                                              center.dx * zoom,
                                                          height / 2 -
                                                              center.dy * zoom,
                                                        );
                                                  },
                                              onFit: () {
                                                final visibleNodes = nodes
                                                    .where(
                                                      (node) => node.visible,
                                                    )
                                                    .toList();
                                                if (visibleNodes.isEmpty) {
                                                  ref
                                                      .read(
                                                        viewportProvider
                                                            .notifier,
                                                      )
                                                      .reset();
                                                  return;
                                                }
                                                final bounds =
                                                    MinimapTransform.worldBoundsFor(
                                                      nodeBounds: visibleNodes
                                                          .map(
                                                            (node) =>
                                                                node.bounds,
                                                          ),
                                                    );
                                                ref
                                                    .read(
                                                      viewportProvider.notifier,
                                                    )
                                                    .zoomToNode(
                                                      bounds,
                                                      canvasSize,
                                                    );
                                              },
                                              onZoomIn: () => ref
                                                  .read(
                                                    viewportProvider.notifier,
                                                  )
                                                  .zoomBy(
                                                    1.1,
                                                    canvasSize.center(
                                                      Offset.zero,
                                                    ),
                                                  ),
                                              onZoomOut: () => ref
                                                  .read(
                                                    viewportProvider.notifier,
                                                  )
                                                  .zoomBy(
                                                    0.9,
                                                    canvasSize.center(
                                                      Offset.zero,
                                                    ),
                                                  ),
                                              onReset: () => ref
                                                  .read(
                                                    viewportProvider.notifier,
                                                  )
                                                  .reset(),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                                if (candidates.isNotEmpty)
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: tokens.accent.withValues(
                                            alpha: 0.08,
                                          ),
                                          border: Border.all(
                                            color: tokens.accent,
                                            width: 3,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            'Drop shape here',
                                            style: TextStyle(
                                              color: tokens.accent,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (inspectorVisible && !compactPanels)
                          SizedBox(
                            width: narrowStack ? narrowPanelWidth : null,
                            child: Padding(
                              padding: EdgeInsets.only(top: panelHeaderInset),
                              child: InspectorPanel(
                                projectId: widget.projectId,
                                imageArtifactStore: _imageArtifactStore,
                                fileArtifactStore: _fileArtifactStore,
                                mediaArtifactStore: _mediaArtifactStore,
                                videoArtifactStore: _videoArtifactStore,
                                beginArtifactOperation: () =>
                                    ++_artifactOperationGeneration,
                                artifactOperationCurrent:
                                    _isArtifactOperationCurrent,
                                imageCache: _imageCache,
                                width: narrowStack ? narrowPanelWidth : 280,
                                onResetModel3d: _resetModel3DView,
                                onRetryModel3d: _retryModel3DPreview,
                                onReplaceModel3d: _replaceModel3D,
                                onEditMermaid: _openMermaidEditor,
                                onEditChartData: _collaborationReadOnly
                                    ? null
                                    : _openChartDataEditor,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!focusMode &&
                      !_collaborationReadOnly &&
                      widget.services.enableAiStudio)
                    Positioned(
                      left: !compactPanels && layersVisible
                          ? (narrowStack ? narrowPanelWidth : 250.0)
                          : 0,
                      right: !compactPanels && inspectorVisible
                          ? (narrowStack ? narrowPanelWidth : 280.0)
                          : 0,
                      bottom: AppSpacing.md,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: AIPanel(
                          projectId: widget.projectId,
                          onNodeCreated: _focusCreatedAiNode,
                          canEditCanvas: () =>
                              mounted && !_collaborationReadOnly,
                          compact: true,
                          promptFocusNode: _aiPromptFocusNode,
                        ),
                      ),
                    ),
                  if (compactPanels && compactPanel != null) ...[
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _closeCompactPanels,
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.10),
                        ),
                      ),
                    ),
                    Positioned(
                      left: panelInset,
                      right: panelInset,
                      bottom: panelInset,
                      height: compactPanelHeight,
                      child: Material(
                        type: MaterialType.transparency,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            tokens.panelRadius,
                          ),
                          child: compactPanel,
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _formatModelSize(int byteLength) {
    if (byteLength < 1024) return '$byteLength B';
    if (byteLength < 1024 * 1024) {
      return '${(byteLength / 1024).toStringAsFixed(1)} KB';
    }
    if (byteLength < 1024 * 1024 * 1024) {
      return '${(byteLength / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(byteLength / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<PreparedDocumentAssetNode?> _createModel3DNode(
    Uint8List bytes, {
    required String fileName,
    required Offset worldPosition,
    int? operationGeneration,
    String? expectedUserId,
    bool registerAsset = true,
  }) async {
    final syncService = ref.read(supabaseSyncServiceProvider);
    final generation = operationGeneration ?? ++_artifactOperationGeneration;
    final accountId = expectedUserId ?? syncService.currentUserId;
    try {
      final result = await Model3DImportService(
        artifactStore: _model3DArtifactStore,
        syncService: syncService,
      ).importBytes(bytes, fileName: fileName, projectId: widget.projectId);
      if (!_isArtifactOperationCurrent(
        generation: generation,
        projectId: widget.projectId,
        accountId: accountId,
      )) {
        return null;
      }
      final artifactReference = validModel3DArtifactReference(
        result.artifact.reference,
      );
      if (artifactReference == null) return null;
      final nodeId = const Uuid().v4();
      final asset = buildDocumentAsset(
        id: nodeId,
        kind: DocumentAssetKind.model3d,
        name: result.fileName,
        mimeType: 'model/gltf-binary',
        artifactReference: artifactReference,
        storagePath: result.storagePath,
        declaredSize: result.byteLength,
        bytes: bytes,
      );
      if (asset == null) return null;
      if (registerAsset) {
        if (!_isArtifactOperationCurrent(
          generation: generation,
          projectId: widget.projectId,
          accountId: accountId,
        )) {
          return null;
        }
        ref.read(documentAssetsProvider.notifier).upsert(asset);
      }
      final node = CanvasNode(
        id: nodeId,
        type: NodeType.model3d,
        x: worldPosition.dx - 160,
        y: worldPosition.dy - 120,
        width: 320,
        height: 240,
        payload: Model3DPayload(
          fileName: result.fileName,
          fileSizeText: _formatModelSize(result.byteLength),
          assetId: nodeId,
          modelPath: null,
          modelUrl: null,
          storagePath: result.storagePath,
          artifactReference: artifactReference,
        ),
      );
      return PreparedDocumentAssetNode(
        node: node,
        asset: asset,
        operationGeneration: generation,
        projectId: widget.projectId,
        accountId: accountId,
      );
    } on Model3DValidationException catch (error) {
      if (mounted) {
        showUiToast(context, error.message, variant: UiToastVariant.error);
      }
    } catch (error) {
      debugPrint('[CanvasEditorSurface] Error importing GLB: $error');
      if (mounted) {
        showUiToast(
          context,
          'The GLB model could not be imported.',
          variant: UiToastVariant.error,
        );
      }
    }
    return null;
  }

  String? _validDurableMediaReference(String? reference) =>
      validMediaArtifactReference(reference);

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

  Future<Uint8List?> _readDroppedModelBytes(DropItem file) =>
      readCanvasXFileBytes(file, maxBytes: maxModel3DBytes);

  Future<Uint8List?> _readDroppedBytes(XFile file, {required int maxBytes}) =>
      readCanvasXFileBytes(file, maxBytes: maxBytes);

  Future<PreparedDocumentAssetNode?> _pickModel3DNode(
    Offset worldPosition, {
    int? operationGeneration,
    String? expectedUserId,
    bool registerAsset = true,
  }) async {
    final generation = operationGeneration ?? ++_artifactOperationGeneration;
    final syncService = ref.read(supabaseSyncServiceProvider);
    final accountId = expectedUserId ?? syncService.currentUserId;
    try {
      final picked =
          await (widget.services.pickGlb?.call() ?? AssetService().pickGlb());
      if (!_isArtifactOperationCurrent(
            generation: generation,
            projectId: widget.projectId,
            accountId: accountId,
          ) ||
          picked == null) {
        return null;
      }
      Uint8List? bytes = picked.bytes;
      if ((bytes == null || bytes.isEmpty) &&
          !kIsWeb &&
          picked.path != null &&
          picked.path!.isNotEmpty) {
        bytes = await readCanvasFileBytes(
          picked.path!,
          maxBytes: maxModel3DBytes,
        );
        if (!_isArtifactOperationCurrent(
          generation: generation,
          projectId: widget.projectId,
          accountId: accountId,
        )) {
          return null;
        }
      }
      if (bytes == null || bytes.isEmpty) {
        throw const Model3DValidationException(
          'The selected GLB file could not be read.',
        );
      }
      return _createModel3DNode(
        bytes,
        fileName: picked.name,
        worldPosition: worldPosition,
        operationGeneration: generation,
        expectedUserId: accountId,
        registerAsset: registerAsset,
      );
    } on Model3DValidationException catch (error) {
      if (mounted) {
        showUiToast(context, error.message, variant: UiToastVariant.error);
      }
    } catch (error) {
      debugPrint('[CanvasEditorSurface] Error picking GLB: $error');
      if (mounted) {
        showUiToast(
          context,
          'The GLB model could not be selected.',
          variant: UiToastVariant.error,
        );
      }
    }
    return null;
  }

  Future<void> _importModel3DFromToolbar() async {
    await _spawnNodeAt(CanvasTool.model3d, _quickCaptureWorldCenter());
    if (mounted) {
      ref.read(activeToolProvider.notifier).setTool(CanvasTool.select);
    }
  }

  void _resetModel3DView(CanvasNode node) {
    if (_collaborationReadOnly || node.type != NodeType.model3d) return;
    setState(() {
      _model3DResetCommands[node.id] =
          (_model3DResetCommands[node.id] ?? 0) + 1;
    });
  }

  void _setModel3DAutoRotate(CanvasNode node, bool value) {
    if (_collaborationReadOnly || node.type != NodeType.model3d) return;
    final current = ref
        .read(documentNodesProvider)
        .where((candidate) => candidate.id == node.id)
        .firstOrNull;
    if (current == null || current.payload is! Model3DPayload) return;
    ref
        .read(documentNodesProvider.notifier)
        .updateNode(
          current.copyWith(
            payload: (current.payload as Model3DPayload).copyWith(
              autoRotate: value,
            ),
          ),
        );
  }

  void _captureModel3DCamera(CanvasNode node, Model3DCameraBookmark bookmark) {
    if (_collaborationReadOnly || node.type != NodeType.model3d) return;
    final current = ref
        .read(documentNodesProvider)
        .where((candidate) => candidate.id == node.id)
        .firstOrNull;
    if (current == null || current.payload is! Model3DPayload) return;
    final payload = current.payload as Model3DPayload;
    final nextPayload = payload
        .upsertCameraBookmark(bookmark)
        .copyWith(activeCameraBookmarkId: bookmark.id);
    ref
        .read(documentNodesProvider.notifier)
        .updateNode(current.copyWith(payload: nextPayload));
  }

  Future<void> _captureModel3DSnapshot(
    CanvasNode node,
    Uint8List bytes,
    int width,
    int height,
  ) async {
    if (_collaborationReadOnly || node.type != NodeType.model3d) return;
    final operationGeneration = ++_artifactOperationGeneration;
    final projectId = widget.projectId;
    final accountId = ref.read(supabaseSyncServiceProvider).currentUserId;
    final captured = ref
        .read(documentNodesProvider)
        .where((candidate) => candidate.id == node.id)
        .firstOrNull;
    if (captured == null || captured.payload is! Model3DPayload) return;
    final checksum = sha256.convert(bytes).toString();
    final artifact = await _imageArtifactStore.save(
      bytes,
      fileName: '${node.id}-snapshot.png',
    );
    if (!_isArtifactOperationCurrent(
      generation: operationGeneration,
      projectId: projectId,
      accountId: accountId,
    )) {
      return;
    }
    final snapshotReference = validImageArtifactReference(artifact.reference);
    if (snapshotReference == null) {
      if (mounted) {
        showUiToast(
          context,
          'The 3D snapshot could not be registered in owned artifact storage.',
          variant: UiToastVariant.error,
        );
      }
      return;
    }
    final snapshotAssetId = 'snapshot-${node.id}-${checksum.substring(0, 16)}';
    final snapshotAsset = buildDocumentAsset(
      id: snapshotAssetId,
      kind: DocumentAssetKind.image,
      name: '${node.id}-snapshot.png',
      mimeType: 'image/png',
      artifactReference: snapshotReference,
      storagePath: null,
      declaredSize: bytes.lengthInBytes,
      bytes: bytes,
    );
    if (snapshotAsset == null) return;
    final current = ref
        .read(documentNodesProvider)
        .where((candidate) => candidate.id == node.id)
        .firstOrNull;
    if (!_isArtifactOperationCurrent(
          generation: operationGeneration,
          projectId: projectId,
          accountId: accountId,
        ) ||
        current == null ||
        !canCommitModel3DSnapshot(
          capturedNode: captured,
          currentNode: current,
        )) {
      return;
    }
    ref.read(documentAssetsProvider.notifier).upsert(snapshotAsset);
    final payload = current.payload as Model3DPayload;
    final snapshot = Model3DSnapshot(
      id: 'snapshot-${DateTime.now().microsecondsSinceEpoch}',
      label: 'Snapshot ${payload.snapshots.length + 1}',
      cameraBookmarkId: payload.activeCameraBookmarkId,
      assetId: snapshotAssetId,
      artifactReference: snapshotReference,
      width: width,
      height: height,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    ref
        .read(documentNodesProvider.notifier)
        .updateNode(
          current.copyWith(payload: payload.upsertSnapshot(snapshot)),
        );
  }

  void _retryModel3DPreview(CanvasNode node) {
    if (_collaborationReadOnly || node.type != NodeType.model3d) return;
    setState(() {
      _model3DRetryCommands[node.id] =
          (_model3DRetryCommands[node.id] ?? 0) + 1;
    });
  }

  Future<void> _replaceModel3D(CanvasNode node) async {
    if (_collaborationReadOnly || node.type != NodeType.model3d) return;
    final operationGeneration = ++_artifactOperationGeneration;
    final projectId = widget.projectId;
    final accountId = ref.read(supabaseSyncServiceProvider).currentUserId;
    String? stagedAssetId;
    String? committedAssetId;

    try {
      final preparedReplacement = await _pickModel3DNode(
        node.bounds.center,
        operationGeneration: operationGeneration,
        expectedUserId: accountId,
      );
      final replacement = preparedReplacement?.node;
      if (replacement?.payload is Model3DPayload) {
        stagedAssetId = (replacement!.payload as Model3DPayload).assetId;
      }
      if (!_isArtifactOperationCurrent(
            generation: operationGeneration,
            projectId: projectId,
            accountId: accountId,
          ) ||
          preparedReplacement == null ||
          replacement == null) {
        return;
      }
      final replacementPayload = replacement.payload;
      if (replacementPayload is! Model3DPayload) return;

      if (stagedAssetId == null || stagedAssetId.isEmpty) return;

      final current = ref
          .read(documentNodesProvider)
          .where((candidate) => candidate.id == node.id)
          .firstOrNull;
      if (current == null || current.payload is! Model3DPayload) return;
      final currentPayload = current.payload as Model3DPayload;
      final manifest = ref.read(documentAssetsProvider);
      if (manifest[stagedAssetId] == null) return;
      if (!_isArtifactOperationCurrent(
        generation: operationGeneration,
        projectId: projectId,
        accountId: accountId,
      )) {
        return;
      }

      final committed = commitModel3DReplacement(
        manifest: manifest,
        stagedAssetId: stagedAssetId,
        currentAssetId: currentPayload.assetId,
        ownerNodeId: current.id,
        nodes: ref.read(documentNodesProvider),
      );
      final assetId = committed.assetId;
      publishModel3DReplacement(
        originalManifest: manifest,
        committedManifest: committed.manifest,
        stagedAssetId: stagedAssetId,
        nodes: ref.read(documentNodesProvider),
        setManifest: (next) =>
            ref.read(documentAssetsProvider.notifier).setManifest(next),
        publishNode: () {
          ref
              .read(documentNodesProvider.notifier)
              .updateNode(
                current.copyWith(
                  payload: replacementPayload.copyWith(
                    assetId: assetId,
                    snapshots: currentPayload.snapshots,
                    cameraBookmarks: currentPayload.cameraBookmarks,
                    annotations: currentPayload.annotations,
                    activeCameraBookmarkId:
                        currentPayload.activeCameraBookmarkId,
                  ),
                ),
              );
        },
      );
      committedAssetId = assetId;
      ref.read(selectionProvider.notifier).select(node.id);
    } finally {
      final staged = stagedAssetId;
      if (staged != null && committedAssetId != staged) {
        final manifest = ref.read(documentAssetsProvider);
        final settled = settleModel3DReplacementManifest(
          manifest: manifest,
          stagedAssetId: staged,
          committedAssetId: committedAssetId,
          nodes: ref.read(documentNodesProvider),
        );
        if (settled.entries.length != manifest.entries.length) {
          ref.read(documentAssetsProvider.notifier).setManifest(settled);
        }
      }
    }
  }

  bool _isPointerOverSelectedModel(Offset globalPosition) {
    final renderObject = _canvasKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return false;
    final localPosition = renderObject.globalToLocal(globalPosition);
    final worldPosition = ref
        .read(viewportProvider.notifier)
        .toWorld(localPosition);
    final selectedIds = ref.read(selectionProvider);
    return ref
        .read(documentNodesProvider)
        .any(
          (node) =>
              node.visible &&
              node.type == NodeType.model3d &&
              selectedIds.contains(node.id) &&
              node.bounds.contains(worldPosition),
        );
  }

  Offset _dropPositionInCanvas(DropDoneDetails detail) {
    final renderObject = _canvasKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox) {
      return renderObject.globalToLocal(detail.globalPosition);
    }
    return detail.localPosition;
  }

  void _handleCanvasObjectDrop(DragTargetDetails<Object> details) {
    if (_collaborationReadOnly) return;
    final worldPosition = ref
        .read(viewportProvider.notifier)
        .toWorld(details.offset);
    final data = details.data;
    if (data is DiagramShapeDefinition) {
      ref.read(activeDiagramShapeProvider.notifier).state = data;
      unawaited(_spawnNodeAt(CanvasTool.diagramShape, worldPosition));
    } else if (data is ChartType) {
      ref.read(activeChartTypeProvider.notifier).state = data;
      unawaited(_spawnNodeAt(CanvasTool.chart, worldPosition));
    } else {
      return;
    }
    ref.read(activeToolProvider.notifier).setTool(CanvasTool.select);
  }

  @visibleForTesting
  Future<void> handleFileDrop(DropDoneDetails detail) =>
      _handleFileDrop(detail);

  Future<void> _handleFileDrop(DropDoneDetails detail) async {
    if (_collaborationReadOnly || detail.files.isEmpty) return;

    final operationGeneration = ++_artifactOperationGeneration;
    final projectId = widget.projectId;
    final accountId = ref.read(supabaseSyncServiceProvider).currentUserId;

    // DropTarget.localPosition is local to the DropTarget scaffold, not the
    // transformed canvas. Convert the global pointer position at the boundary.
    final dropScreenPos = _dropPositionInCanvas(detail);
    final worldPos = ref.read(viewportProvider.notifier).toWorld(dropScreenPos);

    for (int i = 0; i < detail.files.length; i++) {
      final xfile = detail.files[i];
      final fileName = xfile.name;
      final fileNameLower = fileName.toLowerCase();
      final isModel3D = fileNameLower.endsWith('.glb');
      final isImage =
          fileNameLower.endsWith('.png') ||
          fileNameLower.endsWith('.jpg') ||
          fileNameLower.endsWith('.jpeg') ||
          fileNameLower.endsWith('.webp') ||
          fileNameLower.endsWith('.gif') ||
          fileNameLower.endsWith('.bmp');
      final isAudio =
          fileNameLower.endsWith('.mp3') ||
          fileNameLower.endsWith('.wav') ||
          fileNameLower.endsWith('.m4a') ||
          fileNameLower.endsWith('.aac') ||
          fileNameLower.endsWith('.ogg') ||
          fileNameLower.endsWith('.flac');
      final isVideo =
          fileNameLower.endsWith('.mp4') ||
          fileNameLower.endsWith('.mov') ||
          fileNameLower.endsWith('.webm') ||
          fileNameLower.endsWith('.mkv') ||
          fileNameLower.endsWith('.avi');

      final dropOffset = Offset(i * 30.0, i * 30.0);

      if (isModel3D) {
        final bytes = await _readDroppedModelBytes(xfile);
        if (!_isArtifactOperationCurrent(
          generation: operationGeneration,
          projectId: projectId,
          accountId: accountId,
        )) {
          return;
        }
        if (bytes == null || bytes.isEmpty) {
          if (mounted) {
            showUiToast(
              context,
              'The dropped GLB file could not be read.',
              variant: UiToastVariant.error,
            );
          }
          continue;
        }
        final originalManifest = ref.read(documentAssetsProvider);
        final prepared = await _createModel3DNode(
          bytes,
          fileName: fileName,
          worldPosition: worldPos + dropOffset,
          operationGeneration: operationGeneration,
          expectedUserId: accountId,
          registerAsset: false,
        );
        if (!_isArtifactOperationCurrent(
          generation: operationGeneration,
          projectId: projectId,
          accountId: accountId,
        )) {
          return;
        }
        if (prepared == null) continue;
        final node = prepared.node;
        final asset = prepared.asset;
        if (!_isArtifactOperationCurrent(
          generation: operationGeneration,
          projectId: projectId,
          accountId: accountId,
        )) {
          return;
        }
        publishDocumentAssetAndNode(
          originalManifest: originalManifest,
          committedManifest: originalManifest.upsert(asset),
          setManifest: (next) =>
              ref.read(documentAssetsProvider.notifier).setManifest(next),
          publishNode: () {
            ref.read(documentNodesProvider.notifier).addNode(node);
            ref.read(selectionProvider.notifier).select(node.id);
          },
        );
        continue;
      }

      if (isAudio) {
        final bytes = await _readDroppedBytes(
          xfile,
          maxBytes: maxMediaArtifactBytes,
        );
        if (!_isArtifactOperationCurrent(
          generation: operationGeneration,
          projectId: projectId,
          accountId: accountId,
        )) {
          return;
        }
        if (bytes == null || bytes.isEmpty) {
          if (!mounted) return;
          showUiToast(
            context,
            'The dropped audio file could not be read.',
            variant: UiToastVariant.error,
          );
          continue;
        }
        final audioMimeType = _audioMimeTypeForFileName(fileName);
        if (!assetBytesMatchMimeSignature(bytes, audioMimeType)) {
          if (!mounted) return;
          showUiToast(
            context,
            'The dropped audio is not a supported audio file.',
            variant: UiToastVariant.error,
          );
          continue;
        }
        MediaArtifact artifact;
        try {
          artifact = await _mediaArtifactStore.save(
            bytes,
            kind: MediaArtifactKind.original,
            mimeType: audioMimeType,
            checksum: mediaArtifactChecksum(bytes),
            fileName: fileName,
            storagePolicy: MediaStoragePolicy.durable,
          );
        } catch (_) {
          if (!mounted) return;
          showUiToast(
            context,
            'The dropped audio could not be stored in owned artifact storage.',
            variant: UiToastVariant.error,
          );
          continue;
        }
        if (!_isArtifactOperationCurrent(
          generation: operationGeneration,
          projectId: projectId,
          accountId: accountId,
        )) {
          return;
        }
        final audioReference = _validDurableMediaReference(artifact.reference);
        if (audioReference == null) {
          if (!mounted) return;
          showUiToast(
            context,
            'The audio could not be stored in owned artifact storage.',
            variant: UiToastVariant.error,
          );
          continue;
        }
        final nodeId = const Uuid().v4();
        final asset = buildDocumentAsset(
          id: nodeId,
          kind: DocumentAssetKind.audio,
          name: fileName,
          mimeType: audioMimeType,
          artifactReference: audioReference,
          storagePath: null,
          declaredSize: bytes.lengthInBytes,
          bytes: bytes,
        );
        if (asset == null) {
          if (!mounted) return;
          showUiToast(
            context,
            'The audio could not be registered in the asset manifest.',
            variant: UiToastVariant.error,
          );
          continue;
        }
        final node = CanvasNode(
          id: nodeId,
          type: NodeType.audioCard,
          x: worldPos.dx - 120 + dropOffset.dx,
          y: worldPos.dy - 35 + dropOffset.dy,
          width: 240,
          height: 70,
          payload: AudioPayload(
            trackName: fileName,
            assetId: nodeId,
            audioArtifactReference: audioReference,
          ),
        );
        if (!_isArtifactOperationCurrent(
          generation: operationGeneration,
          projectId: projectId,
          accountId: accountId,
        )) {
          return;
        }
        final originalManifest = ref.read(documentAssetsProvider);
        publishDocumentAssetAndNode(
          originalManifest: originalManifest,
          committedManifest: originalManifest.upsert(asset),
          setManifest: (next) =>
              ref.read(documentAssetsProvider.notifier).setManifest(next),
          publishNode: () {
            ref.read(documentNodesProvider.notifier).addNode(node);
            ref.read(selectionProvider.notifier).select(node.id);
          },
        );
      } else if (isVideo) {
        final bytes = await _readDroppedBytes(
          xfile,
          maxBytes: maxVideoArtifactBytes,
        );
        if (!_isArtifactOperationCurrent(
          generation: operationGeneration,
          projectId: projectId,
          accountId: accountId,
        )) {
          return;
        }
        if (bytes == null || bytes.isEmpty) {
          if (!mounted) return;
          showUiToast(
            context,
            'The dropped video file could not be read.',
            variant: UiToastVariant.error,
          );
          continue;
        }

        VideoArtifact artifact;
        try {
          artifact = await _videoArtifactStore.save(bytes, fileName: fileName);
        } catch (_) {
          if (!mounted) return;
          showUiToast(
            context,
            'The dropped video is unavailable or not a supported MP4.',
            variant: UiToastVariant.error,
          );
          continue;
        }
        if (!_isArtifactOperationCurrent(
          generation: operationGeneration,
          projectId: projectId,
          accountId: accountId,
        )) {
          return;
        }
        final videoReference = validVideoArtifactReference(artifact.reference);
        if (videoReference == null) {
          if (!mounted) return;
          showUiToast(
            context,
            'The video could not be stored in owned artifact storage.',
            variant: UiToastVariant.error,
          );
          continue;
        }

        final nodeId = const Uuid().v4();
        final asset = buildDocumentAsset(
          id: nodeId,
          kind: DocumentAssetKind.video,
          name: fileName,
          mimeType: inferAssetMimeType(fileName, fallback: 'video/mp4'),
          artifactReference: videoReference,
          storagePath: null,
          declaredSize: bytes.lengthInBytes,
          bytes: bytes,
        );
        if (asset == null) {
          if (!mounted) return;
          showUiToast(
            context,
            'The video could not be registered in the asset manifest.',
            variant: UiToastVariant.error,
          );
          continue;
        }
        final node = CanvasNode(
          id: nodeId,
          type: NodeType.videoCard,
          x: worldPos.dx - 120 + dropOffset.dx,
          y: worldPos.dy - 75 + dropOffset.dy,
          width: 240,
          height: 150,
          payload: VideoPayload(
            title: fileName,
            durationText: 'Unknown',
            assetId: nodeId,
            videoArtifactReference: videoReference,
          ),
        );
        if (!_isArtifactOperationCurrent(
          generation: operationGeneration,
          projectId: projectId,
          accountId: accountId,
        )) {
          return;
        }
        final originalManifest = ref.read(documentAssetsProvider);
        publishDocumentAssetAndNode(
          originalManifest: originalManifest,
          committedManifest: originalManifest.upsert(asset),
          setManifest: (next) =>
              ref.read(documentAssetsProvider.notifier).setManifest(next),
          publishNode: () {
            ref.read(documentNodesProvider.notifier).addNode(node);
            ref.read(selectionProvider.notifier).select(node.id);
          },
        );
      } else if (isImage) {
        try {
          final bytes = await _readDroppedBytes(
            xfile,
            maxBytes: maxImageArtifactBytes,
          );
          if (!_isArtifactOperationCurrent(
            generation: operationGeneration,
            projectId: projectId,
            accountId: accountId,
          )) {
            return;
          }

          if (bytes == null || bytes.isEmpty) continue;

          final artifact = await _imageArtifactStore.save(
            bytes,
            fileName: xfile.name,
          );
          if (!_isArtifactOperationCurrent(
            generation: operationGeneration,
            projectId: projectId,
            accountId: accountId,
          )) {
            return;
          }
          final imageReference = validImageArtifactReference(
            artifact.reference,
          );
          if (imageReference == null) {
            if (!mounted) return;
            showUiToast(
              context,
              'The image could not be stored in owned artifact storage.',
              variant: UiToastVariant.error,
            );
            continue;
          }

          // Decode & cache instantly under the opaque artifact identity.
          double width = 280;
          double height = 200;
          final decodedImg = await _imageCache.decodeAndCacheBytes(
            imageReference,
            bytes,
          );
          if (!_isArtifactOperationCurrent(
            generation: operationGeneration,
            projectId: projectId,
            accountId: accountId,
          )) {
            return;
          }
          if (decodedImg != null) {
            const maxDim = 320.0;
            final aspect = decodedImg.width / decodedImg.height;
            if (decodedImg.width >= decodedImg.height) {
              width = maxDim;
              height = maxDim / aspect;
            } else {
              height = maxDim;
              width = maxDim * aspect;
            }
          }

          final nodeId = const Uuid().v4();
          final asset = buildDocumentAsset(
            id: nodeId,
            kind: DocumentAssetKind.image,
            name: xfile.name,
            mimeType: inferAssetMimeType(xfile.name, fallback: 'image/png'),
            artifactReference: imageReference,
            storagePath: null,
            declaredSize: bytes.lengthInBytes,
            bytes: bytes,
          );
          if (asset == null) {
            if (mounted) {
              showUiToast(
                context,
                'The image could not be registered in the asset manifest.',
                variant: UiToastVariant.error,
              );
            }
            continue;
          }
          final newNode = CanvasNode(
            id: nodeId,
            type: NodeType.image,
            x: (worldPos.dx - width / 2) + dropOffset.dx,
            y: (worldPos.dy - height / 2) + dropOffset.dy,
            width: width,
            height: height,
            payload: ImagePayload(
              imageArtifactReference: imageReference,
              assetId: nodeId,
            ),
          );
          if (!_isArtifactOperationCurrent(
            generation: operationGeneration,
            projectId: projectId,
            accountId: accountId,
          )) {
            return;
          }
          final originalManifest = ref.read(documentAssetsProvider);
          publishDocumentAssetAndNode(
            originalManifest: originalManifest,
            committedManifest: originalManifest.upsert(asset),
            setManifest: (next) =>
                ref.read(documentAssetsProvider.notifier).setManifest(next),
            publishNode: () {
              ref.read(documentNodesProvider.notifier).addNode(newNode);
              ref.read(selectionProvider.notifier).select(newNode.id);
            },
          );
        } catch (err) {
          debugPrint(
            '[CanvasEditorSurface] Error processing dropped image: $err',
          );
        }
      } else {
        // Non-image file -> Create FileCard
        try {
          final persistedBytes = await _readDroppedBytes(
            xfile,
            maxBytes: maxFileArtifactBytes,
          );
          if (!_isArtifactOperationCurrent(
            generation: operationGeneration,
            projectId: projectId,
            accountId: accountId,
          )) {
            return;
          }
          final fileLength = persistedBytes?.lengthInBytes ?? 0;

          if (persistedBytes == null || persistedBytes.isEmpty) {
            if (!mounted) return;
            showUiToast(
              context,
              'The file could not be read for owned artifact storage.',
              variant: UiToastVariant.error,
            );
            continue;
          }

          String fileSizeStr = 'Unknown size';
          if (fileLength > 0) {
            if (fileLength < 1024) {
              fileSizeStr = '$fileLength B';
            } else if (fileLength < 1024 * 1024) {
              fileSizeStr = '${(fileLength / 1024).toStringAsFixed(1)} KB';
            } else if (fileLength < 1024 * 1024 * 1024) {
              fileSizeStr =
                  '${(fileLength / (1024 * 1024)).toStringAsFixed(1)} MB';
            } else {
              fileSizeStr =
                  '${(fileLength / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
            }
          }

          final ext = fileName.contains('.')
              ? fileName.split('.').last.toUpperCase()
              : 'FILE';
          final savedFile = await _fileArtifactStore.save(
            persistedBytes,
            fileName: fileName,
          );
          if (!_isArtifactOperationCurrent(
            generation: operationGeneration,
            projectId: projectId,
            accountId: accountId,
          )) {
            return;
          }
          final artifactReference = validFileArtifactReference(
            savedFile.reference,
          );
          if (artifactReference == null) {
            if (!mounted) return;
            showUiToast(
              context,
              'The file could not be stored in owned artifact storage.',
              variant: UiToastVariant.error,
            );
            continue;
          }

          const cardWidth = 240.0;
          const cardHeight = 70.0;

          final nodeId = const Uuid().v4();
          final assetId = nodeId;
          final asset = buildDocumentAsset(
            id: assetId,
            kind: DocumentAssetKind.document,
            name: fileName,
            mimeType: inferAssetMimeType(
              fileName,
              fallback: 'application/octet-stream',
            ),
            artifactReference: artifactReference,
            storagePath: null,
            declaredSize: persistedBytes.lengthInBytes,
            bytes: persistedBytes,
          );
          if (asset == null) {
            if (!mounted) return;
            showUiToast(
              context,
              'The file could not be registered in the asset manifest.',
              variant: UiToastVariant.error,
            );
            continue;
          }
          final newNode = CanvasNode(
            id: nodeId,
            type: NodeType.fileCard,
            x: (worldPos.dx - cardWidth / 2) + dropOffset.dx,
            y: (worldPos.dy - cardHeight / 2) + dropOffset.dy,
            width: cardWidth,
            height: cardHeight,
            payload: FilePayload(
              fileName: fileName,
              assetId: assetId,
              fileExtension: ext,
              fileSizeText: fileSizeStr,
              artifactReference: artifactReference,
            ),
          );
          if (!_isArtifactOperationCurrent(
            generation: operationGeneration,
            projectId: projectId,
            accountId: accountId,
          )) {
            return;
          }
          final originalManifest = ref.read(documentAssetsProvider);
          publishDocumentAssetAndNode(
            originalManifest: originalManifest,
            committedManifest: originalManifest.upsert(asset),
            setManifest: (next) =>
                ref.read(documentAssetsProvider.notifier).setManifest(next),
            publishNode: () {
              ref.read(documentNodesProvider.notifier).addNode(newNode);
              ref.read(selectionProvider.notifier).select(newNode.id);
            },
          );
        } catch (err) {
          debugPrint(
            '[CanvasEditorSurface] Error processing dropped file: $err',
          );
        }
      }
    }
  }

  List<Widget> _buildInlineEditor() {
    final nodeId = _editingNodeId;
    if (nodeId == null) return const [];
    final nodes = ref.read(documentNodesProvider);
    final match = nodes.where((n) => n.id == nodeId).toList();
    if (match.isEmpty) return const [];
    final node = match.first;
    final tokens = context.appTokens;
    final viewport = ref.read(viewportProvider);
    final isShapeNode = node.payload is ShapePayload;
    final shapeTextInset = isShapeNode && !_editingFrameLabel ? 8.0 : 0.0;

    final Offset screenPos;
    double width;
    if (_editingFrameLabel) {
      screenPos = ref
          .read(viewportProvider.notifier)
          .toScreen(Offset(node.x, node.y - 18));
      width = math.max(120.0, node.width);
    } else {
      screenPos = ref
          .read(viewportProvider.notifier)
          .toScreen(Offset(node.x + shapeTextInset, node.y));
      width = isShapeNode
          ? math.max(1.0, node.width - shapeTextInset * 2) * viewport.zoom
          : math.max(160.0, node.width);
    }

    final isTextNode =
        node.type == NodeType.text && node.payload is TextPayload;
    final isStickyNoteNode =
        node.type == NodeType.stickyNote && node.payload is StickyNotePayload;
    final textPayload = isTextNode ? (node.payload as TextPayload) : null;
    final stickyPayload = isStickyNoteNode
        ? (node.payload as StickyNotePayload)
        : null;
    final shapePayload = isShapeNode ? (node.payload as ShapePayload) : null;

    final double inlineFontSize = _editingFrameLabel
        ? 12.0
        : (textPayload?.fontSize ?? (stickyPayload?.fontSize ?? 14.0));
    final TextAlign inlineTextAlign =
        textPayload?.textAlign ??
        (stickyPayload?.textAlign ??
            (isShapeNode ? TextAlign.center : TextAlign.left));
    return [
      // Floating Formatting Quick-Bar above active text editing or sticky note node
      if ((isTextNode || isStickyNoteNode) &&
          (textPayload != null || stickyPayload != null))
        Positioned(
          left: screenPos.dx,
          top: math.max(8.0, screenPos.dy - 44),
          child: TapRegion(
            groupId: 'inline_text_editor',
            child: Container(
              key: const ValueKey('inline-text-formatting-quick-bar'),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs + AppSpacing.xxs,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: tokens.panelElevated,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(
                  color: tokens.panelBorder,
                  width: AppBorder.thin,
                ),
                boxShadow: [
                  BoxShadow(
                    color: tokens.text.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bold Button
                  UiIconButton(
                    icon: Icons.format_bold,
                    tooltip: 'Bold (Ctrl+B)',
                    size: UiButtonSize.sm,
                    selected:
                        textPayload?.fontWeight == FontWeight.bold ||
                        textPayload?.fontWeight == FontWeight.w900,
                    onPressed: () {
                      if (isTextNode) {
                        _applyFormattingToRichTextOrNode(
                          node,
                          formatType: 'bold',
                          nodeFallback: (p) => p.copyWith(
                            fontWeight:
                                (p.fontWeight == FontWeight.bold ||
                                    p.fontWeight == FontWeight.w900)
                                ? FontWeight.normal
                                : FontWeight.bold,
                          ),
                        );
                      }
                    },
                  ),
                  // Italic Button
                  UiIconButton(
                    icon: Icons.format_italic,
                    tooltip: 'Italic (Ctrl+I)',
                    size: UiButtonSize.sm,
                    selected: textPayload?.fontStyle == FontStyle.italic,
                    onPressed: () {
                      if (isTextNode) {
                        _applyFormattingToRichTextOrNode(
                          node,
                          formatType: 'italic',
                          nodeFallback: (p) => p.copyWith(
                            fontStyle: p.fontStyle == FontStyle.italic
                                ? FontStyle.normal
                                : FontStyle.italic,
                          ),
                        );
                      }
                    },
                  ),

                  // Underline Button
                  UiIconButton(
                    icon: Icons.format_underlined,
                    tooltip: 'Underline (Ctrl+U)',
                    size: UiButtonSize.sm,
                    selected: textPayload?.underline == true,
                    onPressed: () {
                      if (isTextNode) {
                        _applyFormattingToRichTextOrNode(
                          node,
                          formatType: 'underline',
                          nodeFallback: (p) =>
                              p.copyWith(underline: !p.underline),
                        );
                      }
                    },
                  ),
                  // Strikethrough Button
                  UiIconButton(
                    icon: Icons.format_strikethrough,
                    tooltip: 'Strikethrough',
                    size: UiButtonSize.sm,
                    selected: textPayload?.strikethrough == true,
                    onPressed: () {
                      if (isTextNode) {
                        _applyFormattingToRichTextOrNode(
                          node,
                          formatType: 'strikethrough',
                          nodeFallback: (p) =>
                              p.copyWith(strikethrough: !p.strikethrough),
                        );
                      }
                    },
                  ),
                  Container(
                    width: AppBorder.thin,
                    height: 16,
                    color: tokens.panelBorder,
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                  ),
                  // Alignment cycles (Left -> Center -> Right -> Justify)
                  UiIconButton(
                    icon: inlineTextAlign == TextAlign.center
                        ? Icons.format_align_center
                        : (inlineTextAlign == TextAlign.right
                              ? Icons.format_align_right
                              : (inlineTextAlign == TextAlign.justify
                                    ? Icons.format_align_justify
                                    : Icons.format_align_left)),
                    tooltip: 'Align: ${inlineTextAlign.name.toUpperCase()}',
                    size: UiButtonSize.sm,
                    onPressed: () {
                      final nextAlign = inlineTextAlign == TextAlign.left
                          ? TextAlign.center
                          : (inlineTextAlign == TextAlign.center
                                ? TextAlign.right
                                : (inlineTextAlign == TextAlign.right
                                      ? (isTextNode
                                            ? TextAlign.justify
                                            : TextAlign.left)
                                      : TextAlign.left));
                      if (isTextNode && textPayload != null) {
                        _applyQuickStyle(
                          node,
                          (p) => p.copyWith(textAlign: nextAlign),
                        );
                      } else if (isStickyNoteNode && stickyPayload != null) {
                        ref
                            .read(documentNodesProvider.notifier)
                            .updateNode(
                              node.copyWith(
                                payload: stickyPayload.copyWith(
                                  textAlign: nextAlign,
                                ),
                              ),
                            );
                        _editFocusNode.requestFocus();
                      }
                    },
                  ),
                  // Vertical Align cycles
                  if (isTextNode && textPayload != null)
                    UiIconButton(
                      icon:
                          textPayload.verticalAlign == TextVerticalAlign.middle
                          ? Icons.vertical_align_center
                          : (textPayload.verticalAlign ==
                                    TextVerticalAlign.bottom
                                ? Icons.vertical_align_bottom
                                : Icons.vertical_align_top),
                      tooltip:
                          'Vertical Align: ${textPayload.verticalAlign.name.toUpperCase()}',
                      size: UiButtonSize.sm,
                      onPressed: () {
                        final nextVAlign =
                            textPayload.verticalAlign == TextVerticalAlign.top
                            ? TextVerticalAlign.middle
                            : (textPayload.verticalAlign ==
                                      TextVerticalAlign.middle
                                  ? TextVerticalAlign.bottom
                                  : TextVerticalAlign.top);
                        _applyQuickStyle(
                          node,
                          (p) => p.copyWith(verticalAlign: nextVAlign),
                        );
                      },
                    ),
                  Container(
                    width: AppBorder.thin,
                    height: 16,
                    color: tokens.panelBorder,
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                  ),
                  // Font Size quick increment / decrement
                  UiIconButton(
                    icon: Icons.remove,
                    tooltip: 'Decrease Font Size',
                    size: UiButtonSize.sm,
                    onPressed: () {
                      if (isTextNode && textPayload != null) {
                        _applyQuickStyle(
                          node,
                          (p) => p.copyWith(
                            fontSize: (p.fontSize - 2).clamp(8.0, 140.0),
                          ),
                        );
                      } else if (isStickyNoteNode && stickyPayload != null) {
                        ref
                            .read(documentNodesProvider.notifier)
                            .updateNode(
                              node.copyWith(
                                payload: stickyPayload.copyWith(
                                  fontSize: (stickyPayload.fontSize - 2).clamp(
                                    8.0,
                                    72.0,
                                  ),
                                ),
                              ),
                            );
                        _editFocusNode.requestFocus();
                      }
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxs,
                    ),
                    child: Text(
                      '${inlineFontSize.toInt()}',
                      style: TextStyle(
                        color: tokens.text,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.add,
                    tooltip: 'Increase Font Size',
                    size: UiButtonSize.sm,
                    onPressed: () {
                      if (isTextNode && textPayload != null) {
                        _applyQuickStyle(
                          node,
                          (p) => p.copyWith(
                            fontSize: (p.fontSize + 2).clamp(8.0, 140.0),
                          ),
                        );
                      } else if (isStickyNoteNode && stickyPayload != null) {
                        ref
                            .read(documentNodesProvider.notifier)
                            .updateNode(
                              node.copyWith(
                                payload: stickyPayload.copyWith(
                                  fontSize: (stickyPayload.fontSize + 2).clamp(
                                    8.0,
                                    72.0,
                                  ),
                                ),
                              ),
                            );
                        _editFocusNode.requestFocus();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),

      Positioned(
        left: screenPos.dx,
        top: screenPos.dy,
        width: width,
        height: _editingFrameLabel
            ? null
            : (isShapeNode
                  ? math.max(1.0, node.height * viewport.zoom)
                  : math.max(40.0, node.height)),
        child: TapRegion(
          groupId: 'inline_text_editor',
          onTapOutside: (_) {
            _commitInlineEdit();
          },
          child: shapePayload == null
              ? UiTextField(
                  controller: _editController,
                  focusNode: _editFocusNode,
                  autofocus: true,
                  maxLines: _editingFrameLabel ? 1 : null,
                  expands: !_editingFrameLabel,
                  minLines: _editingFrameLabel ? 1 : null,
                  keyboardType: _editingFrameLabel
                      ? TextInputType.text
                      : TextInputType.multiline,
                  textInputAction: _editingFrameLabel
                      ? TextInputAction.done
                      : TextInputAction.newline,
                  autocorrect: textPayload?.spellCheckEnabled ?? true,
                  enableSuggestions: textPayload?.spellCheckEnabled ?? true,
                  spellCheckConfiguration: textPayload == null
                      ? null
                      : (textPayload.spellCheckEnabled
                            ? const SpellCheckConfiguration()
                            : const SpellCheckConfiguration.disabled()),
                  textAlign: inlineTextAlign,
                  textAlignVertical: textPayload == null
                      ? TextAlignVertical.top
                      : (textPayload.verticalAlign == TextVerticalAlign.middle
                            ? TextAlignVertical.center
                            : (textPayload.verticalAlign ==
                                      TextVerticalAlign.bottom
                                  ? TextAlignVertical.bottom
                                  : TextAlignVertical.top)),
                  onChanged: _updateInlineEditTransient,
                  onSubmitted: _editingFrameLabel
                      ? (_) => _commitInlineEdit()
                      : null,
                )
              : Material(
                  type: MaterialType.transparency,
                  child: TextField(
                    controller: _editController,
                    focusNode: _editFocusNode,
                    autofocus: true,
                    maxLines: null,
                    expands: true,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    textAlign: inlineTextAlign,
                    textAlignVertical: TextAlignVertical.center,
                    onChanged: _updateInlineEditTransient,
                    style: TextStyle(
                      color: shapePayload.labelColor,
                      fontSize: shapePayload.labelFontSize,
                      fontWeight: FontWeight.w500,
                    ),
                    cursorColor: shapePayload.labelColor,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
        ),
      ),
    ];
  }

  /*
  // Legacy coordinate-sensitive TextField styling is kept below for reference.
  Widget _legacyInlineEditorField() => TextField(
        controller: _editController,
        focusNode: _editFocusNode,
        autofocus: true,
        textAlign: inlineTextAlign,
      );
  */

  void _handleSecondaryTapUp(TapUpDetails details, CanvasTool activeTool) {
    if (activeTool == CanvasTool.pen || _activePenPoints.isNotEmpty) {
      _finalizePenPath(isClosed: false);
      return;
    }
    if (_connectorSourceNodeId != null) {
      setState(() => _connectorSourceNodeId = null);
      return;
    }

    final worldPos = ref
        .read(viewportProvider.notifier)
        .toWorld(details.localPosition);
    final nodes = ref.read(documentNodesProvider);
    final hit = CanvasHitTester.hitTest(nodes, worldPos);

    if (hit != null) {
      final selectedIds = ref.read(selectionProvider);
      if (!selectedIds.contains(hit.id)) {
        ref.read(selectionProvider.notifier).select(hit.id);
      }
      _showNodeContextMenu(details.globalPosition, hit, worldPos);
    } else {
      ref.read(selectionProvider.notifier).clear();
      _showEmptyCanvasContextMenu(details.globalPosition, worldPos);
    }
  }

  void _showModel3DContextMenu(Offset globalPosition, CanvasNode node) {
    final renderObject = _canvasKey.currentContext?.findRenderObject();
    final localPosition = renderObject is RenderBox
        ? renderObject.globalToLocal(globalPosition)
        : null;
    final worldPosition = localPosition == null
        ? Offset(node.x, node.y)
        : ref.read(viewportProvider.notifier).toWorld(localPosition);
    _showNodeContextMenu(globalPosition, node, worldPosition);
  }

  void _showNodeContextMenu(
    Offset screenPos,
    CanvasNode node,
    Offset worldPos,
  ) {
    final selectedIds = ref.read(selectionProvider).toList();
    final isMulti = selectedIds.length > 1;
    final hasVariants =
        !isMulti &&
        (node.variantOfNodeId != null ||
            ref
                .read(documentNodesProvider)
                .any((candidate) => candidate.variantOfNodeId == node.id));
    final mermaidSource = !isMulti ? _mermaidSourceForNode(node) : null;
    final mermaidPayload = mermaidSource?.payload;
    final mermaidIsNative =
        mermaidPayload is MermaidPayload &&
        mermaidPayload.renderMode == MermaidRenderMode.native;
    final mermaidConversionInFlight =
        mermaidSource != null &&
        ref.read(mermaidConversionInFlightProvider).contains(mermaidSource.id);

    showUiContextMenu<String>(
      context: context,
      position: screenPos,
      semanticsLabel: 'Canvas element actions',
      items: [
        const UiMenuAction<String>(
          value: 'ai_generate',
          label: 'Edit with AI',
          icon: Icons.auto_awesome,
        ),
        if (hasVariants)
          const UiMenuAction<String>(
            value: 'browse_variants',
            label: 'Browse Variants / Compare',
            icon: Icons.compare_arrows_outlined,
          ),
        const UiMenuAction<String>(
          value: 'create_component',
          label: 'Create Component (Ctrl+Alt+K)',
          icon: Icons.widgets_outlined,
        ),
        if (!_collaborationReadOnly && node.type == NodeType.vectorPath)
          const UiMenuAction<String>(
            value: 'vector_tools',
            label: 'Vector Path Tools',
            icon: Icons.polyline_outlined,
          ),
        const UiMenuAction<String>(
          value: 'duplicate',
          label: 'Duplicate (Ctrl+D)',
          icon: Icons.copy,
        ),
        if (!_collaborationReadOnly && mermaidSource != null) ...[
          const UiMenuAction<String>(
            value: 'edit_mermaid_source',
            label: 'Edit Mermaid Source',
            icon: Icons.account_tree_outlined,
          ),
          if (mermaidIsNative)
            UiMenuAction<String>(
              value: 'regenerate_mermaid',
              label: 'Regenerate Native Diagram',
              icon: Icons.refresh,
              enabled: !mermaidConversionInFlight,
            )
          else
            UiMenuAction<String>(
              value: 'convert_mermaid',
              label: 'Convert to Native',
              icon: Icons.transform_outlined,
              enabled: !mermaidConversionInFlight,
            ),
          if (mermaidIsNative)
            const UiMenuAction<String>(
              value: 'revert_mermaid',
              label: 'Revert to Mermaid Source',
              icon: Icons.undo,
            ),
        ],
        if (node.type == NodeType.group)
          const UiMenuAction<String>(
            value: 'ungroup',
            label: 'Ungroup (Ctrl+Shift+G)',
            icon: Icons.folder_open,
          )
        else if (isMulti)
          const UiMenuAction<String>(
            value: 'group',
            label: 'Group Selection (Ctrl+G)',
            icon: Icons.folder_outlined,
          ),
        const UiMenuAction<String>(
          value: 'rename',
          label: 'Rename / Edit Text',
          icon: Icons.edit_outlined,
        ),
        UiMenuAction<String>(
          value: 'toggle_lock',
          label: node.locked ? 'Unlock Element' : 'Lock Element',
          icon: node.locked ? Icons.lock_open : Icons.lock_outline,
        ),
        UiMenuAction<String>(
          value: 'toggle_visibility',
          label: node.visible ? 'Hide Element' : 'Show Element',
          icon: node.visible
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
        ),
        const UiMenuAction<String>(
          value: 'bring_to_front',
          label: 'Bring to Front',
          icon: Icons.flip_to_front,
        ),
        const UiMenuAction<String>(
          value: 'bring_forward',
          label: 'Bring Forward (Ctrl+])',
          icon: Icons.arrow_upward,
        ),
        const UiMenuAction<String>(
          value: 'send_backward',
          label: 'Send Backward (Ctrl+[)',
          icon: Icons.arrow_downward,
        ),
        const UiMenuAction<String>(
          value: 'send_to_back',
          label: 'Send to Back',
          icon: Icons.flip_to_back,
        ),
        const UiMenuAction<String>(
          value: 'delete',
          label: 'Delete (Del)',
          icon: Icons.delete_outline,
          destructive: true,
        ),
      ],
    ).then((choice) {
      if (choice == null) return;
      final ids = ref.read(selectionProvider).toList();

      switch (choice) {
        case 'ai_generate':
          _focusAiComposer();
          break;
        case 'vector_tools':
          unawaited(_openVectorPathTools(node, ids));
          break;
        case 'browse_variants':
          _openVariantBrowser(node);
          break;
        case 'create_component':
          _createComponentFromSelection(ids.isNotEmpty ? ids : [node.id]);
          break;
        case 'duplicate':
          final newIds = _duplicateNodesAndTrackUsage(
            ids.isNotEmpty ? ids : [node.id],
          );
          ref.read(selectionProvider.notifier).selectAll(newIds);
          break;
        case 'group':
          if (ids.length > 1) {
            final groupId = ref
                .read(documentNodesProvider.notifier)
                .groupNodes(ids);
            if (groupId != null) {
              ref.read(selectionProvider.notifier).select(groupId);
            }
          }
          break;
        case 'ungroup':
          if (node.type == NodeType.group) {
            final payload = node.payload as GroupPayload;
            ref.read(documentNodesProvider.notifier).ungroupNodes(node.id);
            ref
                .read(selectionProvider.notifier)
                .selectAll(payload.childNodeIds);
          }
          break;
        case 'edit_mermaid_source':
          if (mermaidSource != null) _openMermaidEditor(mermaidSource);
          break;
        case 'convert_mermaid':
          if (mermaidSource != null) {
            unawaited(_runMermaidConversion(mermaidSource, regenerate: false));
          }
          break;
        case 'regenerate_mermaid':
          if (mermaidSource != null) {
            unawaited(_runMermaidConversion(mermaidSource, regenerate: true));
          }
          break;
        case 'revert_mermaid':
          if (mermaidSource != null) {
            _showMermaidConversionResult(
              ref
                  .read(documentNodesProvider.notifier)
                  .revertMermaidToSource(mermaidSource.id),
            );
          }
          break;
        case 'rename':
          _showRenameDialog(node);
          break;
        case 'toggle_lock':
          ref
              .read(documentNodesProvider.notifier)
              .toggleLock(ids.isNotEmpty ? ids : [node.id]);
          break;
        case 'toggle_visibility':
          ref
              .read(documentNodesProvider.notifier)
              .toggleVisibility(ids.isNotEmpty ? ids : [node.id]);
          break;
        case 'bring_to_front':
          ref.read(documentNodesProvider.notifier).bringToFront(node.id);
          break;
        case 'bring_forward':
          ref.read(documentNodesProvider.notifier).bringForward(node.id);
          break;
        case 'send_backward':
          ref.read(documentNodesProvider.notifier).sendBackward(node.id);
          break;
        case 'send_to_back':
          ref.read(documentNodesProvider.notifier).sendToBack(node.id);
          break;
        case 'delete':
          ref
              .read(documentNodesProvider.notifier)
              .deleteNodes(ids.isNotEmpty ? ids : [node.id]);
          ref.read(selectionProvider.notifier).clear();
          break;
      }
    });
  }

  void _createComponentFromSelection(List<String> selectedIds) {
    if (selectedIds.isEmpty) return;
    final allNodes = ref.read(documentNodesProvider);
    final selectedNodes = allNodes
        .where((n) => selectedIds.contains(n.id))
        .toList();
    if (selectedNodes.isEmpty) return;

    // Calculate bounding box of selection
    double minX = selectedNodes.first.x;
    double minY = selectedNodes.first.y;
    double maxX = selectedNodes.first.x + selectedNodes.first.width;
    double maxY = selectedNodes.first.y + selectedNodes.first.height;

    for (final n in selectedNodes) {
      if (n.x < minX) minX = n.x;
      if (n.y < minY) minY = n.y;
      if (n.x + n.width > maxX) maxX = n.x + n.width;
      if (n.y + n.height > maxY) maxY = n.y + n.height;
    }

    final compWidth = math.max(120.0, maxX - minX);
    final compHeight = math.max(60.0, maxY - minY);

    // Transform selected nodes to relative local coordinates inside component
    final childTemplates = selectedNodes.map((n) {
      return n.copyWith(x: n.x - minX, y: n.y - minY);
    }).toList();

    // Remove old standalone nodes and insert new master Component node
    ref.read(documentNodesProvider.notifier).deleteNodes(selectedIds);

    final newCompId = const Uuid().v4();
    final newCompNode = CanvasNode(
      id: newCompId,
      type: NodeType.component,
      name: selectedNodes.length == 1
          ? (selectedNodes.first.name ?? 'Custom Component')
          : 'Grouped Component',
      x: minX,
      y: minY,
      width: compWidth,
      height: compHeight,
      payload: ComponentPayload(
        masterComponentId: newCompId,
        componentName: selectedNodes.length == 1
            ? (selectedNodes.first.name ?? 'Custom Component')
            : 'New Component',
        isMaster: true,
        templateChildren: childTemplates,
      ),
    );

    ref.read(documentNodesProvider.notifier).addNode(newCompNode);
    ref.read(selectionProvider.notifier).select(newCompId);

    showUiToast(
      context,
      'Created Master Component from ${selectedNodes.length} items!',
      variant: UiToastVariant.success,
      duration: const Duration(seconds: 2),
    );
  }

  void _saveDrawingStudioWorkspace(
    CanvasNode node,
    DrawingPaperPayload originalPayload,
    DrawingPaperPayload updatedPayload,
  ) {
    final originalBounds = DrawingPaperRenderer.workspaceBounds(
      originalPayload,
    );
    final updatedBounds = DrawingPaperRenderer.workspaceBounds(updatedPayload);
    final mappedBounds = DrawingPaperRenderer.mapWorkspaceBoundsToCanvas(
      originalWorkspaceBounds: originalBounds,
      updatedWorkspaceBounds: updatedBounds,
      canvasBounds: Rect.fromLTWH(node.x, node.y, node.width, node.height),
    );
    final workspacePayload = updatedPayload.copyWith(compositePreviewRef: null);
    final updatedNode = node.copyWith(
      x: mappedBounds.left,
      y: mappedBounds.top,
      width: mappedBounds.width,
      height: mappedBounds.height,
      payload: workspacePayload,
    );
    ref.read(documentNodesProvider.notifier).updateNode(updatedNode);
    _prepareDrawingPaperPreview(updatedNode, workspacePayload);
  }

  void _addAdjacentDrawingPaper(CanvasNode source, Offset direction) {
    if (_collaborationReadOnly) return;
    final payload = source.payload;
    if (payload is! DrawingPaperPayload) return;

    const gap = 32.0;
    final width = source.width;
    final height = source.height;
    final x = direction.dx > 0
        ? source.x + source.width + gap
        : direction.dx < 0
        ? source.x - width - gap
        : source.x + (source.width - width) / 2;
    final y = direction.dy > 0
        ? source.y + source.height + gap
        : direction.dy < 0
        ? source.y - height - gap
        : source.y + (source.height - height) / 2;
    final freshPayload = payload.copyWith(
      rasterDocumentId: const Uuid().v4(),
      rasterRevision: 0,
      compositePreviewRef: null,
      rasterOperations: const [],
      layers: const [DrawingLayer(id: 'layer_1', name: 'Background Layer')],
      activeLayerIndex: 0,
      activeSelection: null,
      rulers: const [],
      mangaStructure: null,
    );
    final node = CanvasNode(
      id: const Uuid().v4(),
      type: NodeType.drawingPaper,
      x: x,
      y: y,
      width: width,
      height: height,
      payload: freshPayload,
    );
    ref.read(documentNodesProvider.notifier).addNode(node);
    ref.read(selectionProvider.notifier).select(node.id);
  }

  void _showEmptyCanvasContextMenu(Offset screenPos, Offset worldPos) {
    showUiContextMenu<String>(
      context: context,
      position: screenPos,
      semanticsLabel: 'Canvas creation actions',
      items: const [
        UiMenuAction<String>(
          value: 'open_ai_engine',
          label: 'Focus AI prompt',
          icon: Icons.auto_awesome,
        ),
        UiMenuAction<String>(
          value: 'add_paper',
          label: 'Add Drawing Paper Studio',
          icon: Icons.note_add_outlined,
        ),
        UiMenuAction<String>(
          value: 'add_rectangle',
          label: 'Add Rectangle',
          icon: Icons.crop_square,
        ),
        UiMenuAction<String>(
          value: 'add_ellipse',
          label: 'Add Ellipse',
          icon: Icons.circle_outlined,
        ),
        UiMenuAction<String>(
          value: 'add_text',
          label: 'Add Text',
          icon: Icons.title,
        ),
        UiMenuAction<String>(
          value: 'add_sticky',
          label: 'Add Sticky Note',
          icon: Icons.sticky_note_2_outlined,
        ),
        UiMenuAction<String>(
          value: 'add_document',
          label: 'Add Document',
          icon: Icons.description_outlined,
        ),
        UiMenuAction<String>(
          value: 'add_frame',
          label: 'Add Frame Container',
          icon: Icons.crop_free,
        ),
        UiMenuAction<String>(
          value: 'add_diamond',
          label: 'Add Decision (Diamond)',
          icon: Icons.change_history,
        ),
        UiMenuAction<String>(
          value: 'add_cylinder',
          label: 'Add Database (Cylinder)',
          icon: Icons.storage_outlined,
        ),
        UiMenuAction<String>(
          value: 'add_todo',
          label: 'Add To-do List',
          icon: Icons.checklist_outlined,
        ),
        UiMenuAction<String>(
          value: 'add_table',
          label: 'Add Table Matrix',
          icon: Icons.table_chart_outlined,
        ),
        UiMenuAction<String>(
          value: 'add_column',
          label: 'Add Column Card',
          icon: Icons.view_column_outlined,
        ),
        UiMenuAction<String>(
          value: 'add_swatch',
          label: 'Add Color Swatch',
          icon: Icons.palette_outlined,
        ),
        UiMenuAction<String>(
          value: 'add_file',
          label: 'Add File Card',
          icon: Icons.insert_drive_file_outlined,
        ),
        UiMenuAction<String>(
          value: 'add_link',
          label: 'Add Link Bookmark',
          icon: Icons.link_outlined,
        ),
        UiMenuAction<String>(
          value: 'add_template',
          label: 'Insert Flowchart Template',
          icon: Icons.account_tree_outlined,
        ),
        UiMenuAction<String>(
          value: 'insert_saved_template',
          label: 'Insert Saved Template',
          icon: Icons.bookmark_border_outlined,
        ),
        UiMenuAction<String>(
          value: 'reset_view',
          label: 'Reset View (100%)',
          icon: Icons.center_focus_strong,
        ),
      ],
    ).then((choice) {
      if (choice == null) return;
      switch (choice) {
        case 'open_ai_engine':
          _focusAiComposer();
          break;
        case 'add_paper':
          if (!mounted) break;
          showUiDialog(
            context: context,
            builder: (ctx) => PaperTemplateDialog(
              onSelected: (paperPayload) {
                final double paperAspect =
                    paperPayload.pixelHeight / paperPayload.pixelWidth;
                const double targetWidth = 400.0;
                final double targetHeight = targetWidth * paperAspect;

                final paperNode = CanvasNode(
                  id: const Uuid().v4(),
                  type: NodeType.drawingPaper,
                  x: worldPos.dx - targetWidth / 2,
                  y: worldPos.dy - targetHeight / 2,
                  width: targetWidth,
                  height: targetHeight,
                  payload: paperPayload as NodePayload,
                );
                ref.read(documentNodesProvider.notifier).addNode(paperNode);
                ref.read(selectionProvider.notifier).select(paperNode.id);
              },
            ),
          );
          break;
        case 'add_rectangle':
          _spawnNodeAt(CanvasTool.rectangle, worldPos);
          break;
        case 'add_ellipse':
          _spawnNodeAt(CanvasTool.ellipse, worldPos);
          break;
        case 'add_text':
          _spawnNodeAt(CanvasTool.text, worldPos);
          break;
        case 'add_sticky':
          _spawnNodeAt(CanvasTool.stickyNote, worldPos);
          break;
        case 'add_document':
          _spawnNodeAt(CanvasTool.document, worldPos);
          break;
        case 'add_frame':
          if (!mounted) break;
          showUiDialog(
            context: context,
            builder: (ctx) => FramePresetDialog(
              onSelectPreset: (preset, isLandscape) {
                final w = preset.getWidth(isLandscape);
                final h = preset.getHeight(isLandscape);
                final frameNode = CanvasNode(
                  id: const Uuid().v4(),
                  type: NodeType.frame,
                  x: worldPos.dx - w / 2,
                  y: worldPos.dy - h / 2,
                  width: w,
                  height: h,
                  payload: FramePayload(
                    name: preset.name,
                    presetId: preset.id,
                    isLandscape: isLandscape,
                  ),
                );
                ref.read(documentNodesProvider.notifier).addNode(frameNode);
                ref.read(selectionProvider.notifier).select(frameNode.id);
              },
            ),
          );
          break;
        case 'add_diamond':
          _spawnNodeAt(CanvasTool.diamond, worldPos);
          break;
        case 'add_cylinder':
          _spawnNodeAt(CanvasTool.cylinder, worldPos);
          break;
        case 'add_todo':
          _spawnNodeAt(CanvasTool.todoList, worldPos);
          break;
        case 'add_table':
          _spawnNodeAt(CanvasTool.tableGrid, worldPos);
          break;
        case 'add_column':
          _spawnNodeAt(CanvasTool.columnContainer, worldPos);
          break;
        case 'add_swatch':
          _spawnNodeAt(CanvasTool.colorSwatch, worldPos);
          break;
        case 'add_file':
          _spawnNodeAt(CanvasTool.fileCard, worldPos);
          break;
        case 'add_link':
          _spawnNodeAt(CanvasTool.linkCard, worldPos);
          break;
        case 'add_template':
          _insertFlowchartTemplate();
          break;
        case 'insert_saved_template':
          unawaited(_insertSavedTemplateAt(worldPos));
          break;
        case 'reset_view':
          ref.read(viewportProvider.notifier).reset();
          break;
      }
    });
  }

  void _showRenameDialog(CanvasNode node) {
    final isText = node.payload is TextPayload;
    String currentName = '';
    if (isText) {
      currentName = (node.payload as TextPayload).text;
    } else if (node.name != null) {
      currentName = node.name!;
    } else if (node.payload is FramePayload) {
      currentName = (node.payload as FramePayload).name;
    } else if (node.payload is ComponentPayload) {
      currentName = (node.payload as ComponentPayload).componentName;
    } else if (node.payload is GroupPayload) {
      currentName = (node.payload as GroupPayload).name;
    }

    final controller = TextEditingController(text: currentName);

    showUiDialog(
      context: context,
      builder: (dialogContext) => UiDialog(
        semanticsLabel: isText ? 'Edit text' : 'Rename canvas element',
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md + AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isText ? 'Edit Text' : 'Rename ${node.type.name.toUpperCase()}',
                style: style.titleTextStyle,
              ),
              const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
              UiTextField(
                controller: controller,
                autofocus: true,
                hint: isText ? 'Enter text...' : 'Enter layer name...',
                onSubmitted: (_) =>
                    _saveRename(dialogContext, controller, node, isText),
              ),
              const SizedBox(height: AppSpacing.lg + AppSpacing.xxs),
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
                    onPressed: () =>
                        _saveRename(dialogContext, controller, node, isText),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  void _saveRename(
    BuildContext dialogContext,
    TextEditingController controller,
    CanvasNode node,
    bool isText,
  ) {
    final newText = controller.text.trim();
    if (newText.isEmpty) return;
    if (isText) {
      final updatedPayload = (node.payload as TextPayload).copyWith(
        text: newText,
      );
      ref
          .read(documentNodesProvider.notifier)
          .updateNode(node.copyWith(payload: updatedPayload));
    } else {
      ref
          .read(documentNodesProvider.notifier)
          .updateNode(node.copyWith(name: newText));
    }
    Navigator.pop(dialogContext);
  }

  Future<void> _openFilePayload(CanvasNode node, FilePayload payload) =>
      openFilePreview(
        context,
        payload,
        fileArtifactStore: _fileArtifactStore,
        onAnnotationsChanged: (annotations) {
          ref
              .read(documentNodesProvider.notifier)
              .updateNode(
                node.copyWith(
                  payload: payload.copyWith(pdfAnnotations: annotations),
                ),
              );
        },
      );

  void _handleDoubleTap(CanvasTool activeTool) {
    _chartTapTimer?.cancel();
    _chartTapTimer = null;
    if (activeTool != CanvasTool.select && activeTool != CanvasTool.text) {
      return;
    }
    final worldPos = ref
        .read(viewportProvider.notifier)
        .toWorld(_lastTapLocalPosition);
    if (activeTool == CanvasTool.select) {
      _handleConnectorDoubleTap(worldPos);
      final connectorControl = CanvasHitTester.hitTestConnectorControl(
        ref.read(documentEdgesProvider),
        {for (final node in ref.read(documentNodesProvider)) node.id: node},
        ref.read(selectionProvider),
        worldPos,
        zoom: ref.read(viewportProvider).zoom,
      );
      if (connectorControl != null) return;
    }
    final hit = CanvasHitTester.hitTest(
      ref.read(documentNodesProvider),
      worldPos,
    );
    if (hit == null) return;
    ref.read(selectionProvider.notifier).select(hit.id);

    if (hit.type == NodeType.fileCard && hit.payload is FilePayload) {
      _openFilePayload(hit, hit.payload as FilePayload);
      return;
    }

    if (hit.type == NodeType.mermaid) {
      _openMermaidEditor(hit);
      return;
    }

    if (hit.type == NodeType.chart && hit.payload is ChartPayload) {
      _openChartDataEditor(hit);
      return;
    }

    if (hit.type == NodeType.text) {
      _startInlineEdit(hit, frameLabel: false);
      return;
    }

    if (hit.type == NodeType.sketchCard && hit.payload is SketchCardPayload) {
      showUiDialog(
        context: context,
        builder: (ctx) => SketchCardEditorDialog(
          node: hit,
          onSave: (updatedPayload) {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(hit.copyWith(payload: updatedPayload));
          },
        ),
      );
      return;
    }

    final currentPins =
        hit.type == NodeType.annotatedImage &&
            hit.payload is AnnotatedImagePayload
        ? (hit.payload as AnnotatedImagePayload).pins
        : hit.pins;
    if (currentPins.isNotEmpty) {
      final local = Offset(worldPos.dx - hit.x, worldPos.dy - hit.y);
      int targetPinIdx = 0;
      for (int i = 0; i < currentPins.length; i++) {
        if ((currentPins[i].position - local).distance <= 24.0) {
          targetPinIdx = i;
          break;
        }
      }
      _showAnnotationPinEditor(hit, targetPinIdx);
      return;
    }

    if (hit.type == NodeType.drawing && hit.payload is DrawingPayload) {
      final dp = hit.payload as DrawingPayload;
      if (dp.points.isNotEmpty) {
        final localPos = Offset(worldPos.dx - hit.x, worldPos.dy - hit.y);

        // Find closest segment index to insert new point with precise projection
        int insertIndex = dp.points.length - 1;
        Offset insertionPoint = localPos;
        double minDistance = double.infinity;

        for (int i = 0; i < dp.points.length - 1; i++) {
          final p1 = dp.points[i];
          final p2 = dp.points[i + 1];
          final l2 =
              (p1.dx - p2.dx) * (p1.dx - p2.dx) +
              (p1.dy - p2.dy) * (p1.dy - p2.dy);
          final t = l2 == 0.0
              ? 0.0
              : math.max(
                  0.0,
                  math.min(
                    1.0,
                    ((localPos.dx - p1.dx) * (p2.dx - p1.dx) +
                            (localPos.dy - p1.dy) * (p2.dy - p1.dy)) /
                        l2,
                  ),
                );
          final proj = Offset(
            p1.dx + t * (p2.dx - p1.dx),
            p1.dy + t * (p2.dy - p1.dy),
          );
          final dist = (localPos - proj).distance;
          if (dist < minDistance) {
            minDistance = dist;
            insertIndex = i + 1;
            insertionPoint = proj;
          }
        }

        final newPoints = List<Offset>.from(dp.points)
          ..insert(insertIndex, insertionPoint);
        final newIndices = <int>{
          ...dp.controlPointIndices.map(
            (idx) => idx >= insertIndex ? idx + 1 : idx,
          ),
          insertIndex,
        }.toList()..sort();

        ref
            .read(documentNodesProvider.notifier)
            .updateNode(
              hit.copyWith(
                payload: dp.copyWith(
                  points: newPoints,
                  controlPointIndices: newIndices,
                ),
              ),
            );
      }
      return;
    }

    if (hit.type == NodeType.frame) {
      _startInlineEdit(hit, frameLabel: true);
      return;
    }

    if (hit.type == NodeType.text || hit.type == NodeType.stickyNote) {
      _startInlineEdit(hit, frameLabel: false);
      return;
    }

    if (hit.type == NodeType.drawingPaper) {
      final payload = hit.payload as DrawingPaperPayload;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => DrawingStudioScreen(
            initialPayload: payload,
            onSaveAndExit: (updated) {
              _saveDrawingStudioWorkspace(hit, payload, updated);
            },
          ),
        ),
      );
      return;
    }

    if (hit.type == NodeType.tableGrid) {
      TableMatrixEditorModal.show(
        context,
        node: hit,
        onUpdate: (updatedNode) {
          ref.read(documentNodesProvider.notifier).updateNode(updatedNode);
        },
      );
      return;
    }

    if (hit.type == NodeType.component) {
      ComponentEditorModal.show(
        context,
        node: hit,
        onUpdate: (updatedNode) {
          ref.read(documentNodesProvider.notifier).updateNode(updatedNode);
        },
      );
      return;
    }

    if (hit.type == NodeType.nestedBoard) {
      NestedBoardScreen.show(
        context,
        node: hit,
        onUpdate: (updatedNode) {
          ref.read(documentNodesProvider.notifier).updateNode(updatedNode);
        },
      );
      return;
    }

    if (hit.type == NodeType.columnContainer) {
      ColumnCardEditorModal.show(
        context,
        node: hit,
        onUpdate: (updatedNode) {
          ref.read(documentNodesProvider.notifier).updateNode(updatedNode);
        },
      );
      return;
    }

    if (hit.type == NodeType.todoList) {
      TodoListEditorModal.show(
        context,
        node: hit,
        onUpdate: (updatedNode) {
          ref.read(documentNodesProvider.notifier).updateNode(updatedNode);
        },
      );
      return;
    }

    if (hit.type == NodeType.document) {
      _openDocumentEditor(hit);
      return;
    }

    if (hit.type == NodeType.linkCard) {
      _openLinkInApp(hit);
      return;
    }

    if (hit.type == NodeType.videoCard) {
      _openVideoPlayer(hit);
      return;
    }

    if (hit.type == NodeType.audioCard) {
      _openAudioPlayer(hit);
      return;
    }

    if (hit.type == NodeType.mapCard) {
      _openMapViewer(hit);
      return;
    }

    if (hit.type == NodeType.embed) {
      _openEmbed(hit);
      return;
    }

    if (hit.type == NodeType.image) {
      _openImageCrop(hit);
      return;
    }

    if (hit.payload is ShapePayload) {
      _startInlineEdit(hit, frameLabel: false);
    }
  }

  void _showAnnotationPinEditor(CanvasNode node, int pinIndex) {
    final bool isAnnImage =
        node.type == NodeType.annotatedImage &&
        node.payload is AnnotatedImagePayload;
    final List<ImageAnnotationPin> pinsList = isAnnImage
        ? (node.payload as AnnotatedImagePayload).pins
        : node.pins;

    if (pinIndex < 0 || pinIndex >= pinsList.length) return;

    final pin = pinsList[pinIndex];
    showUiDialog(
      context: context,
      builder: (ctx) => AnnotationPinEditorDialog(
        pin: pin,
        pinIndex: pinIndex,
        onSave: (updatedPin) {
          final updatedPins = List<ImageAnnotationPin>.from(pinsList);
          updatedPins[pinIndex] = updatedPin;
          if (isAnnImage) {
            final ap = node.payload as AnnotatedImagePayload;
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: ap.copyWith(pins: updatedPins)),
                );
          } else {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(node.copyWith(pins: updatedPins));
          }
        },
        onDelete: () {
          final updatedPins = List<ImageAnnotationPin>.from(pinsList)
            ..removeAt(pinIndex);
          if (isAnnImage) {
            final ap = node.payload as AnnotatedImagePayload;
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(payload: ap.copyWith(pins: updatedPins)),
                );
          } else {
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(node.copyWith(pins: updatedPins));
          }
        },
      ),
    );
  }

  Future<void> _startVideoMeeting() async {
    final configuration = ref.read(meetingConfigurationProvider);
    if (!configuration.isAvailable || !_collaborationCanManageRoom) return;
    final controller = ref.read(
      meetingControllerProvider(widget.projectId).notifier,
    );
    try {
      final session = await controller.startMeeting(
        maxParticipants: configuration.maxParticipants,
      );
      if (!mounted) return;
      context.push(
        '/meeting/${Uri.encodeComponent(session.id)}?projectId=${Uri.encodeQueryComponent(widget.projectId)}',
      );
    } on MeetingControllerException catch (error) {
      if (!mounted) return;
      showUiToast(context, error.message, variant: UiToastVariant.error);
    } catch (_) {
      if (!mounted) return;
      showUiToast(
        context,
        'Video meeting tidak tersedia. Coba lagi.',
        variant: UiToastVariant.error,
      );
    }
  }

  Future<void> _openMeetingEntry() async {
    final configuration = ref.read(meetingConfigurationProvider);
    if (!configuration.isAvailable) return;
    final meetingState = ref.read(meetingControllerProvider(widget.projectId));
    final meetingId = meetingState.meetingId;
    if (meetingId == null || meetingId.isEmpty) {
      await _startVideoMeeting();
      return;
    }
    if (!mounted) return;
    context.push(
      '/meeting/${Uri.encodeComponent(meetingId)}?projectId=${Uri.encodeQueryComponent(widget.projectId)}',
    );
  }

  Future<void> _openRoomDialog() async {
    if (!_collaborationCanManageRoom) return;
    final cachedRoom = await CollaborationRoomCache.read(widget.projectId);
    if (!mounted) return;
    final sync = ref.read(supabaseSyncServiceProvider);
    final controller = TextEditingController();
    CanvasRoom? room = cachedRoom;
    bool creating = false;
    var selectedDuration = cachedRoom?.expiresAt == null ? 'never' : '1d';

    DateTime? expirationFor(String value) => switch (value) {
      '1h' => DateTime.now().add(const Duration(hours: 1)),
      '1d' => DateTime.now().add(const Duration(days: 1)),
      '7d' => DateTime.now().add(const Duration(days: 7)),
      _ => null,
    };

    String expirationLabel(CanvasRoom value) {
      final expiresAt = value.expiresAt;
      if (expiresAt == null) return 'Room aktif tanpa batas waktu.';
      return 'Aktif sampai ${expiresAt.toLocal().toString().split('.').first}';
    }

    if (room != null) controller.text = room.roomCode;

    showUiDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => UiDialog(
          semanticsLabel: 'Collaboration room',
          builder: (context, style) => Padding(
            padding: const EdgeInsets.all(AppSpacing.md + AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('COLLABORATION ROOM', style: style.titleTextStyle),
                const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
                Text(
                  'Buat Room ID lalu bagikan enam angka ini kepada collaborator. Room disimpan sampai host mencabut atau masa berlakunya habis.',
                  style: style.bodyTextStyle.copyWith(fontSize: 11),
                ),
                const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
                UiTextField(
                  controller: controller,
                  label: 'Room ID',
                  textAlign: TextAlign.center,
                  readOnly: true,
                ),
                const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
                UiSelect<String>(
                  label: 'Room lifetime',
                  items: const {
                    '1 hour': '1h',
                    '1 day': '1d',
                    '7 days': '7d',
                    'Never': 'never',
                  },
                  value: selectedDuration,
                  enabled: !creating,
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedDuration = value);
                    }
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                if (room != null)
                  Text(
                    expirationLabel(room!),
                    style: style.bodyTextStyle.copyWith(fontSize: 11),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Consumer(
                  builder: (context, ref, _) {
                    final collaboration = ref.watch(
                      collaborationSessionProvider(widget.projectId),
                    );
                    return Text(
                      'Peserta aktif: ${collaboration.participantCount}',
                      style: style.bodyTextStyle.copyWith(fontSize: 11),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (room != null)
                      UiButton(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: room!.roomCode),
                          );
                          if (dialogContext.mounted) {
                            showUiToast(
                              dialogContext,
                              'Room ID copied.',
                              variant: UiToastVariant.success,
                            );
                          }
                        },
                        variant: UiButtonVariant.ghost,
                        prefix: const Icon(Icons.copy_outlined),
                        child: const Text('Copy'),
                      ),
                    if (room != null) const SizedBox(width: AppSpacing.sm),
                    if (room != null)
                      UiButton(
                        onPressed: creating
                            ? null
                            : () async {
                                final revokeClient = ref.read(
                                  supabaseClientProvider,
                                );
                                final expectedAccountId =
                                    revokeClient?.auth.currentUser?.id ??
                                    revokeClient?.auth.currentSession?.user.id;
                                if (expectedAccountId == null) return;
                                String? currentAccountId() {
                                  final client = ref.read(
                                    supabaseClientProvider,
                                  );
                                  return client?.auth.currentUser?.id ??
                                      client?.auth.currentSession?.user.id;
                                }

                                setDialogState(() => creating = true);
                                try {
                                  try {
                                    await _collaborationSession
                                        ?.persistSnapshot();
                                  } catch (error) {
                                    debugPrint(
                                      '[CanvasEditorSurface] Room revoke snapshot failed: $error',
                                    );
                                  }
                                  if (currentAccountId() != expectedAccountId) {
                                    throw StateError(
                                      'Collaboration account changed during room revoke.',
                                    );
                                  }
                                  await sync.revokeCollaborationRoom(
                                    widget.projectId,
                                    expectedUserId: expectedAccountId,
                                  );
                                  if (currentAccountId() != expectedAccountId) {
                                    throw StateError(
                                      'Collaboration account changed during room revoke.',
                                    );
                                  }
                                  await CollaborationRoomCache.clear(
                                    widget.projectId,
                                    expectedAccountId: expectedAccountId,
                                  );
                                  if (currentAccountId() != expectedAccountId) {
                                    throw StateError(
                                      'Collaboration account changed during room revoke.',
                                    );
                                  }
                                  await ref
                                      .read(homeProjectsProvider.notifier)
                                      .clearCollaborationRoom(
                                        widget.projectId,
                                        expectedAccountId: expectedAccountId,
                                      );
                                  if (currentAccountId() != expectedAccountId) {
                                    throw StateError(
                                      'Collaboration account changed before room disable.',
                                    );
                                  }
                                  await _collaborationSession?.disableRoom();
                                  if (!dialogContext.mounted) return;
                                  setDialogState(() {
                                    room = null;
                                    controller.clear();
                                    creating = false;
                                  });
                                } catch (_) {
                                  if (!dialogContext.mounted) return;
                                  setDialogState(() => creating = false);
                                  showUiToast(
                                    dialogContext,
                                    'Could not revoke the collaboration room.',
                                    variant: UiToastVariant.error,
                                  );
                                }
                              },
                        variant: UiButtonVariant.ghost,
                        child: const Text('Revoke'),
                      ),
                    const SizedBox(width: AppSpacing.sm),
                    UiButton(
                      onPressed: creating
                          ? null
                          : () async {
                              final client = ref.read(supabaseClientProvider);
                              final startingAccountId =
                                  client?.auth.currentUser?.id ??
                                  client?.auth.currentSession?.user.id;
                              if (!sync.isAuthenticated ||
                                  startingAccountId == null) {
                                showUiToast(
                                  dialogContext,
                                  'Sign in before creating a collaboration room.',
                                  variant: UiToastVariant.error,
                                );
                                return;
                              }
                              setDialogState(() => creating = true);
                              try {
                                final projects = await ref
                                    .read(localStorageServiceProvider)
                                    .getProjects();
                                final metadata = projects
                                    .where(
                                      (project) =>
                                          project.id == widget.projectId,
                                    )
                                    .firstOrNull;
                                final metadataClient = ref.read(
                                  supabaseClientProvider,
                                );
                                final metadataAccountId =
                                    metadataClient?.auth.currentUser?.id ??
                                    metadataClient
                                        ?.auth
                                        .currentSession
                                        ?.user
                                        .id;
                                if (metadataAccountId != startingAccountId) {
                                  throw StateError(
                                    'Collaboration account changed while loading project metadata.',
                                  );
                                }
                                if (metadata == null ||
                                    metadata.cloudOwnerId !=
                                        startingAccountId ||
                                    metadata.isCollaborationRoom ||
                                    metadata.status == ProjectStatus.trashed) {
                                  throw const SyncException(
                                    'Only a verified cloud owner can create a collaboration room.',
                                  );
                                }
                                await sync.verifyProjectOwnership(
                                  widget.projectId,
                                  expectedUserId: startingAccountId,
                                );
                                final ownerVerifiedClient = ref.read(
                                  supabaseClientProvider,
                                );
                                final ownerVerifiedAccountId =
                                    ownerVerifiedClient?.auth.currentUser?.id ??
                                    ownerVerifiedClient
                                        ?.auth
                                        .currentSession
                                        ?.user
                                        .id;
                                if (ownerVerifiedAccountId !=
                                    startingAccountId) {
                                  throw StateError(
                                    'Collaboration account changed during project ownership verification.',
                                  );
                                }
                                final verifiedClient = ref.read(
                                  supabaseClientProvider,
                                );
                                final verifiedAccountId =
                                    verifiedClient?.auth.currentUser?.id ??
                                    verifiedClient
                                        ?.auth
                                        .currentSession
                                        ?.user
                                        .id;
                                if (verifiedAccountId != startingAccountId) {
                                  throw StateError(
                                    'Collaboration account changed during project ownership verification.',
                                  );
                                }
                                await sync.syncDocumentSnapshot(
                                  _currentCanvasDocument(),
                                  expectedUserId: startingAccountId,
                                );
                                final currentClient = ref.read(
                                  supabaseClientProvider,
                                );
                                final currentAccountId =
                                    currentClient?.auth.currentUser?.id ??
                                    currentClient?.auth.currentSession?.user.id;
                                if (currentAccountId != startingAccountId) {
                                  throw StateError(
                                    'Collaboration account changed during room creation.',
                                  );
                                }
                                final created = await sync
                                    .createCollaborationRoom(
                                      projectId: widget.projectId,
                                      projectName: widget.projectName,
                                      expiresAt: expirationFor(
                                        selectedDuration,
                                      ),
                                      expectedUserId: startingAccountId,
                                    );
                                final postCreateClient = ref.read(
                                  supabaseClientProvider,
                                );
                                final postCreateAccountId =
                                    postCreateClient?.auth.currentUser?.id ??
                                    postCreateClient
                                        ?.auth
                                        .currentSession
                                        ?.user
                                        .id;
                                if (postCreateAccountId != startingAccountId) {
                                  throw StateError(
                                    'Collaboration account changed after room creation.',
                                  );
                                }
                                try {
                                  await CollaborationRoomCache.write(
                                    created,
                                    accountId: startingAccountId,
                                  );
                                } catch (error) {
                                  debugPrint(
                                    '[CanvasEditorSurface] Room cache write failed: $error',
                                  );
                                }
                                await ref
                                    .read(homeProjectsProvider.notifier)
                                    .rememberCollaborationRoom(
                                      created,
                                      expectedAccountId: startingAccountId,
                                    );
                                if (!dialogContext.mounted) return;
                                setDialogState(() {
                                  room = created;
                                  controller.text = created.roomCode;
                                  creating = false;
                                });
                              } catch (error) {
                                if (!dialogContext.mounted) return;
                                setDialogState(() => creating = false);
                                showUiToast(
                                  dialogContext,
                                  error is SyncException
                                      ? error.message
                                      : 'Could not create the collaboration room.',
                                  variant: UiToastVariant.error,
                                );
                              }
                            },
                      child: Text(
                        room == null ? 'Create Room ID' : 'Rotate ID',
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    UiButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      variant: UiButtonVariant.ghost,
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  void _openBoardHistoryDialog() {
    showUiDialog(
      context: context,
      builder: (dialogContext) => Consumer(
        builder: (context, ref, _) {
          final versions = ref.watch(
            persistedVersionsProvider(widget.projectId),
          );
          final autosaves = ref.watch(
            persistedAutoCheckpointsProvider(widget.projectId),
          );
          final dialogPadding = AppResponsive.dialogPadding(context);
          final dialogWidth = AppResponsive.dialogWidth(
            context,
            preferred: 390,
          );
          final dialogHeight = AppResponsive.dialogHeight(
            context,
            preferred: 440,
          );
          final contentWidth = (dialogWidth - dialogPadding.horizontal)
              .clamp(0.0, double.infinity)
              .toDouble();
          final contentHeight = (dialogHeight - dialogPadding.vertical)
              .clamp(0.0, double.infinity)
              .toDouble();
          return UiDialog(
            semanticsLabel: 'Board history',
            constraints: AppResponsive.dialogConstraints(
              context,
              maxWidth: 390,
              maxHeight: 440,
            ),
            builder: (context, style) => Padding(
              padding: dialogPadding,
              child: SizedBox(
                key: const ValueKey('board-history-content'),
                width: contentWidth,
                height: contentHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'BOARD HISTORY',
                            style: style.titleTextStyle,
                          ),
                        ),
                        if (_collaborationCanManageRoom)
                          UiIconButton(
                            icon: Icons.bookmark_add_outlined,
                            tooltip: 'Save named version',
                            onPressed: () => _showSaveVersionDialog(context),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                    Text(
                      'Named versions and autosave checkpoints survive restart.',
                      style: style.bodyTextStyle.copyWith(fontSize: 11),
                    ),
                    const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
                    Expanded(
                      child: versions.when(
                        loading: () => const UiLoadingState(),
                        error: (error, _) =>
                            Center(child: Text('History unavailable: $error')),
                        data: (savedVersions) => autosaves.when(
                          loading: () => const UiLoadingState(),
                          error: (error, _) => Center(
                            child: Text('Autosave history unavailable: $error'),
                          ),
                          data: (autoCheckpoints) {
                            final records =
                                [...savedVersions, ...autoCheckpoints]..sort(
                                  (a, b) => b.timestamp.compareTo(a.timestamp),
                                );
                            if (records.isEmpty) {
                              return Center(
                                child: Text(
                                  'No snapshots yet.\nSave a named version to create a recovery point.',
                                  textAlign: TextAlign.center,
                                  style: style.bodyTextStyle,
                                ),
                              );
                            }
                            return ListView.builder(
                              itemCount: records.length,
                              itemBuilder: (context, index) {
                                final snap = records[index];
                                final named = savedVersions.any(
                                  (item) => item.id == snap.id,
                                );
                                final title = named
                                    ? snap.description
                                    : 'Autosave';
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.xxs,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: UiButton(
                                          onPressed: () => _openRestoreOptions(
                                            snap,
                                            dialogContext,
                                          ),
                                          variant: UiButtonVariant.ghost,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                named
                                                    ? Icons.bookmark
                                                    : Icons.restore,
                                                size: 16,
                                              ),
                                              const SizedBox(
                                                width:
                                                    AppSpacing.md -
                                                    AppSpacing.xxs,
                                              ),
                                              ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                      maxWidth: 230,
                                                    ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      title,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    Text(
                                                      '${_formatTimestamp(snap.timestamp)} · ${snap.document.nodes.length} nodes',
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: context
                                                            .appTokens
                                                            .textMuted,
                                                        fontSize: 10,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      UiIconButton(
                                        icon: Icons.compare_arrows_outlined,
                                        tooltip: 'Compare $title',
                                        onPressed: () => _openVersionDiff(snap),
                                        variant: UiButtonVariant.outline,
                                        size: UiButtonSize.sm,
                                      ),
                                      UiIconButton(
                                        icon: Icons.call_split_outlined,
                                        tooltip: 'Create branch from $title',
                                        onPressed: () =>
                                            _branchDocumentSnapshot(snap),
                                        variant: UiButtonVariant.outline,
                                        size: UiButtonSize.sm,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
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
          );
        },
      ),
    );
  }

  Future<void> _openVersionDiff(DocumentSnapshotRecord snapshot) =>
      showDocumentVersionDiff(
        context,
        current: _currentCanvasDocument(),
        snapshot: snapshot,
      );

  Future<void> _openRestoreOptions(
    DocumentSnapshotRecord snapshot,
    BuildContext historyContext,
  ) async {
    if (_collaborationReadOnly) return;
    final mode = await showUiDialog<_DocumentRestoreMode>(
      context: historyContext,
      builder: (dialogContext) => UiDialog(
        semanticsLabel: 'Restore version options',
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md + AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('RESTORE VERSION', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.sm),
              Text(
                snapshot.description.trim().isEmpty
                    ? 'Autosave'
                    : snapshot.description.trim(),
                style: style.bodyTextStyle,
              ),
              const SizedBox(height: AppSpacing.lg),
              UiButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                ).pop(_DocumentRestoreMode.inPlace),
                prefix: const Icon(Icons.restore_rounded, size: 16),
                child: const Text('Restore in place'),
              ),
              const SizedBox(height: AppSpacing.sm),
              UiButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(_DocumentRestoreMode.copy),
                variant: UiButtonVariant.outline,
                prefix: const Icon(Icons.call_split_outlined, size: 16),
                child: const Text('Restore as branch'),
              ),
              const SizedBox(height: AppSpacing.sm),
              UiButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                variant: UiButtonVariant.ghost,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || mode == null) return;
    switch (mode) {
      case _DocumentRestoreMode.inPlace:
        if (!historyContext.mounted) return;
        await _restoreDocumentSnapshot(snapshot, historyContext);
      case _DocumentRestoreMode.copy:
        await _branchDocumentSnapshot(snapshot);
    }
  }

  Future<void> _branchDocumentSnapshot(DocumentSnapshotRecord snapshot) async {
    if (_collaborationReadOnly) return;
    try {
      final storage = ref.read(localStorageServiceProvider);
      final hydrated = await storage.hydrateDocument(snapshot.document);
      final description = snapshot.description.trim().isEmpty
          ? 'Autosave'
          : snapshot.description.trim();
      final branch = await storage.duplicateProjectFromDocument(
        widget.projectId,
        hydrated,
        name: '${widget.projectName} · $description',
      );
      if (mounted) showUiToast(context, 'Branch dibuat: ${branch.name}');
    } catch (error) {
      if (mounted) {
        showUiToast(
          context,
          'Branch gagal dibuat: $error',
          variant: UiToastVariant.error,
        );
      }
    }
  }

  Future<void> _showSaveVersionDialog(BuildContext context) async {
    if (_collaborationReadOnly) return;
    final controller = TextEditingController();
    await showUiDialog(
      context: context,
      builder: (dialogContext) => UiDialog(
        semanticsLabel: 'Save named version',
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md + AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('SAVE VERSION', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
              UiTextField(
                controller: controller,
                label: 'Version name',
                hint: 'e.g. Client review ready',
                autofocus: true,
              ),
              const SizedBox(height: AppSpacing.lg + AppSpacing.xxs),
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
                    onPressed: () async {
                      final description = controller.text.trim();
                      if (description.isEmpty) return;
                      try {
                        await ref
                            .read(
                              persistedVersionsProvider(
                                widget.projectId,
                              ).notifier,
                            )
                            .save(
                              _currentCanvasDocument(),
                              description: description,
                              commandReplay: ref
                                  .read(historyProvider.notifier)
                                  .exportReplay(widget.projectId),
                            );
                      } catch (error) {
                        if (dialogContext.mounted) {
                          showUiToast(
                            dialogContext,
                            'Version save failed: $error',
                            variant: UiToastVariant.error,
                          );
                        }
                        return;
                      }
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                    },
                    child: const Text('Save version'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
  }

  CanvasDocument _currentCanvasDocument() {
    final autosave = _autosaveController;
    if (autosave?.isInitialized == true) return autosave!.currentDocument();
    return CanvasDocument(
      projectId: widget.projectId,
      nodes: ref.read(documentNodesProvider),
      edges: ref.read(documentEdgesProvider),
      viewport: ref.read(viewportProvider),
      navigation: _navigationState.toJson(),
      assets: ref.read(documentAssetsProvider),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _restoreDocumentSnapshot(
    DocumentSnapshotRecord snapshot,
    BuildContext dialogContext,
  ) async {
    if (_collaborationReadOnly) return;
    try {
      final storage = ref.read(localStorageServiceProvider);
      await storage.saveDocument(_currentCanvasDocument());
      await storage.duplicateProject(
        widget.projectId,
        name: '${widget.projectName} before restore',
      );
      final hydrated = await storage.hydrateDocument(snapshot.document);
      final restored = hydrated.copyWith(
        projectId: widget.projectId,
        updatedAt: DateTime.now(),
      );
      final autosave = _autosaveController;
      if (autosave != null) {
        await autosave.restoreDocument(restored);
      } else {
        ref.read(documentNodesProvider.notifier).setNodes(restored.nodes);
        ref.read(documentEdgesProvider.notifier).setEdges(restored.edges);
        ref
            .read(viewportProvider.notifier)
            .setPosition(restored.viewport.x, restored.viewport.y);
        ref.read(viewportProvider.notifier).setZoom(restored.viewport.zoom);
        await storage.saveDocument(restored);
      }
      if (dialogContext.mounted) {
        Navigator.pop(dialogContext);
      }
      if (mounted) showUiToast(context, 'Restored with a safety copy.');
    } catch (error) {
      if (mounted) {
        showUiToast(
          context,
          'Restore failed: $error',
          variant: UiToastVariant.error,
        );
      }
    }
  }

  String _formatTimestamp(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  List<CanvasCommandDescriptor> _canvasCommandDescriptors({
    required bool canUndo,
    required bool canRedo,
    required bool hasSelection,
  }) {
    final commands = CanvasCommandCatalog.core(
      readOnly: _collaborationReadOnly,
      canUndo: canUndo,
      canRedo: canRedo,
      hasSelection: hasSelection,
    );
    final toolCommands = CanvasTool.values
        .map(
          (tool) => CanvasCommandDescriptor(
            id: 'tool.${tool.name}',
            title: 'Use ${_toolCommandLabel(tool)} tool',
            description: 'Switch the active canvas tool.',
            category: CanvasCommandCategory.create,
            enabled: !_collaborationReadOnly || tool == CanvasTool.select,
            requiresEdit: tool != CanvasTool.select,
            keywords: [tool.name],
          ),
        )
        .toList(growable: false);
    return [...commands, ...toolCommands];
  }

  String _toolCommandLabel(CanvasTool tool) {
    final words = tool.name
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll('_', ' ')
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
    return words;
  }

  void _handleCanvasCommand(String commandId) {
    if (commandId.startsWith('tool.')) {
      final toolName = commandId.substring('tool.'.length);
      final tool = CanvasTool.values
          .where((item) => item.name == toolName)
          .firstOrNull;
      if (tool != null &&
          (!_collaborationReadOnly || tool == CanvasTool.select)) {
        ref.read(activeToolProvider.notifier).setTool(tool);
      }
      return;
    }
    switch (commandId) {
      case 'canvas.search':
        _openSearchDialog();
        return;
      case 'canvas.zoom_to_content':
        _zoomToCanvasContent();
        return;
      case 'canvas.viewport_bookmarks':
        unawaited(_openViewportBookmarks());
        return;
      case 'canvas.toggle_focus':
        _toggleCanvasFocusMode();
        return;
      case 'history.undo':
        if (!_collaborationReadOnly) {
          ref.read(documentNodesProvider.notifier).undo();
        }
        return;
      case 'history.redo':
        if (!_collaborationReadOnly) {
          ref.read(documentNodesProvider.notifier).redo();
        }
        return;
      case 'selection.duplicate':
        if (_collaborationReadOnly) return;
        final ids = ref.read(selectionProvider).toList(growable: false);
        if (ids.isEmpty) return;
        final duplicated = _duplicateNodesAndTrackUsage(ids);
        ref.read(selectionProvider.notifier).selectAll(duplicated);
        return;
      case 'selection.delete':
        _deleteSelectedNodes();
        return;
      case 'selection.group':
        if (_collaborationReadOnly) return;
        final ids = ref.read(selectionProvider).toList(growable: false);
        final groupId = ref
            .read(documentNodesProvider.notifier)
            .groupNodes(ids);
        if (groupId != null) {
          ref.read(selectionProvider.notifier).select(groupId);
        }
        return;
      case 'navigation.new_page':
        unawaited(_createCanvasPage());
        return;
      case 'navigation.rename_page':
        unawaited(_renameActiveCanvasPage());
        return;
      case 'view.precision_settings':
        unawaited(_openCanvasPrecisionSettings());
        return;
      case 'view.shortcut_help':
        _openShortcutHelp();
        return;
      case 'selection.align':
        _openSelectionArrangeMenu();
        return;
    }
  }

  void _openCanvasCommandPalette() {
    if (!mounted) return;
    final history = ref.read(historyProvider);
    final selectedIds = ref.read(selectionProvider);
    final toolHistory = ref.read(canvasToolHistoryProvider);
    showUiDialog(
      context: context,
      builder: (_) => CanvasCommandPalette(
        commands: _canvasCommandDescriptors(
          canUndo: history.canUndo,
          canRedo: history.canRedo,
          hasSelection: selectedIds.isNotEmpty,
        ),
        recentToolIds: toolHistory
            .map((entry) => entry.toolId)
            .toList(growable: false),
        onSelected: _handleCanvasCommand,
      ),
    );
  }

  void _deleteSelectedNodes() {
    if (_collaborationReadOnly) return;
    final ids = ref.read(selectionProvider).toList(growable: false);
    if (ids.isEmpty) return;
    final nodeIds = ref
        .read(documentNodesProvider)
        .where((node) => ids.contains(node.id))
        .map((node) => node.id)
        .toList(growable: false);
    final edgeIds = ref
        .read(documentEdgesProvider)
        .where((edge) => ids.contains(edge.id))
        .map((edge) => edge.id)
        .toList(growable: false);
    if (nodeIds.isNotEmpty) {
      ref.read(documentNodesProvider.notifier).deleteNodes(nodeIds);
    }
    if (edgeIds.isNotEmpty) {
      ref.read(documentNodesProvider.notifier).deleteEdges(edgeIds);
    }
    ref.read(selectionProvider.notifier).clear();
  }

  Future<void> _openCanvasPrecisionSettings() async {
    if (!mounted) return;
    await showUiDialog<void>(
      context: context,
      builder: (_) => CanvasPrecisionDialog(projectId: widget.projectId),
    );
  }

  void _openShortcutHelp() {
    final matrix = InputBehaviorMatrix.defaults();
    showUiDialog<void>(
      context: context,
      builder: (dialogContext) => UiDialog(
        semanticsLabel: 'Keyboard and input shortcuts',
        constraints: AppResponsive.dialogConstraints(
          dialogContext,
          maxWidth: 620,
          maxHeight: 700,
        ),
        builder: (context, style) => ConstrainedBox(
          constraints: AppResponsive.dialogConstraints(
            context,
            maxWidth: 620,
            maxHeight: 700,
          ),
          child: Padding(
            padding: AppResponsive.dialogPadding(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Keyboard and input shortcuts',
                  style: style.titleTextStyle,
                ),
                const SizedBox(height: AppSpacing.md),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final shortcut in matrix.shortcuts)
                        UiSurface(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          child: Row(
                            children: [
                              Expanded(child: Text(shortcut.command)),
                              Text(
                                shortcut.signature,
                                style: TextStyle(
                                  color: context.appTokens.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Divider(),
                      for (final behavior
                          in matrix.behaviors
                              .where(
                                (behavior) =>
                                    behavior.modality !=
                                    CanvasInputModality.keyboard,
                              )
                              .take(12))
                        UiSurface(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${behavior.platform.name} · ${behavior.modality.name}',
                              ),
                              Text(
                                behavior.description,
                                style: TextStyle(
                                  color: context.appTokens.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: UiButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openSelectionArrangeMenu() {
    if (_collaborationReadOnly) return;
    final ids = ref.read(selectionProvider).toList(growable: false);
    if (ids.length < 2) return;
    showUiDialog<void>(
      context: context,
      builder: (dialogContext) {
        void apply(void Function(DocumentNodesNotifier) action) {
          action(ref.read(documentNodesProvider.notifier));
          Navigator.of(dialogContext).pop();
        }

        return UiDialog(
          semanticsLabel: 'Align and distribute selected nodes',
          constraints: AppResponsive.dialogConstraints(
            dialogContext,
            maxWidth: 620,
            maxHeight: 420,
          ),
          builder: (context, style) => Padding(
            padding: AppResponsive.dialogPadding(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Align and distribute', style: style.titleTextStyle),
                const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final entry in <(String, AlignmentType)>[
                      ('Align left', AlignmentType.left),
                      ('Align center', AlignmentType.center),
                      ('Align right', AlignmentType.right),
                      ('Align top', AlignmentType.top),
                      ('Align middle', AlignmentType.middle),
                      ('Align bottom', AlignmentType.bottom),
                    ])
                      UiButton(
                        variant: UiButtonVariant.outline,
                        onPressed: () => apply(
                          (notifier) => notifier.alignNodes(ids, entry.$2),
                        ),
                        child: Text(entry.$1),
                      ),
                    UiButton(
                      variant: UiButtonVariant.outline,
                      onPressed: () => apply(
                        (notifier) => notifier.distributeNodes(
                          ids,
                          DistributionType.horizontal,
                        ),
                      ),
                      child: const Text('Distribute horizontal'),
                    ),
                    UiButton(
                      variant: UiButtonVariant.outline,
                      onPressed: () => apply(
                        (notifier) => notifier.distributeNodes(
                          ids,
                          DistributionType.vertical,
                        ),
                      ),
                      child: const Text('Distribute vertical'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
                Align(
                  alignment: Alignment.centerRight,
                  child: UiButton(
                    variant: UiButtonVariant.ghost,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openQuickCapturePalette() {
    _openCanvasCommandPalette();
  }

  Offset _quickCaptureWorldCenter() {
    final renderObject = _canvasKey.currentContext?.findRenderObject();
    final size = renderObject is RenderBox
        ? renderObject.size
        : MediaQuery.sizeOf(context);
    return ref
        .read(viewportProvider.notifier)
        .toWorld(Offset(size.width / 2, size.height / 2));
  }

  void _openSearchDialog() {
    showUiDialog(
      context: context,
      builder: (ctx) => SearchDialog(
        onSelectNode: (nodeId) {
          final node = ref
              .read(documentNodesProvider)
              .firstWhere(
                (n) => n.id == nodeId,
                orElse: () => throw StateError('node not found'),
              );
          ref.read(selectionProvider.notifier).select(nodeId);
          final viewport = ref.read(viewportProvider);
          final viewportNotifier = ref.read(viewportProvider.notifier);
          final nodeCenter = Offset(
            node.x + node.width / 2,
            node.y + node.height / 2,
          );
          viewportNotifier.setPosition(
            -nodeCenter.dx * viewport.zoom,
            -nodeCenter.dy * viewport.zoom,
          );
        },
      ),
    );
  }

  void _openVariantBrowser(CanvasNode anchorNode) {
    showUiDialog(
      context: context,
      builder: (_) => VariantBrowserDialog(
        anchorNode: anchorNode,
        nodes: ref.read(documentNodesProvider),
        imageCache: _imageCache,
        readOnly: _collaborationReadOnly,
        onSelectNode: (nodeId) {
          final node = ref
              .read(documentNodesProvider)
              .where((candidate) => candidate.id == nodeId)
              .firstOrNull;
          if (node == null) return;
          _focusCreatedAiNode(node);
        },
      ),
    );
  }

  Future<void> _openVectorPathTools(
    CanvasNode node,
    List<String> selectedIds,
  ) async {
    if (_collaborationReadOnly || node.payload is! VectorPathPayload) return;
    final nodes = ref.read(documentNodesProvider);
    final selectedVectors = selectedIds
        .map((id) => nodes.where((candidate) => candidate.id == id).firstOrNull)
        .whereType<CanvasNode>()
        .where((candidate) => candidate.payload is VectorPathPayload)
        .toList(growable: false);
    final action = await showUiDialog<VectorPathToolAction>(
      context: context,
      builder: (_) => VectorPathToolsDialog(
        payload: node.payload as VectorPathPayload,
        hasBooleanTarget: selectedVectors.length == 2,
      ),
    );
    if (!mounted || action == null) return;

    final current = ref
        .read(documentNodesProvider)
        .where((candidate) => candidate.id == node.id)
        .firstOrNull;
    if (current == null || current.payload is! VectorPathPayload) return;
    final payload = current.payload as VectorPathPayload;
    final notifier = ref.read(documentNodesProvider.notifier);

    try {
      switch (action) {
        case VectorPathToolAction.insertAnchor:
          notifier.updateNode(
            current.copyWith(
              payload: VectorPathEditing.insertAnchor(payload, segmentIndex: 0),
            ),
          );
        case VectorPathToolAction.removeAnchor:
          final firstContour = payload.allSubpaths.firstOrNull;
          if (firstContour == null) return;
          notifier.updateNode(
            current.copyWith(
              payload: VectorPathEditing.removeAnchor(
                payload,
                pointIndex: firstContour.length - 1,
              ),
            ),
          );
        case VectorPathToolAction.splitContour:
          final firstContour = payload.allSubpaths.firstOrNull;
          if (firstContour == null || firstContour.length < 3) return;
          final firstClosed = payload.allSubpathClosed.firstOrNull ?? false;
          final singleContour = payload.copyWith(
            points: firstContour,
            isClosed: firstClosed,
            subpaths: const [],
            subpathClosed: const [],
          );
          final split = VectorPathEditing.splitSubpath(
            singleContour,
            pointIndex: firstContour.length ~/ 2,
          );
          final remainingContours = payload.allSubpaths.skip(1);
          final remainingClosed = payload.allSubpathClosed.skip(1);
          final contours = [
            split.first.points,
            split.second.points,
            ...remainingContours,
          ];
          notifier.updateNode(
            current.copyWith(
              payload: payload.copyWith(
                points: contours.expand((contour) => contour).toList(),
                isClosed: false,
                subpaths: contours,
                subpathClosed: [false, false, ...remainingClosed],
              ),
            ),
          );
        case VectorPathToolAction.joinContours:
          if (payload.subpaths.length < 2) return;
          notifier.updateNode(
            current.copyWith(
              payload: VectorPathEditing.joinSubpaths(
                payload,
                firstSubpathIndex: 0,
                secondSubpathIndex: 1,
              ),
            ),
          );
        case VectorPathToolAction.booleanUnion:
        case VectorPathToolAction.booleanIntersect:
        case VectorPathToolAction.booleanDifference:
        case VectorPathToolAction.booleanXor:
          if (selectedVectors.length != 2) return;
          final other = selectedVectors.firstWhere(
            (candidate) => candidate.id != current.id,
          );
          if (current.locked || other.locked) {
            showUiToast(context, 'Unlock both vectors before a boolean edit.');
            return;
          }
          final otherPayload = other.payload as VectorPathPayload;
          final translated = VectorPathEditing.translate(
            otherPayload,
            Offset(other.x - current.x, other.y - current.y),
          );
          final operation = switch (action) {
            VectorPathToolAction.booleanUnion => VectorBooleanOperation.union,
            VectorPathToolAction.booleanIntersect =>
              VectorBooleanOperation.intersect,
            VectorPathToolAction.booleanDifference =>
              VectorBooleanOperation.difference,
            VectorPathToolAction.booleanXor => VectorBooleanOperation.xor,
            _ => VectorBooleanOperation.union,
          };
          final combined = VectorPathEditing.booleanCombine(
            payload,
            translated,
            operation,
          );
          if (combined.allSubpaths.isEmpty) {
            showUiToast(context, 'Boolean operation produced an empty path.');
            return;
          }
          final bounds = combined.toPath().getBounds();
          final normalized = VectorPathEditing.translate(
            combined,
            -bounds.topLeft,
          );
          notifier.beginTransaction(name: 'Boolean vector path');
          notifier.updateNode(
            current.copyWith(
              x: current.x + bounds.left,
              y: current.y + bounds.top,
              width: math.max(10.0, bounds.width),
              height: math.max(10.0, bounds.height),
              payload: normalized,
            ),
          );
          notifier.deleteNodes([other.id]);
          notifier.commitTransaction();
          ref.read(selectionProvider.notifier).select(current.id);
      }
    } catch (error) {
      if (mounted) {
        showUiToast(
          context,
          'Vector edit failed: $error',
          variant: UiToastVariant.error,
        );
      }
    }
  }

  void _openAssetLibrary() {
    final sync = ref.read(supabaseSyncServiceProvider);
    showUiDialog(
      context: context,
      builder: (_) => AssetLibraryDialog(
        nodes: ref.read(documentNodesProvider),
        manifest: ref.read(documentAssetsProvider),
        imageCache: _imageCache,
        readOnly: _collaborationReadOnly,
        library: ref.read(assetLibraryRepositoryProvider(widget.projectId)),
        assetService: AssetService(sync),
        scopeId: widget.projectId,
        onInsert: _collaborationReadOnly
            ? null
            : (sourceNode) {
                final newIds = _duplicateNodesAndTrackUsage([sourceNode.id]);
                if (newIds.isEmpty) return;
                _focusCreatedAiNode(
                  ref
                      .read(documentNodesProvider)
                      .firstWhere((node) => node.id == newIds.single),
                );
              },
        onInsertAsset: insertAssetLibraryItem,
      ),
    );
  }

  @visibleForTesting
  Future<void> insertAssetLibraryItem(AssetLibraryItem item) async {
    if (_collaborationReadOnly || item.scopeId != widget.projectId) return;
    if (!item.isInsertable) {
      showUiToast(
        context,
        'Asset must finish syncing before it can be inserted.',
        variant: UiToastVariant.error,
      );
      return;
    }

    final generation = ++_artifactOperationGeneration;
    _assetLibraryMaterializerGeneration = generation;
    final projectId = widget.projectId;
    final accountId = ref.read(supabaseSyncServiceProvider).currentUserId;
    final isBundledShape = _isBundledShapeItem(item);
    final materialized = isBundledShape
        ? null
        : await _assetLibraryMaterializer.materialize(item);
    if (!_isArtifactOperationCurrent(
      generation: generation,
      projectId: projectId,
      accountId: accountId,
    )) {
      return;
    }
    _assetLibraryMaterializerGeneration = null;
    if (!isBundledShape && materialized == null) {
      if (!mounted) return;
      showUiToast(
        context,
        'The library asset is unavailable or failed validation.',
        variant: UiToastVariant.error,
      );
      return;
    }

    final originalManifest = ref.read(documentAssetsProvider);
    final generatedIdentity = const Uuid().v4();
    final assetId = stableDocumentAssetId(
      candidate: item.id,
      manifest: originalManifest,
      nodes: ref.read(documentNodesProvider),
      ownerNodeId: generatedIdentity,
      fallback: generatedIdentity,
    );
    final nodeId = assetId;
    final materializedItem = materialized == null
        ? item
        : item.copyWith(
            metadata: {
              ...item.metadata,
              _assetReferenceMetadataKey(item.kind): materialized.reference,
            },
            sizeBytes: materialized.sizeBytes,
            checksum: materialized.checksum,
            mimeType: materialized.mimeType,
          );
    final position = _assetLibraryInsertionPosition();
    final node = AssetLibraryNodeFactory.create(
      item: materializedItem,
      nodeId: nodeId,
      assetId: assetId,
      position: position,
      imageArtifactReference:
          materialized == null || !_isImageLibraryKind(item.kind)
          ? null
          : materialized.reference,
    );
    final asset = materialized == null
        ? null
        : buildDocumentAsset(
            id: assetId,
            kind: _documentAssetKindForLibraryItem(item.kind),
            name: item.name,
            mimeType: materialized.mimeType,
            artifactReference: materialized.reference,
            storagePath: null,
            declaredSize: materialized.sizeBytes,
            bytes: materialized.bytes,
            existing: originalManifest[assetId],
            metadata: _durableCatalogMetadata(item, materializedItem),
          );
    if (!isBundledShape && (asset == null || !asset.hasDurableReference)) {
      return;
    }
    final committedManifest = asset == null
        ? originalManifest
        : originalManifest.upsert(asset);
    if (!_isArtifactOperationCurrent(
      generation: generation,
      projectId: projectId,
      accountId: accountId,
    )) {
      return;
    }

    publishDocumentAssetAndNode(
      originalManifest: originalManifest,
      committedManifest: committedManifest,
      setManifest: (next) =>
          ref.read(documentAssetsProvider.notifier).setManifest(next),
      publishNode: () {
        ref.read(documentNodesProvider.notifier).addNode(node);
      },
    );
    if (!_isArtifactOperationCurrent(
      generation: generation,
      projectId: projectId,
      accountId: accountId,
    )) {
      return;
    }
    ref.read(selectionProvider.notifier).select(node.id);
    await ref
        .read(assetLibraryRepositoryProvider(projectId))
        .recordUsage(item.id, projectId: projectId, nodeId: node.id);
  }

  String _assetReferenceMetadataKey(AssetLibraryItemKind kind) =>
      switch (kind) {
        AssetLibraryItemKind.image ||
        AssetLibraryItemKind.graphic ||
        AssetLibraryItemKind.icon ||
        AssetLibraryItemKind.illustration => 'imageArtifactReference',
        AssetLibraryItemKind.file => 'fileArtifactReference',
        AssetLibraryItemKind.audio => 'audioArtifactReference',
        AssetLibraryItemKind.video => 'videoArtifactReference',
        AssetLibraryItemKind.model3d => 'model3dArtifactReference',
      };

  Map<String, dynamic> _durableCatalogMetadata(
    AssetLibraryItem original,
    AssetLibraryItem materialized,
  ) => {
    'libraryItemId': original.id,
    'scopeId': original.scopeId,
    'source': original.source.name,
    'providerAssetId': ?original.providerAssetId,
    'attribution': ?original.attribution,
    'creator': ?original.creator,
    'license': ?original.license,
    'licenseUrl': ?original.licenseUrl,
    'width': ?original.width,
    'height': ?original.height,
    'durationMs': ?original.durationMs,
    _assetReferenceMetadataKey(original.kind):
        materialized.metadata[_assetReferenceMetadataKey(original.kind)],
  };

  DocumentAssetKind _documentAssetKindForLibraryItem(
    AssetLibraryItemKind kind,
  ) => switch (kind) {
    AssetLibraryItemKind.image ||
    AssetLibraryItemKind.graphic ||
    AssetLibraryItemKind.icon ||
    AssetLibraryItemKind.illustration => DocumentAssetKind.image,
    AssetLibraryItemKind.file => DocumentAssetKind.document,
    AssetLibraryItemKind.audio => DocumentAssetKind.audio,
    AssetLibraryItemKind.video => DocumentAssetKind.video,
    AssetLibraryItemKind.model3d => DocumentAssetKind.model3d,
  };

  Offset _assetLibraryInsertionPosition() {
    final renderObject = _canvasKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox) {
      return ref
          .read(viewportProvider.notifier)
          .toWorld(
            Offset(renderObject.size.width / 2, renderObject.size.height / 2),
          );
    }
    return Offset.zero;
  }

  void _openDesignTokenManager() {
    showUiDialog(
      context: context,
      builder: (_) =>
          DesignTokenManagerDialog(readOnly: _collaborationReadOnly),
    );
  }

  Future<void> _openPublishedSnapshotDialog() async {
    if (_collaborationReadOnly) return;
    final storage = ref.read(localStorageServiceProvider);
    PublishedSnapshot? existing;
    try {
      existing = await storage.loadPublishedSnapshot(widget.projectId);
    } catch (_) {
      existing = null;
    }
    if (!mounted) return;

    showUiDialog(
      context: context,
      builder: (_) => PublishedSnapshotDialog(
        document: _currentCanvasDocument(),
        publishedBy: 'local-user',
        existingSnapshot: existing,
        onPublish: (snapshot) async {
          await storage.savePublishedSnapshot(snapshot);
          final sync = ref.read(supabaseSyncServiceProvider);
          if (!sync.isConfigured || !sync.isAuthenticated) {
            return null;
          }
          try {
            final link = await sync.publishCanvasSnapshot(snapshot);
            if (link == null) return null;
            return Uri.base
                .replace(
                  path: '/share/${link.projectId}',
                  queryParameters: {'token': link.token},
                )
                .toString();
          } catch (error) {
            debugPrint('[CanvasEditorSurface] Share link unavailable: $error');
            return null;
          }
        },
      ),
    );
  }

  Future<void> _openReviewWorkflowDialog() async {
    final session = _collaborationSession;
    final role = widget.collaborationRole;
    final canEditCanvas =
        !_collaborationReadOnly &&
        (session?.canEditCanvas ??
            (role == null || CollaborationPermissions(role).canEditCanvas));
    final actorId = session?.localUserId ?? _commentNotificationUserId;
    final selectedNodeId = ref.read(selectionProvider).firstOrNull;
    await showUiDialog<void>(
      context: context,
      builder: (_) => ReviewWorkflowDialog(
        projectId: widget.projectId,
        actorId: actorId,
        canEditCanvas: canEditCanvas,
        selectedNodeId: selectedNodeId,
        onPublishPreview: _openPublishedSnapshotDialog,
      ),
    );
  }

  Future<void> _openWorkspaceGovernanceDialog() async {
    final storage = ref.read(localStorageServiceProvider);
    final sync = ref.read(supabaseSyncServiceProvider);
    AccessibilitySettings settings;
    WorkspacePolicy policy;
    PluginRegistry pluginRegistry;
    WorkspaceGovernanceSnapshot? remoteGovernance;
    final expectedUserId = sync.currentUserId;
    WorkspaceHealthSnapshot? remoteHealth;
    EntitlementSnapshot? remoteEntitlement;
    var remotePluginRegistryAvailable = false;
    var remotePluginIds = <String>{};
    List<WorkspaceAuditEvent> auditEvents = const [];
    try {
      settings = await storage.loadAccessibilitySettings();
    } catch (_) {
      settings = const AccessibilitySettings();
    }
    try {
      policy = await storage.loadWorkspacePolicy();
    } catch (_) {
      policy = const WorkspacePolicy();
    }
    try {
      pluginRegistry = await storage.loadPluginRegistry();
    } catch (_) {
      pluginRegistry = PluginRegistry();
    }
    if (sync.isConfigured) {
      try {
        final loadedGovernance = await sync.getWorkspaceGovernance(
          widget.projectId,
          expectedUserId: expectedUserId,
        );
        remoteGovernance = loadedGovernance;
        policy = loadedGovernance.policy;
        try {
          auditEvents = await sync.listWorkspaceAuditEvents(widget.projectId);
        } catch (error) {
          debugPrint(
            '[CanvasEditorSurface] Remote audit events unavailable: $error',
          );
        }
      } catch (error) {
        debugPrint(
          '[CanvasEditorSurface] Remote governance unavailable: $error',
        );
      }
      try {
        remoteHealth = await sync.getWorkspaceHealth(widget.projectId);
      } catch (error) {
        debugPrint('[CanvasEditorSurface] Remote health unavailable: $error');
      }
      try {
        remoteEntitlement = await sync.getWorkspaceEntitlement(
          widget.projectId,
        );
      } catch (error) {
        debugPrint(
          '[CanvasEditorSurface] Remote entitlement unavailable: $error',
        );
      }
      try {
        final remoteRegistrations = await sync.listWorkspacePluginRegistrations(
          widget.projectId,
        );
        pluginRegistry = PluginRegistry(registrations: remoteRegistrations);
        remotePluginIds = remoteRegistrations
            .map((registration) => registration.manifest.id)
            .toSet();
        remotePluginRegistryAvailable = true;
      } catch (error) {
        debugPrint(
          '[CanvasEditorSurface] Remote plugin registry unavailable: $error',
        );
      }
    }
    if (!mounted ||
        widget.projectId.trim().isEmpty ||
        sync.currentUserId != expectedUserId) {
      return;
    }

    final document = _currentCanvasDocument();
    final storageBytes = jsonEncode(document.toPersistenceJson()).length;
    final assetBytes = document.assets.items.fold<int>(
      0,
      (total, asset) => total + (asset.sizeBytes ?? 0),
    );
    final localUsage = WorkspaceUsage(
      storageBytes: storageBytes,
      assetBytes: assetBytes,
      projectCount: 1,
    );
    final usage = remoteGovernance?.usage ?? localUsage;
    Future<void> savePolicy(WorkspacePolicy next) async {
      await storage.saveWorkspacePolicy(next);
      if (sync.isConfigured) {
        await sync.upsertWorkspacePolicy(
          projectId: widget.projectId,
          policy: next,
        );
      }
    }

    Future<void> savePluginRegistry(PluginRegistry next) async {
      await storage.savePluginRegistry(next);
      if (!remotePluginRegistryAvailable) return;
      final nextPluginIds = next.registrations
          .map((registration) => registration.manifest.id)
          .toSet();
      for (final registration in next.registrations) {
        await sync.upsertWorkspacePluginRegistration(
          projectId: widget.projectId,
          registration: registration,
        );
      }
      for (final pluginId in remotePluginIds.difference(nextPluginIds)) {
        await sync.deleteWorkspacePluginRegistration(
          projectId: widget.projectId,
          pluginId: pluginId,
        );
      }
      remotePluginIds = nextPluginIds;
    }

    Future<WorkspaceSupportBundleReceipt> submitSupportBundle() async {
      if (!sync.isConfigured) {
        throw const SyncException('Cloud backend is not configured.');
      }
      final bundle = SupportBundle(
        generatedAt: DateTime.now().toUtc(),
        sections: {
          'health': remoteHealth == null
              ? const {'status': 'unavailable'}
              : {
                  'status': remoteHealth.status.name,
                  'version': remoteHealth.version,
                  'checks': remoteHealth.checks
                      .map((check) => check.toJson())
                      .toList(growable: false),
                },
          'workspacePolicy': policy.toJson(),
          'entitlement':
              remoteEntitlement?.toJson() ?? const {'status': 'unavailable'},
          'plugins': pluginRegistry.toJson(),
          'usage': usage.toJson(),
          'audit': auditEvents
              .map((event) => event.toJson())
              .toList(growable: false),
          'collaboration': {
            'connection': _collaborationSession?.connectionState.name,
            'syncStatus': _collaborationSession?.syncStatus.name,
            'pendingOperations': _collaborationSession?.pendingOperationCount,
          },
        },
      );
      return sync.submitWorkspaceSupportBundle(
        projectId: widget.projectId,
        operationId: 'support-${DateTime.now().microsecondsSinceEpoch}',
        bundle: bundle,
        checksum: sha256.convert(utf8.encode(bundle.encode())).toString(),
      );
    }

    showUiDialog(
      context: context,
      builder: (_) => WorkspaceGovernanceDialog(
        initialSettings: settings,
        usage: usage,
        quota: policy.quota,
        onSave: storage.saveAccessibilitySettings,
        initialPolicy: policy,
        retentionPolicy: policy.retention,
        auditEvents: auditEvents,
        onPolicySave: savePolicy,
        initialPluginRegistry: pluginRegistry,
        onPluginRegistrySave: savePluginRegistry,
        healthSnapshot: remoteHealth,
        entitlement: remoteEntitlement,
        onSupportBundleSubmit: sync.isConfigured ? submitSupportBundle : null,
        cloudProjectId: sync.isConfigured ? widget.projectId : null,
        cloudExpectedUserId: sync.isConfigured ? expectedUserId : null,
      ),
    );
  }

  Future<void> _openComponentLibrary() async {
    final storage = ref.read(localStorageServiceProvider);
    final discovered = ComponentLibrary.discover(
      ref.read(documentNodesProvider),
    );
    ComponentLibrary library;
    try {
      library = (await storage.loadComponentLibrary(
        widget.projectId,
      )).merge(discovered);
    } catch (_) {
      library = discovered;
    }
    if (!mounted) return;
    showUiDialog(
      context: context,
      builder: (_) => ComponentLibraryDialog(
        nodes: ref.read(documentNodesProvider),
        initialLibrary: library,
        readOnly: _collaborationReadOnly,
        onLibraryChanged: (next) =>
            storage.saveComponentLibrary(widget.projectId, next),
        onInsert: _collaborationReadOnly
            ? null
            : (instance) {
                ref.read(documentNodesProvider.notifier).addNode(instance);
                _focusCreatedAiNode(instance);
              },
      ),
    );
  }

  void _openExportCenter({ExportPreset? initialPreset}) {
    if (!widget.services.enableExport) return;
    final nodes = ref.read(documentNodesProvider);
    final selectedIds = ref
        .read(selectionProvider)
        .where((id) => nodes.any((node) => node.id == id));
    final hasSelectedFrame = selectedIds.any(
      (id) => nodes.firstWhere((node) => node.id == id).type == NodeType.frame,
    );

    showUiDialog(
      context: context,
      builder: (_) => ExportCenterDialog(
        initialPreset: initialPreset ?? ExportPresetRegistry.png,
        initialTarget: selectedIds.isNotEmpty
            ? ExportTarget.selection
            : ExportTarget.currentCanvas,
        hasSelection: selectedIds.isNotEmpty,
        hasSelectedFrame: hasSelectedFrame,
        onExport: _runExport,
      ),
    );
  }

  void _openInspectHandoff() {
    if (!widget.services.enableExport) return;
    final nodes = ref.read(documentNodesProvider);
    final selectedIds = ref
        .read(selectionProvider)
        .where((id) => nodes.any((node) => node.id == id))
        .toList(growable: false);
    showUiDialog(
      context: context,
      builder: (_) => InspectHandoffDialog(
        document: _currentCanvasDocument(),
        nodeIds: selectedIds.isEmpty ? null : selectedIds,
        onExport: _saveInspectHandoff,
      ),
    );
  }

  Future<ExportSaveOutcome> _saveInspectHandoff(
    InspectHandoffFormat format,
    String content,
  ) {
    final extension = switch (format) {
      InspectHandoffFormat.css => 'css',
      InspectHandoffFormat.flutter => 'dart',
      InspectHandoffFormat.svg => 'svg',
      InspectHandoffFormat.json => 'json',
    };
    final mimeType = switch (format) {
      InspectHandoffFormat.css => 'text/css',
      InspectHandoffFormat.flutter => 'text/x-dart',
      InspectHandoffFormat.svg => 'image/svg+xml',
      InspectHandoffFormat.json => 'application/json',
    };
    final fileName = sanitizeExportFileName(
      '$_documentTitle-inspect.$extension',
    );
    return ExportFileSaver().save(
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(content)),
      mimeType: mimeType,
      dialogTitle: 'Save ${format.name.toUpperCase()} handoff',
    );
  }

  Future<ExportSaveOutcome> _runExport(
    ExportTarget target,
    ExportPreset preset,
  ) async {
    if (!widget.services.enableExport) return ExportSaveOutcome.failed;
    try {
      final jobId = _exportQueue.enqueue(
        preset: preset,
        task: () async {
          final document = _documentForExportTarget(
            target,
            includeMermaidSources: preset.format == ExportPresetFormat.mermaid,
          );
          return preset.requiresRenderBoundary
              ? await _exportWithCleanBoundary(document, preset)
              : await preset.export(
                  document,
                  portableAssetCollector:
                      preset.format == ExportPresetFormat.portablePackage
                      ? _portableAssetCollector
                      : null,
                );
        },
      );
      final job = await _exportQueue.waitForJob(jobId);
      if (job.status == ExportQueueJobStatus.canceled) {
        return ExportSaveOutcome.canceled;
      }
      if (job.status != ExportQueueJobStatus.completed || job.result == null) {
        return ExportSaveOutcome.failed;
      }
      final result = job.result!;

      final fileName = sanitizeExportFileName(
        '$_documentTitle-${_exportTargetLabel(target)}.${preset.extension}',
      );
      final outcome = await ExportFileSaver().save(
        fileName: fileName,
        bytes: result.data,
        mimeType: preset.mimeType,
        dialogTitle: 'Save ${preset.label}',
      );
      if (mounted) {
        final message = switch (outcome) {
          ExportSaveOutcome.saved => 'Saved $fileName.',
          ExportSaveOutcome.canceled => 'Export canceled.',
          ExportSaveOutcome.failed => 'Export failed.',
        };
        showUiToast(
          context,
          message,
          variant: outcome == ExportSaveOutcome.saved
              ? UiToastVariant.success
              : UiToastVariant.info,
        );
      }
      return outcome;
    } catch (error) {
      debugPrint('[CanvasEditorSurface] Export failed: $error');
      return ExportSaveOutcome.failed;
    }
  }

  CanvasDocument _documentForExportTarget(
    ExportTarget target, {
    bool includeMermaidSources = false,
  }) {
    final document = _currentCanvasDocument();
    final nodes = document.nodes;
    List<CanvasNode> selectedNodes;

    switch (target) {
      case ExportTarget.currentCanvas:
        selectedNodes = nodes;
        break;
      case ExportTarget.selection:
        final selectedIds = ref.read(selectionProvider);
        selectedNodes = nodes
            .where((node) => selectedIds.contains(node.id))
            .toList();
        if (selectedNodes.isEmpty) {
          throw StateError('Select at least one canvas object to export.');
        }
        break;
      case ExportTarget.selectedFrame:
        final selectedFrame = nodes
            .where(
              (node) =>
                  node.type == NodeType.frame &&
                  ref.read(selectionProvider).contains(node.id),
            )
            .firstOrNull;
        if (selectedFrame == null) {
          throw StateError('Select a frame to export.');
        }
        final frameRect = selectedFrame.bounds;
        selectedNodes = nodes.where((node) {
          if (!node.visible) return false;
          if (node.id == selectedFrame.id) return true;
          final center = Offset(
            node.x + node.width / 2,
            node.y + node.height / 2,
          );
          return frameRect.contains(center);
        }).toList();
        break;
    }

    if (includeMermaidSources) {
      final selectedNodeIds = selectedNodes.map((node) => node.id).toSet();
      final sourceIds = <String>{};
      for (final node in nodes) {
        if (node.type != NodeType.mermaid || node.payload is! MermaidPayload) {
          continue;
        }
        final payload = node.payload as MermaidPayload;
        if (selectedNodeIds.contains(node.id) ||
            payload.nativeNodeIds.any(selectedNodeIds.contains)) {
          sourceIds.add(node.id);
        }
      }
      selectedNodes = [
        ...selectedNodes,
        ...nodes.where(
          (node) =>
              sourceIds.contains(node.id) && !selectedNodeIds.contains(node.id),
        ),
      ];
    }

    final ids = selectedNodes.map((node) => node.id).toSet();
    final edges = document.edges
        .where(
          (edge) =>
              (edge.sourceNodeId == null || ids.contains(edge.sourceNodeId)) &&
              (edge.targetNodeId == null || ids.contains(edge.targetNodeId)),
        )
        .toList();
    return document.copyWith(nodes: selectedNodes, edges: edges);
  }

  Future<ExportPresetResult?> _exportWithCleanBoundary(
    CanvasDocument document,
    ExportPreset preset,
  ) async {
    final bounds = _exportBounds(document.nodes, document.edges);
    const padding = 40.0;
    const maxDimension = 4096.0;
    final rawWidth = math.max(1.0, bounds.width + padding * 2);
    final rawHeight = math.max(1.0, bounds.height + padding * 2);
    final zoom = math.min(
      1.0,
      math.min(maxDimension / rawWidth, maxDimension / rawHeight),
    );
    final size = Size(rawWidth * zoom, rawHeight * zoom);
    final boundaryKey = GlobalKey();
    final overlay = OverlayEntry(
      builder: (_) => Positioned(
        left: -10000,
        top: -10000,
        child: IgnorePointer(
          child: CanvasExportSurface(
            boundaryKey: boundaryKey,
            nodes: document.nodes,
            edges: document.edges,
            viewport: canvas_model.Viewport(
              x: (padding - bounds.left) * zoom,
              y: (padding - bounds.top) * zoom,
              zoom: zoom,
            ),
            size: size,
            renderTokens: CanvasRenderTokens.fromAppTokens(context.appTokens),
            imageCache: _imageCache,
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(overlay);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          boundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final bytes = await ExportService.capturePng(boundary);
      return bytes == null ? null : ExportPresetResult.bytes(preset, bytes);
    } finally {
      overlay.remove();
    }
  }

  Rect _exportBounds(
    List<CanvasNode> nodes, [
    List<CanvasEdge> edges = const [],
  ]) {
    final visibleNodes = nodes.where((node) => node.visible).toList();
    final nodeMap = {for (final node in visibleNodes) node.id: node};
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;

    void include(Offset point) {
      if (!point.dx.isFinite || !point.dy.isFinite) return;
      minX = math.min(minX, point.dx);
      minY = math.min(minY, point.dy);
      maxX = math.max(maxX, point.dx);
      maxY = math.max(maxY, point.dy);
    }

    for (final node in visibleNodes) {
      include(Offset(node.x, node.y));
      include(Offset(node.x + node.width, node.y + node.height));
    }
    for (final edge in edges) {
      for (final point in ConnectorRouter.routePointsForEdge(edge, nodeMap)) {
        include(point);
      }
    }

    if (!minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite) {
      return const Rect.fromLTWH(0, 0, 800, 600);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  String _exportTargetLabel(ExportTarget target) => switch (target) {
    ExportTarget.currentCanvas => 'canvas',
    ExportTarget.selection => 'selection',
    ExportTarget.selectedFrame => 'frame',
  };

  void _openDocumentEditor(CanvasNode node) {
    final payload = node.payload as DocumentPayload;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => DocumentEditorScreen(
          initialPayload: payload,
          onSave: (updated) {
            final latestNode = ref
                .read(documentNodesProvider)
                .firstWhere((n) => n.id == node.id, orElse: () => node);
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  latestNode.copyWith(name: updated.title, payload: updated),
                );
          },
          onSaveAndExit: (updated) {
            final latestNode = ref
                .read(documentNodesProvider)
                .firstWhere((n) => n.id == node.id, orElse: () => node);
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  latestNode.copyWith(name: updated.title, payload: updated),
                );
          },
        ),
      ),
    );
  }

  void _openVideoPlayer(CanvasNode node) {
    final payload = node.payload as VideoPayload;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => VideoPlayerScreen(
          sourcePath: payload.videoPath ?? '',
          networkUrl: payload.videoUrl,
          storagePath: payload.storagePath,
          artifactReference: payload.videoArtifactReference,
          sourceResolver: _mediaSourceResolver,
          caption: payload.caption,
          timeline: payload.mediaTimeline,
          onDownload: () => _downloadVideo(node),
        ),
      ),
    );
  }

  Future<void> _downloadVideo(CanvasNode node) async {
    final payload = node.payload as VideoPayload;
    final service = VideoDownloadService();
    TransientMediaSource? source;
    try {
      source = await _mediaSourceResolver.resolveVideo(payload);
      final bytes = await source.readBytes();
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Video artifact is no longer available.');
      }
      await service.downloadSource(
        fileName: videoDownloadFileName(node.name),
        videoArtifactReference: payload.videoArtifactReference,
        bytes: bytes,
      );
      if (!mounted) return;
      showUiToast(
        context,
        'Video download started.',
        variant: UiToastVariant.success,
      );
    } catch (_) {
      if (!mounted) return;
      showUiToast(
        context,
        'Video download failed.',
        variant: UiToastVariant.error,
      );
    } finally {
      await source?.dispose();
    }
  }

  void _openAudioPlayer(CanvasNode node) {
    final payload = node.payload as AudioPayload;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => AudioPlayerScreen(
          sourcePath: payload.audioPath,
          networkUrl: payload.audioUrl,
          storagePath: payload.storagePath,
          audioArtifactReference: payload.audioArtifactReference,
          sourceResolver: _mediaSourceResolver,
          title: payload.trackName,
          artist: payload.artist,
          timeline: payload.mediaTimeline,
        ),
      ),
    );
  }

  void _openMapViewer(CanvasNode node) {
    final payload = node.payload as MapPayload;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => MapViewerScreen(
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
    );
  }

  Future<void> _submitLinkUrl(CanvasNode node, String input) async {
    try {
      final normalized = normalizeLinkUrl(input).toString();
      final current = ref
          .read(documentNodesProvider)
          .firstWhere(
            (candidate) => candidate.id == node.id,
            orElse: () => node,
          );
      final payload = current.payload as LinkPayload;
      if (payload.url == normalized &&
          payload.previewStatus == LinkPreviewStatus.ready) {
        return;
      }
      await ref
          .read(linkPreviewControllerProvider.notifier)
          .submit(current, normalized);
    } on LinkUrlValidationException catch (error) {
      if (mounted) {
        showUiToast(context, error.message, variant: UiToastVariant.error);
      }
    }
  }

  void _openLinkInApp(CanvasNode node) {
    try {
      final payload = node.payload as LinkPayload;
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
      if (mounted) {
        showUiToast(context, error.message, variant: UiToastVariant.error);
      }
    }
  }

  Future<void> _openLinkExternal(CanvasNode node) async {
    try {
      final uri = normalizeLinkUrl((node.payload as LinkPayload).url);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        showUiToast(
          context,
          'Browser tidak dapat dibuka.',
          variant: UiToastVariant.error,
        );
      }
    } catch (error) {
      if (mounted) {
        final message = error is LinkUrlValidationException
            ? error.message
            : 'Browser tidak dapat dibuka.';
        showUiToast(context, message, variant: UiToastVariant.error);
      }
    }
  }

  void _openEmbed(CanvasNode node) {
    final payload = node.payload as EmbedPayload;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => EmbedWebviewScreen(
          url: parseEmbedUrl(payload.url).launchUrl.toString(),
          title: payload.title?.isNotEmpty == true
              ? payload.title!
              : payload.provider,
        ),
      ),
    );
  }

  Future<void> _attachImageAssetToNode(
    CanvasNode node,
    ImagePayload payload,
  ) async {
    final operationGeneration = ++_artifactOperationGeneration;
    final projectId = widget.projectId;
    final accountId = ref.read(supabaseSyncServiceProvider).currentUserId;
    final capturedNode = ref
        .read(documentNodesProvider)
        .where((candidate) => candidate.id == node.id)
        .firstOrNull;
    if (capturedNode == null || capturedNode.payload is! ImagePayload) return;

    final result = await AssetService(
      ref.read(supabaseSyncServiceProvider),
    ).pickImage(projectId: projectId);
    if (!_isArtifactOperationCurrent(
          generation: operationGeneration,
          projectId: projectId,
          accountId: accountId,
        ) ||
        result == null) {
      return;
    }

    final bytes = result.bytes;
    String? imageReference;
    if (bytes != null && bytes.isNotEmpty) {
      try {
        final artifact = await _imageArtifactStore.save(
          bytes,
          fileName: result.name,
        );
        imageReference = validImageArtifactReference(artifact.reference);
      } catch (_) {
        imageReference = null;
      }
    }
    if (!_isArtifactOperationCurrent(
      generation: operationGeneration,
      projectId: projectId,
      accountId: accountId,
    )) {
      return;
    }
    final storagePath = _validatedImageStoragePath(result.storagePath);
    if (imageReference == null && storagePath == null) {
      if (mounted) {
        showUiToast(
          context,
          'The selected image could not be stored.',
          variant: UiToastVariant.error,
        );
      }
      return;
    }

    if (bytes != null && bytes.isNotEmpty && imageReference != null) {
      await _imageCache.decodeAndCacheBytes(imageReference, bytes);
      if (!_isArtifactOperationCurrent(
        generation: operationGeneration,
        projectId: projectId,
        accountId: accountId,
      )) {
        return;
      }
    }

    final current = ref
        .read(documentNodesProvider)
        .where((candidate) => candidate.id == node.id)
        .firstOrNull;
    if (current == null || current.payload is! ImagePayload) return;
    if (!canCommitDocumentAssetReplacement(
      capturedNode: capturedNode,
      currentNode: current,
      operationProjectId: projectId,
      currentProjectId: widget.projectId,
      expectedAccountId: accountId,
      currentAccountId: ref.read(supabaseSyncServiceProvider).currentUserId,
    )) {
      return;
    }

    final currentPayload = current.payload as ImagePayload;
    final originalManifest = ref.read(documentAssetsProvider);
    final assetId = stableDocumentAssetId(
      candidate: currentPayload.assetId ?? current.id,
      manifest: originalManifest,
      nodes: ref.read(documentNodesProvider),
      ownerNodeId: current.id,
    );
    final asset = buildDocumentAsset(
      id: assetId,
      kind: DocumentAssetKind.image,
      name: result.name,
      mimeType: result.detectedMimeType,
      artifactReference: imageReference,
      storagePath: storagePath,
      declaredSize: result.size,
      bytes: bytes,
      existing: originalManifest[assetId],
    );
    if (asset == null) return;
    final updatedNode = current.copyWith(
      payload: currentPayload.copyWith(
        imageArtifactReference: imageReference,
        storagePath: storagePath,
        clearImageArtifactReference: imageReference == null,
        clearStoragePath: storagePath == null,
        clearLocalPath: true,
        clearUrl: true,
        assetId: assetId,
        cropX: 0.0,
        cropY: 0.0,
        cropWidth: 1.0,
        cropHeight: 1.0,
        focalPointX: 0.5,
        focalPointY: 0.5,
        clearBackgroundMask: true,
      ),
    );
    if (!_isArtifactOperationCurrent(
      generation: operationGeneration,
      projectId: projectId,
      accountId: accountId,
    )) {
      return;
    }
    publishDocumentAssetAndNode(
      originalManifest: originalManifest,
      committedManifest: originalManifest.upsert(asset),
      setManifest: (next) =>
          ref.read(documentAssetsProvider.notifier).setManifest(next),
      publishNode: () =>
          ref.read(documentNodesProvider.notifier).updateNode(updatedNode),
    );
  }

  Future<void> _openImageCrop(CanvasNode node) async {
    final operationGeneration = ++_artifactOperationGeneration;
    final projectId = widget.projectId;
    final accountId = ref.read(supabaseSyncServiceProvider).currentUserId;
    final capturedNode = ref
        .read(documentNodesProvider)
        .where((candidate) => candidate.id == node.id)
        .firstOrNull;
    if (capturedNode == null || capturedNode.payload is! ImagePayload) return;
    final payload = capturedNode.payload as ImagePayload;
    final bytes = await _imageCache.loadImageBytes(
      storagePath: payload.storagePath,
      localPath: payload.localPath,
      url: payload.url,
      imageArtifactReference: payload.imageArtifactReference,
    );

    if (!_isArtifactOperationCurrent(
      generation: operationGeneration,
      projectId: projectId,
      accountId: accountId,
    )) {
      return;
    }
    if (bytes == null) {
      final hasSource =
          (payload.imageArtifactReference?.trim().isNotEmpty ?? false) ||
          (payload.storagePath?.trim().isNotEmpty ?? false) ||
          (payload.localPath?.trim().isNotEmpty ?? false) ||
          (payload.url?.trim().isNotEmpty ?? false);
      if (!hasSource) {
        await _attachImageAssetToNode(capturedNode, payload);
      } else if (mounted) {
        showUiToast(
          context,
          'Unable to load the image for editing. Try replacing it.',
          variant: UiToastVariant.error,
        );
      }
      return;
    }

    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      final sourceSize = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      if (!_isArtifactOperationCurrent(
        generation: operationGeneration,
        projectId: projectId,
        accountId: accountId,
      )) {
        return;
      }
      final current = ref
          .read(documentNodesProvider)
          .where((candidate) => candidate.id == capturedNode.id)
          .firstOrNull;
      if (current == null ||
          !canCommitDocumentAssetReplacement(
            capturedNode: capturedNode,
            currentNode: current,
            operationProjectId: projectId,
            currentProjectId: widget.projectId,
            expectedAccountId: accountId,
            currentAccountId: ref
                .read(supabaseSyncServiceProvider)
                .currentUserId,
          )) {
        return;
      }
      final currentPayload = current.payload as ImagePayload;
      final sourceRect = ImageCropSelection(
        x: currentPayload.cropX,
        y: currentPayload.cropY,
        width: currentPayload.cropWidth,
        height: currentPayload.cropHeight,
      ).toImageRect(sourceSize);

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => ImageCropScreen(
            imageData: bytes,
            initialArea: sourceRect,
            onCroppedWithArea: (_, imageArea) {
              if (!_isArtifactOperationCurrent(
                generation: operationGeneration,
                projectId: projectId,
                accountId: accountId,
              )) {
                return;
              }
              final latest = ref
                  .read(documentNodesProvider)
                  .where((candidate) => candidate.id == capturedNode.id)
                  .firstOrNull;
              if (latest == null ||
                  !canCommitDocumentAssetReplacement(
                    capturedNode: capturedNode,
                    currentNode: latest,
                    operationProjectId: projectId,
                    currentProjectId: widget.projectId,
                    expectedAccountId: accountId,
                    currentAccountId: ref
                        .read(supabaseSyncServiceProvider)
                        .currentUserId,
                  )) {
                return;
              }
              final selection = ImageCropSelection.fromImageRect(
                imageArea,
                sourceSize,
              );
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    latest.copyWith(
                      payload: (latest.payload as ImagePayload).copyWith(
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
    } finally {
      codec.dispose();
    }
  }

  void _startInlineEdit(CanvasNode node, {required bool frameLabel}) {
    String initialText = '';
    if (frameLabel) {
      initialText =
          node.name ??
          (node.payload is FramePayload
              ? (node.payload as FramePayload).name
              : '');
    } else if (node.payload is ShapePayload) {
      initialText = (node.payload as ShapePayload).label;
    } else if (node.payload is TextPayload) {
      initialText = (node.payload as TextPayload).text;
    } else if (node.payload is StickyNotePayload) {
      initialText = (node.payload as StickyNotePayload).text;
    }
    _editController.text = initialText;
    _inlineEditOriginalNode = node;
    setState(() {
      _editingNodeId = node.id;
      _editingFrameLabel = frameLabel;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocusNode.requestFocus();
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController.text.length,
      );
    });
  }

  void _updateInlineEditTransient(String text) {
    final nodeId = _editingNodeId;
    if (nodeId == null) return;
    final nodes = ref.read(documentNodesProvider);
    final node = nodes.where((candidate) => candidate.id == nodeId).firstOrNull;
    if (node == null) return;

    CanvasNode updated = node;
    if (_editingFrameLabel) {
      updated = node.copyWith(name: text);
    } else if (node.payload is ShapePayload) {
      final payload = node.payload as ShapePayload;
      updated = node.copyWith(payload: payload.copyWith(label: text));
    } else if (node.payload is StickyNotePayload) {
      final payload = node.payload as StickyNotePayload;
      updated = node.copyWith(payload: payload.copyWith(text: text));
    } else if (node.payload is TextPayload) {
      final payload = node.payload as TextPayload;
      updated = node.copyWith(payload: payload.copyWith(text: text));
    }

    ref.read(documentNodesProvider.notifier).updateTransientNode(updated);
  }

  void _commitInlineEdit() {
    final nodeId = _editingNodeId;
    if (nodeId == null) return;
    final nodes = ref.read(documentNodesProvider);
    final match = nodes.where((n) => n.id == nodeId).toList();
    final text = _editController.text;
    if (match.isNotEmpty) {
      final node = match.first;
      if (_editingFrameLabel) {
        ref
            .read(documentNodesProvider.notifier)
            .updateNode(
              node.copyWith(name: text),
              historyFrom: _inlineEditOriginalNode,
            );
      } else if (node.payload is ShapePayload) {
        final payload = node.payload as ShapePayload;
        ref
            .read(documentNodesProvider.notifier)
            .updateNode(
              node.copyWith(payload: payload.copyWith(label: text)),
              historyFrom: _inlineEditOriginalNode,
            );
      } else if (node.payload is StickyNotePayload) {
        final payload = node.payload as StickyNotePayload;
        ref
            .read(documentNodesProvider.notifier)
            .updateNode(
              node.copyWith(payload: payload.copyWith(text: text)),
              historyFrom: _inlineEditOriginalNode,
            );
      } else if (node.payload is TextPayload) {
        if (text.trim().isEmpty) {
          ref.read(documentNodesProvider.notifier).deleteNodes([node.id]);
        } else {
          final payload = node.payload as TextPayload;

          // If text was modified in rich text mode and no blocks exist yet, keep plain text or update blocks
          List<RichTextBlock>? updatedBlocks = payload.blocks;
          if (payload.renderMode == TextRenderMode.rich &&
              (updatedBlocks == null || updatedBlocks.isEmpty)) {
            updatedBlocks = text
                .split('\n')
                .map((l) => RichTextBlock(spans: [RichTextSpan(text: l)]))
                .toList();
          }

          // Auto-resize node width / height according to text if sizeMode is auto
          double newWidth = node.width;
          double newHeight = node.height;

          if (payload.sizeMode == TextSizeMode.autoWidth ||
              payload.sizeMode == TextSizeMode.autoHeight) {
            final textSpan = TextSpan(
              text: text,
              style: TextStyle(
                fontSize: payload.fontSize,
                fontWeight: payload.fontWeight,
                height: payload.lineHeight,
                letterSpacing: payload.letterSpacing,
              ),
            );
            final tp = TextPainter(
              text: textSpan,
              textAlign: payload.textAlign,
              textDirection: TextDirection.ltr,
            );
            final double pad = payload.backgroundColor != null
                ? payload.backgroundPadding * 2
                : 16.0;
            if (payload.sizeMode == TextSizeMode.autoWidth) {
              tp.layout(maxWidth: double.infinity);
              newWidth = math.max(60.0, tp.width + pad);
              newHeight = math.max(30.0, tp.height + pad);
            } else if (payload.sizeMode == TextSizeMode.autoHeight) {
              tp.layout(maxWidth: math.max(10.0, node.width - pad));
              newHeight = math.max(30.0, tp.height + pad);
            }
          }

          ref
              .read(documentNodesProvider.notifier)
              .updateNode(
                node.copyWith(
                  width: newWidth,
                  height: newHeight,
                  payload: payload.copyWith(text: text, blocks: updatedBlocks),
                ),
                historyFrom: _inlineEditOriginalNode,
              );
        }
      }
    }
    setState(() {
      _editingNodeId = null;
      _inlineEditOriginalNode = null;
    });
  }

  void _applyQuickStyle(
    CanvasNode node,
    TextPayload Function(TextPayload p) updater,
  ) {
    if (node.payload is! TextPayload) return;
    final currentPayload = node.payload as TextPayload;
    final updatedPayload = updater(currentPayload);
    ref
        .read(documentNodesProvider.notifier)
        .updateNode(node.copyWith(payload: updatedPayload));
    // Keep text field focus active after formatting button click
    _editFocusNode.requestFocus();
  }

  void _applyFormattingToRichTextOrNode(
    CanvasNode node, {
    required String formatType,
    required TextPayload Function(TextPayload p) nodeFallback,
  }) {
    if (node.payload is! TextPayload) return;
    final payload = node.payload as TextPayload;
    final text = _editController.text;
    final selection = _editController.selection;

    if (!selection.isValid ||
        selection.isCollapsed ||
        selection.start < 0 ||
        selection.end > text.length) {
      _applyQuickStyle(node, nodeFallback);
      return;
    }
    final format = switch (formatType) {
      'bold' => RichTextFormat.bold,
      'italic' => RichTextFormat.italic,
      'underline' => RichTextFormat.underline,
      'strikethrough' => RichTextFormat.strikethrough,
      _ => null,
    };
    if (format == null) {
      _applyQuickStyle(node, nodeFallback);
      return;
    }
    final newBlocks = RichTextEditing.formatSelection(
      text: text,
      blocks: payload.blocks,
      selection: selection,
      format: format,
      enabled: true,
    );

    final updatedPayload = payload.copyWith(
      text: text,
      renderMode: TextRenderMode.rich,
      blocks: newBlocks,
    );

    ref
        .read(documentNodesProvider.notifier)
        .updateNode(node.copyWith(payload: updatedPayload));
    _editFocusNode.requestFocus();
  }

  void _handleTapUp(TapUpDetails details, CanvasTool activeTool) {
    _lastTapLocalPosition = details.localPosition;
    final worldPos = ref
        .read(viewportProvider.notifier)
        .toWorld(details.localPosition);

    if (activeTool == CanvasTool.pen) {
      final isShiftPressed =
          HardwareKeyboard.instance.logicalKeysPressed.contains(
            LogicalKeyboardKey.shiftLeft,
          ) ||
          HardwareKeyboard.instance.logicalKeysPressed.contains(
            LogicalKeyboardKey.shiftRight,
          );
      var effectivePos = worldPos;
      if (isShiftPressed && _activePenPoints.isNotEmpty) {
        final last = _activePenPoints.last.point;
        final delta = worldPos - last;
        final angle = math.atan2(delta.dy, delta.dx);
        final snappedAngle = (angle / (math.pi / 4)).round() * (math.pi / 4);
        final dist = delta.distance;
        effectivePos = Offset(
          last.dx + dist * math.cos(snappedAngle),
          last.dy + dist * math.sin(snappedAngle),
        );
      }

      // If clicking near the first point, close the path and finalize
      if (_activePenPoints.length >= 2) {
        final firstPoint = _activePenPoints.first.point;
        if ((worldPos - firstPoint).distance < 14.0) {
          _finalizePenPath(isClosed: true);
          return;
        }
      }
      setState(() {
        _activePenPoints.add(BezierPoint(point: effectivePos));
      });
      return;
    }

    if (activeTool == CanvasTool.drawingPaper) {
      showUiDialog(
        context: context,
        builder: (ctx) => PaperTemplateDialog(
          onSelected: (paperPayload) {
            final double paperAspect =
                paperPayload.pixelHeight / paperPayload.pixelWidth;
            const double targetWidth = 400.0;
            final double targetHeight = targetWidth * paperAspect;

            final paperNode = CanvasNode(
              id: const Uuid().v4(),
              type: NodeType.drawingPaper,
              x: worldPos.dx - targetWidth / 2,
              y: worldPos.dy - targetHeight / 2,
              width: targetWidth,
              height: targetHeight,
              payload: paperPayload as NodePayload,
            );
            ref.read(documentNodesProvider.notifier).addNode(paperNode);
            ref.read(selectionProvider.notifier).select(paperNode.id);
            ref.read(activeToolProvider.notifier).setTool(CanvasTool.select);
          },
        ),
      );
      return;
    }

    if (activeTool == CanvasTool.comment) {
      final hit = CanvasHitTester.hitTest(
        ref.read(documentNodesProvider),
        worldPos,
      );
      _showAddCommentEditor(worldPos, hit?.id);
      ref.read(activeToolProvider.notifier).setTool(CanvasTool.select);
      return;
    }

    if (activeTool == CanvasTool.annotate) {
      final nodes = ref.read(documentNodesProvider);
      final hit = CanvasHitTester.hitTest(nodes, worldPos);
      if (hit != null) {
        final local = Offset(worldPos.dx - hit.x, worldPos.dy - hit.y);

        // If clicked directly on an existing pin of the node
        final currentPins =
            hit.type == NodeType.annotatedImage &&
                hit.payload is AnnotatedImagePayload
            ? (hit.payload as AnnotatedImagePayload).pins
            : hit.pins;

        int clickedPinIdx = -1;
        for (int i = 0; i < currentPins.length; i++) {
          if ((currentPins[i].position - local).distance <= 20.0) {
            clickedPinIdx = i;
            break;
          }
        }
        if (clickedPinIdx != -1) {
          _showAnnotationPinEditor(hit, clickedPinIdx);
          return;
        }

        final pin = ImageAnnotationPin(
          id: const Uuid().v4(),
          position: local,
          text: '',
          createdAt: DateTime.now(),
        );

        if (hit.type == NodeType.annotatedImage &&
            hit.payload is AnnotatedImagePayload) {
          final ap = hit.payload as AnnotatedImagePayload;
          final updatedPins = [...ap.pins, pin];
          final updatedNode = hit.copyWith(
            payload: ap.copyWith(pins: updatedPins),
          );
          ref.read(documentNodesProvider.notifier).updateNode(updatedNode);
          ref.read(documentNodesProvider.notifier).bringToFront(hit.id);
          _showAnnotationPinEditor(updatedNode, updatedPins.length - 1);
        } else {
          // Add pin directly to the existing node (Rectangle, Frame, Shape, SketchCard, etc)
          final updatedPins = [...hit.pins, pin];
          final updatedNode = hit.copyWith(pins: updatedPins);
          ref.read(documentNodesProvider.notifier).updateNode(updatedNode);
          ref.read(documentNodesProvider.notifier).bringToFront(hit.id);
          ref.read(selectionProvider.notifier).select(updatedNode.id);
          _showAnnotationPinEditor(updatedNode, updatedPins.length - 1);
        }
      } else {
        showUiToast(
          context,
          'Annotate: click any node or card to place an annotation pin.',
        );
      }
      return;
    }

    if (activeTool == CanvasTool.select) {
      final hit = _hitTestForSelection(worldPos);
      if (hit != null) {
        // Interactive Toggle for Column Container Cards
        if (hit.type == NodeType.columnContainer &&
            hit.payload is ColumnPayload) {
          final payload = hit.payload as ColumnPayload;
          if (!payload.isCollapsed) {
            final localY = worldPos.dy - hit.y;
            final localX = worldPos.dx - hit.x;
            final visibleCards = payload.cards.where((c) {
              if (payload.filterMode == 'active') return !c.isDone;
              if (payload.filterMode == 'done') return c.isDone;
              return true;
            }).toList();

            double curY = 46.0;
            for (int i = 0; i < visibleCards.length; i++) {
              final card = visibleCards[i];
              final hasMetadata =
                  card.tags.isNotEmpty ||
                  card.dueDate != null ||
                  card.assignee != null ||
                  card.description.isNotEmpty;
              final cardHeight = hasMetadata ? 48.0 : 34.0;

              if (localY >= curY &&
                  localY <= curY + cardHeight &&
                  localX >= 8 &&
                  localX <= 38) {
                final cardIndex = payload.cards.indexWhere(
                  (c) => c.id == card.id,
                );
                if (cardIndex != -1) {
                  final newCards = List<ColumnCardItem>.from(payload.cards);
                  newCards[cardIndex] = card.copyWith(isDone: !card.isDone);
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        hit.copyWith(
                          payload: payload.copyWith(cards: newCards),
                        ),
                      );
                  return;
                }
              }
              curY += cardHeight + 6.0;
            }
          }
        }

        // Interactive Toggle for TodoList Items
        if (hit.type == NodeType.todoList && hit.payload is TodoListPayload) {
          final payload = hit.payload as TodoListPayload;
          final localY = worldPos.dy - hit.y;
          final localX = worldPos.dx - hit.x;
          final headerOffset =
              (payload.showProgressBar && payload.items.isNotEmpty)
              ? 42.0
              : 34.0;
          if (localX >= 8 && localX <= 34 && localY >= headerOffset) {
            double curY = headerOffset;
            for (int i = 0; i < payload.items.length; i++) {
              final item = payload.items[i];
              final hasMeta =
                  item.dueDate != null ||
                  item.assignee != null ||
                  item.priority != TodoPriority.none ||
                  item.tags.isNotEmpty;
              final rowH = hasMeta ? 36.0 : 24.0;
              if (localY >= curY && localY <= curY + rowH) {
                final updatedItems = List<TodoItem>.from(payload.items);
                updatedItems[i] = item.copyWith(isDone: !item.isDone);
                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      hit.copyWith(
                        payload: payload.copyWith(items: updatedItems),
                      ),
                    );
                return;
              }
              curY += rowH;
            }
          }
        }

        // Interactive Checkbox Cell Click for Table Matrix
        if (hit.type == NodeType.tableGrid && hit.payload is TablePayload) {
          final payload = hit.payload as TablePayload;
          final localY = worldPos.dy - hit.y;
          final localX = worldPos.dx - hit.x;
          final colCount = math.max(1, payload.columns.length);
          final colWidth = hit.width / colCount;

          if (localY >= 28.0) {
            final rowIndex = ((localY - 28.0) / 24.0).floor();
            final colIndex = (localX / colWidth).floor();
            if (rowIndex >= 0 &&
                rowIndex < payload.rows.length &&
                colIndex >= 0 &&
                colIndex < payload.columns.length) {
              final cellType = payload.typeForColumn(colIndex);
              if (cellType == TableCellType.checkbox) {
                final cellX = colIndex * colWidth;
                final cellRelativeX = localX - cellX;
                if (cellRelativeX >= 4 && cellRelativeX <= 28) {
                  final newRows = payload.rows
                      .map((r) => List<String>.from(r))
                      .toList();
                  final currentVal = newRows[rowIndex][colIndex];
                  final isChecked =
                      currentVal.toLowerCase() == 'true' ||
                      currentVal == '1' ||
                      currentVal.toLowerCase() == 'x';
                  newRows[rowIndex][colIndex] = isChecked ? 'false' : 'true';
                  ref
                      .read(documentNodesProvider.notifier)
                      .updateNode(
                        hit.copyWith(payload: payload.copyWith(rows: newRows)),
                      );
                  return;
                }
              }
            }
          }
        }

        // Interactive Pin Click on any node in Select Tool mode
        final currentPins =
            hit.type == NodeType.annotatedImage &&
                hit.payload is AnnotatedImagePayload
            ? (hit.payload as AnnotatedImagePayload).pins
            : hit.pins;
        if (currentPins.isNotEmpty) {
          final local = Offset(worldPos.dx - hit.x, worldPos.dy - hit.y);
          for (int i = 0; i < currentPins.length; i++) {
            final targetPoint = currentPins[i].position;
            final outsideBadgePos = Offset(
              hit.width + 16.0,
              targetPoint.dy.clamp(12.0, hit.height - 12.0),
            );
            // Check click either on target dot or on outside badge
            if ((targetPoint - local).distance <= 16.0 ||
                (outsideBadgePos - local).distance <= 20.0) {
              ref.read(selectionProvider.notifier).select(hit.id);
              _showAnnotationPinEditor(hit, i);
              return;
            }
          }
        }
        ref.read(selectionProvider.notifier).select(hit.id);
      } else {
        // Check if user tapped on a Smart Connector Edge
        final edges = ref.read(documentEdgesProvider);
        final nodes = ref.read(documentNodesProvider);
        final nodeMap = {for (final n in nodes) n.id: n};
        final zoom = ref.read(viewportProvider).zoom;
        final edgeHit = CanvasHitTester.hitTestEdge(
          edges,
          nodeMap,
          worldPos,
          tolerance: 14.0 / zoom,
        );

        if (edgeHit != null) {
          ref.read(selectionProvider.notifier).select(edgeHit.id);
        } else {
          ref.read(selectionProvider.notifier).clear();
        }
      }
    } else if (activeTool == CanvasTool.connector) {
      final hit = CanvasHitTester.hitTest(
        ref.read(documentNodesProvider),
        worldPos,
      );
      if (hit != null) {
        if (_connectorSourceNodeId == null) {
          setState(() {
            _connectorSourceNodeId = hit.id;
          });
          showUiToast(context, 'Source selected. Click target node to link.');
        } else if (_connectorSourceNodeId != hit.id) {
          final edge = CanvasEdge(
            id: const Uuid().v4(),
            sourceNodeId: _connectorSourceNodeId!,
            targetNodeId: hit.id,
          );
          ref.read(documentEdgesProvider.notifier).addEdge(edge);
          setState(() {
            _connectorSourceNodeId = null;
          });
          ref.read(activeToolProvider.notifier).setTool(CanvasTool.select);
        }
      } else {
        setState(() {
          _connectorSourceNodeId = null;
        });
      }
    } else if (activeTool == CanvasTool.image ||
        activeTool == CanvasTool.model3d ||
        activeTool == CanvasTool.fileCard ||
        activeTool == CanvasTool.linkCard ||
        activeTool == CanvasTool.videoCard ||
        activeTool == CanvasTool.audioCard ||
        activeTool == CanvasTool.mapCard ||
        activeTool == CanvasTool.embed ||
        activeTool == CanvasTool.sketchCard ||
        activeTool == CanvasTool.columnContainer ||
        activeTool == CanvasTool.nestedBoard ||
        activeTool == CanvasTool.tableGrid ||
        activeTool == CanvasTool.todoList ||
        activeTool == CanvasTool.document ||
        activeTool == CanvasTool.mermaid ||
        activeTool == CanvasTool.chart ||
        activeTool == CanvasTool.diagramShape) {
      _spawnNodeAt(activeTool, worldPos);
      ref.read(activeToolProvider.notifier).setTool(CanvasTool.select);
    }
  }

  void _finalizePenPath({bool isClosed = false}) {
    if (_activePenPoints.length < 2) {
      setState(() {
        _activePenPoints = [];
      });
      return;
    }

    final xs = _activePenPoints.map((p) => p.point.dx);
    final ys = _activePenPoints.map((p) => p.point.dy);
    final minX = xs.reduce((a, b) => a < b ? a : b);
    final maxX = xs.reduce((a, b) => a > b ? a : b);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);

    final localPoints = _activePenPoints.map((bp) {
      return BezierPoint(
        point: Offset(bp.point.dx - minX, bp.point.dy - minY),
        handleIn: bp.handleIn,
        handleOut: bp.handleOut,
      );
    }).toList();

    final penNode = CanvasNode(
      id: const Uuid().v4(),
      type: NodeType.vectorPath,
      x: minX,
      y: minY,
      width: (maxX - minX).clamp(10.0, double.infinity),
      height: (maxY - minY).clamp(10.0, double.infinity),
      payload: VectorPathPayload(points: localPoints, isClosed: isClosed),
    );

    ref.read(documentNodesProvider.notifier).addNode(penNode);
    ref.read(selectionProvider.notifier).select(penNode.id);

    setState(() {
      _activePenPoints = [];
    });
    ref.read(activeToolProvider.notifier).setTool(CanvasTool.select);
  }

  CommentReply _createCommentReply(String text) => CommentReply(
    id: const Uuid().v4(),
    authorId: _localUserId,
    authorName: _effectiveCollaborationDisplayName(),
    text: text.trim(),
    createdAt: DateTime.now(),
  );

  void _addFeedbackReply(CanvasComment parent, String text) {
    if (!_collaborationCanComment || text.trim().isEmpty) return;
    _addCommentReply(parent, _createCommentReply(text));
  }

  void _addNewCommentToThread(CanvasComment anchor, String text) {
    final normalized = text.trim();
    if (!_collaborationCanComment || normalized.isEmpty) return;
    final comment = CanvasComment(
      id: const Uuid().v4(),
      feedbackThreadId: anchor.feedbackThreadKey,
      nodeId: anchor.nodeId,
      authorId: _localUserId,
      authorName: _effectiveCollaborationDisplayName(),
      text: normalized,
      mentions: CommentNotificationFactory.extractMentions(normalized),
      x: anchor.x,
      y: anchor.y,
      createdAt: DateTime.now(),
    );
    ref
        .read(collaborationCommentsProvider(_projectionScope).notifier)
        .addComment(comment);
    _persistComment(comment);
    if (mounted) {
      setState(() => _focusedCommentId = comment.id);
    }
  }

  void _addCommentReply(CanvasComment parent, CommentReply reply) {
    if (!_collaborationCanComment) return;
    final session = _collaborationSession;
    if (session != null) {
      session.insertCommentReply(commentId: parent.id, reply: reply);
    } else {
      final updated = parent.copyWith(replies: [...parent.replies, reply]);
      ref
          .read(collaborationCommentsProvider(_projectionScope).notifier)
          .upsertComment(updated);
      _persistComment(updated);
    }
  }

  void _editCommentReply(
    CanvasComment parent,
    CommentReply reply,
    String text,
  ) {
    final normalized = text.trim();
    if (!_collaborationCanComment || normalized.isEmpty) return;
    if (normalized == reply.text.trim()) return;
    final updatedReply = reply.copyWith(
      text: normalized,
      editedAt: DateTime.now(),
    );
    final session = _collaborationSession;
    if (session != null) {
      session.upsertCommentReply(commentId: parent.id, reply: updatedReply);
      return;
    }
    final updated = parent.copyWith(
      replies: [
        for (final existing in parent.replies)
          if (existing.id == reply.id) updatedReply else existing,
      ],
    );
    ref
        .read(collaborationCommentsProvider(_projectionScope).notifier)
        .upsertComment(updated);
    _persistComment(updated);
  }

  Future<void> _confirmDeleteCommentReply(
    CanvasComment parent,
    CommentReply reply,
  ) async {
    if (!_collaborationCanComment) return;
    final confirmed = await showUiDialog<bool>(
      context: context,
      builder: (dialogContext) => UiDialog(
        semanticsLabel: 'Hapus balasan',
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md + AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hapus balasan?', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
              Text(
                'Balasan dari ${reply.authorName} akan dihapus dari komentar ini.',
                style: TextStyle(color: context.appTokens.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg + AppSpacing.xxs),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  UiButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    variant: UiButtonVariant.ghost,
                    child: const Text('Batal'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  UiButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    variant: UiButtonVariant.destructive,
                    prefix: const Icon(Icons.delete_outline_rounded, size: 15),
                    child: const Text('Hapus'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    _deleteCommentReply(parent, reply);
  }

  void _deleteCommentReply(CanvasComment parent, CommentReply reply) {
    final session = _collaborationSession;
    if (session != null) {
      session.deleteCommentReply(commentId: parent.id, replyId: reply.id);
      return;
    }
    final updated = parent.copyWith(
      replies: parent.replies
          .where((existing) => existing.id != reply.id)
          .toList(),
    );
    ref
        .read(collaborationCommentsProvider(_projectionScope).notifier)
        .upsertComment(updated);
    _persistComment(updated);
  }

  void _saveCommentText(CanvasComment comment, String text) {
    final normalized = text.trim();
    if (!_collaborationCanComment || normalized.isEmpty) return;
    final isDraft = comment.text.trim().isEmpty;
    final textChanged = normalized != comment.text.trim();
    final updated = comment.copyWith(
      text: normalized,
      mentions: CommentNotificationFactory.extractMentions(normalized),
      editedAt: !isDraft && textChanged ? DateTime.now() : comment.editedAt,
    );
    ref
        .read(collaborationCommentsProvider(_projectionScope).notifier)
        .upsertComment(updated);
    _persistComment(updated);
    if (mounted) {
      setState(() {
        if (_feedbackNodeId == comment.id) _feedbackNodeId = null;
        _focusedCommentId = comment.id;
      });
    }
  }

  void _cancelCommentDraft(CanvasComment comment) {
    if (comment.text.isEmpty) {
      ref
          .read(collaborationCommentsProvider(_projectionScope).notifier)
          .deleteComment(comment.id);
    }
    if (mounted) {
      setState(() {
        if (_feedbackNodeId == comment.id) _feedbackNodeId = null;
        if (_focusedCommentId == comment.id) _focusedCommentId = null;
      });
    }
  }

  void _setCommentResolved(CanvasComment comment, bool resolved) {
    final session = _collaborationSession;
    if (session != null) {
      session.setCommentResolved(commentId: comment.id, resolved: resolved);
      return;
    }
    final updated = comment.copyWith(resolved: resolved);
    ref
        .read(collaborationCommentsProvider(_projectionScope).notifier)
        .upsertComment(updated);
    _persistComment(updated);
  }

  Future<void> _confirmDeleteComment(CanvasComment comment) async {
    if (!_collaborationCanComment) return;
    final confirmed = await showUiDialog<bool>(
      context: context,
      builder: (dialogContext) => UiDialog(
        semanticsLabel: 'Hapus komentar',
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(AppSpacing.md + AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hapus komentar?', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
              Text(
                'Komentar dari ${comment.authorName} akan dihapus dari canvas ini.',
                style: TextStyle(color: context.appTokens.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg + AppSpacing.xxs),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  UiButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    variant: UiButtonVariant.ghost,
                    child: const Text('Batal'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  UiButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    variant: UiButtonVariant.destructive,
                    prefix: const Icon(Icons.delete_outline_rounded, size: 15),
                    child: const Text('Hapus'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      if (_feedbackNodeId == comment.id) _feedbackNodeId = null;
      if (_focusedCommentId == comment.id) _focusedCommentId = null;
    });
    _deleteComment(comment);
  }

  void _deleteComment(CanvasComment comment) {
    final session = _collaborationSession;
    if (session != null) {
      session.deleteComment(comment.id);
      return;
    }
    ref
        .read(collaborationCommentsProvider(_projectionScope).notifier)
        .deleteComment(comment.id);
    final sync = ref.read(supabaseSyncServiceProvider);
    if (sync.isConfigured) {
      unawaited(sync.deleteComment(comment.id, widget.projectId));
    }
  }

  void _toggleCommentReaction(CanvasComment comment, String emoji) {
    final session = _collaborationSession;
    final active =
        session?.isCommentReactionActive(
          commentId: comment.id,
          userId: _localUserId,
          emoji: emoji,
        ) ??
        ((comment.reactions[emoji] ?? 0) > 0);
    if (session != null) {
      session.setCommentReaction(
        commentId: comment.id,
        userId: _localUserId,
        emoji: emoji,
        active: !active,
      );
      return;
    }
    final reactions = Map<String, int>.from(comment.reactions);
    if (active) {
      final next = (reactions[emoji] ?? 1) - 1;
      if (next <= 0) {
        reactions.remove(emoji);
      } else {
        reactions[emoji] = next;
      }
    } else {
      reactions[emoji] = (reactions[emoji] ?? 0) + 1;
    }
    final updated = comment.copyWith(reactions: reactions);
    ref
        .read(collaborationCommentsProvider(_projectionScope).notifier)
        .upsertComment(updated);
    _persistComment(updated);
  }

  void _showAddCommentEditor(Offset worldPos, String? nodeId) {
    if (!_collaborationCanComment) return;
    final commentId = const Uuid().v4();
    final comment = CanvasComment(
      id: commentId,
      feedbackThreadId: commentId,
      nodeId: nodeId,
      authorId: _localUserId,
      authorName: _effectiveCollaborationDisplayName(),
      text: '',
      x: worldPos.dx,
      y: worldPos.dy,
      createdAt: DateTime.now(),
    );
    ref
        .read(collaborationCommentsProvider(_projectionScope).notifier)
        .addComment(comment);
    setState(() => _feedbackNodeId = comment.id);
  }

  void _copySelection({bool cut = false}) {
    final ids = ref.read(selectionProvider).toSet();
    if (ids.isEmpty) return;

    final allNodes = ref.read(documentNodesProvider);
    final nodes = allNodes.where((n) => ids.contains(n.id)).toList();
    final nodeIds = nodes.map((node) => node.id).toSet();
    final nodeMap = {for (final node in allNodes) node.id: node};
    final edges = ref
        .read(documentEdgesProvider)
        .where(
          (edge) =>
              ids.contains(edge.id) ||
              (edge.sourceNodeId != null &&
                  nodeIds.contains(edge.sourceNodeId)) ||
              (edge.targetNodeId != null &&
                  nodeIds.contains(edge.targetNodeId)),
        )
        .map((edge) {
          final sourceIncluded =
              edge.sourceNodeId != null && nodeIds.contains(edge.sourceNodeId);
          final targetIncluded =
              edge.targetNodeId != null && nodeIds.contains(edge.targetNodeId);
          final sourcePoint = sourceIncluded
              ? null
              : edge.sourceNodeId == null
              ? edge.sourcePoint
              : ConnectorRouter.endpointPointForEdge(
                  edge,
                  nodeMap,
                  source: true,
                );
          final targetPoint = targetIncluded
              ? null
              : edge.targetNodeId == null
              ? edge.targetPoint
              : ConnectorRouter.endpointPointForEdge(
                  edge,
                  nodeMap,
                  source: false,
                );
          return edge.copyWith(
            sourceNodeId: sourceIncluded ? edge.sourceNodeId : null,
            sourcePoint: sourcePoint,
            targetNodeId: targetIncluded ? edge.targetNodeId : null,
            targetPoint: targetPoint,
          );
        })
        .toList();

    setState(() {
      _clipboardNodes = nodes
          .map((n) => n.copyWith(payload: n.payload.clone()))
          .toList();
      _clipboardEdges = edges;
      _pasteCount = 1;
    });

    if (cut) {
      ref.read(documentNodesProvider.notifier).deleteNodes(ids.toList());
      ref.read(selectionProvider.notifier).clear();
    }
  }

  void _pasteClipboard() {
    if (_clipboardNodes.isEmpty) return;

    final offset = 24.0 * _pasteCount;
    _pasteCount++;
    final idMap = <String, String>{};
    final baseZ = ref.read(documentNodesProvider).length;
    final newNodes = <CanvasNode>[];

    for (var i = 0; i < _clipboardNodes.length; i++) {
      final src = _clipboardNodes[i];
      final newId = const Uuid().v4();
      idMap[src.id] = newId;
      newNodes.add(
        src.copyWith(
          id: newId,
          x: src.x + offset,
          y: src.y + offset,
          zIndex: baseZ + i,
          payload: src.payload.clone(),
        ),
      );
    }

    for (final node in newNodes) {
      ref.read(documentNodesProvider.notifier).addNode(node);
    }
    final newEdgeIds = <String>[];
    for (final edge in _clipboardEdges) {
      final sourceId = edge.sourceNodeId == null
          ? null
          : idMap[edge.sourceNodeId];
      final targetId = edge.targetNodeId == null
          ? null
          : idMap[edge.targetNodeId];
      final newEdge = edge.copyWith(
        id: const Uuid().v4(),
        sourceNodeId: sourceId,
        sourcePoint: sourceId == null
            ? _shiftClipboardPoint(edge.sourcePoint, offset)
            : null,
        targetNodeId: targetId,
        targetPoint: targetId == null
            ? _shiftClipboardPoint(edge.targetPoint, offset)
            : null,
        waypoints: edge.waypoints
            .map((point) => point + Offset(offset, offset))
            .toList(growable: false),
      );
      if (newEdge.sourceNodeId != null || newEdge.sourcePoint != null) {
        if (newEdge.targetNodeId != null || newEdge.targetPoint != null) {
          ref.read(documentEdgesProvider.notifier).addEdge(newEdge);
          newEdgeIds.add(newEdge.id);
        }
      }
    }

    ref.read(selectionProvider.notifier).selectAll([
      ...newNodes.map((n) => n.id),
      ...newEdgeIds,
    ]);
  }

  Offset? _shiftClipboardPoint(Offset? point, double offset) {
    return point == null ? null : point + Offset(offset, offset);
  }

  Future<void> _spawnNodeAt(CanvasTool tool, Offset pos) async {
    final id = const Uuid().v4();
    CanvasNode? newNode;
    DocumentAsset? pendingAsset;
    int? pendingArtifactGeneration;
    String? pendingArtifactProjectId;
    String? pendingArtifactAccountId;

    switch (tool) {
      case CanvasTool.diagramShape:
        final shape = ref.read(activeDiagramShapeProvider);
        final size = shape.defaultSize;
        final nodeType = switch (shape.nodeKind) {
          DiagramShapeNodeKind.ellipse => NodeType.ellipse,
          DiagramShapeNodeKind.diamond => NodeType.diamond,
          DiagramShapeNodeKind.cylinder => NodeType.cylinder,
          DiagramShapeNodeKind.parallelogram => NodeType.parallelogram,
          DiagramShapeNodeKind.rectangle => NodeType.rectangle,
        };
        newNode = CanvasNode(
          id: id,
          type: nodeType,
          x: pos.dx - size.width / 2,
          y: pos.dy - size.height / 2,
          width: size.width,
          height: size.height,
          payload: ShapePayload(
            diagramShapeId: shape.id,
            cornerRadius: shape.defaultCornerRadius,
            label: '',
            fill: const Color(0xFF334155),
            stroke: const Color(0xFF94A3B8),
          ),
        );
        break;
      case CanvasTool.chart:
        final chartType = ref.read(activeChartTypeProvider);
        newNode = CanvasNode(
          id: id,
          type: NodeType.chart,
          x: pos.dx - 180,
          y: pos.dy - 120,
          width: 360,
          height: 240,
          payload: ChartPayload(
            title: '${chartType.name.toUpperCase()} CHART',
            chartType: chartType,
          ),
        );
        break;
      case CanvasTool.rectangle:
        newNode = CanvasNode(
          id: id,
          type: NodeType.rectangle,
          x: pos.dx - 60,
          y: pos.dy - 40,
          width: 120,
          height: 80,
          payload: ShapePayload(),
        );
        break;
      case CanvasTool.ellipse:
        newNode = CanvasNode(
          id: id,
          type: NodeType.ellipse,
          x: pos.dx - 50,
          y: pos.dy - 50,
          width: 100,
          height: 100,
          payload: ShapePayload(
            fill: const Color(0xFF10B981),
            stroke: const Color(0xFF34D399),
          ),
        );
        break;
      case CanvasTool.diamond:
        newNode = CanvasNode(
          id: id,
          type: NodeType.diamond,
          x: pos.dx - 60,
          y: pos.dy - 45,
          width: 120,
          height: 90,
          payload: ShapePayload(
            fill: const Color(0xFFD97706),
            stroke: const Color(0xFFFBBF24),
          ),
        );
        break;
      case CanvasTool.cylinder:
        newNode = CanvasNode(
          id: id,
          type: NodeType.cylinder,
          x: pos.dx - 50,
          y: pos.dy - 60,
          width: 100,
          height: 120,
          payload: ShapePayload(
            fill: const Color(0xFF2563EB),
            stroke: const Color(0xFF60A5FA),
          ),
        );
        break;
      case CanvasTool.parallelogram:
        newNode = CanvasNode(
          id: id,
          type: NodeType.parallelogram,
          x: pos.dx - 65,
          y: pos.dy - 40,
          width: 130,
          height: 80,
          payload: ShapePayload(
            fill: const Color(0xFF10B981),
            stroke: const Color(0xFF34D399),
          ),
        );
        break;
      case CanvasTool.line:
        newNode = CanvasNode(
          id: id,
          type: NodeType.line,
          x: pos.dx - 60,
          y: pos.dy,
          width: 120,
          height: 0,
          payload: ShapePayload(
            strokeWidth: 2.5,
            stroke: const Color(0xFFF97316),
          ),
        );
        break;
      case CanvasTool.arrow:
        newNode = CanvasNode(
          id: id,
          type: NodeType.arrow,
          x: pos.dx - 60,
          y: pos.dy,
          width: 120,
          height: 0,
          payload: ShapePayload(
            strokeWidth: 2.5,
            stroke: const Color(0xFFF97316),
          ),
        );
        break;
      case CanvasTool.stickyNote:
        newNode = CanvasNode(
          id: id,
          type: NodeType.stickyNote,
          x: pos.dx - 70,
          y: pos.dy - 70,
          width: 140,
          height: 140,
          payload: StickyNotePayload(),
        );
        break;
      case CanvasTool.text:
        newNode = CanvasNode(
          id: id,
          type: NodeType.text,
          x: pos.dx - 60,
          y: pos.dy - 15,
          width: 160,
          height: 40,
          payload: TextPayload(),
        );
        break;
      case CanvasTool.frame:
        newNode = CanvasNode(
          id: id,
          type: NodeType.frame,
          x: pos.dx - 150,
          y: pos.dy - 100,
          width: 300,
          height: 200,
          payload: FramePayload(),
        );
        break;
      case CanvasTool.component:
        newNode = CanvasNode(
          id: id,
          type: NodeType.component,
          x: pos.dx - 90,
          y: pos.dy - 50,
          width: 180,
          height: 100,
          payload: ComponentPayload(
            masterComponentId: id,
            componentName: 'Primary Button',
            isMaster: true,
          ),
        );
        break;
      case CanvasTool.pen:
        newNode = CanvasNode(
          id: id,
          type: NodeType.vectorPath,
          x: pos.dx - 60,
          y: pos.dy - 60,
          width: 120,
          height: 120,
          payload: VectorPathPayload(
            points: const [
              BezierPoint(point: Offset(0, 60), handleOut: Offset(20, -40)),
              BezierPoint(
                point: Offset(60, 0),
                handleIn: Offset(-30, 0),
                handleOut: Offset(30, 0),
              ),
              BezierPoint(point: Offset(120, 60), handleIn: Offset(0, -30)),
              BezierPoint(
                point: Offset(60, 120),
                handleIn: Offset(30, 0),
                handleOut: Offset(-30, 0),
              ),
            ],
            isClosed: true,
          ),
        );
        break;
      case CanvasTool.model3d:
        final generation = ++_artifactOperationGeneration;
        final projectId = widget.projectId;
        final accountId = ref.read(supabaseSyncServiceProvider).currentUserId;
        final preparedModel = await _pickModel3DNode(
          pos,
          operationGeneration: generation,
          expectedUserId: accountId,
          registerAsset: false,
        );
        if (!_isArtifactOperationCurrent(
              generation: generation,
              projectId: projectId,
              accountId: accountId,
            ) ||
            preparedModel == null) {
          return;
        }
        pendingAsset = preparedModel.asset;
        pendingArtifactGeneration = generation;
        pendingArtifactProjectId = projectId;
        pendingArtifactAccountId = accountId;
        newNode = preparedModel.node;
        break;
      case CanvasTool.fileCard:
        final generation = ++_artifactOperationGeneration;
        final projectId = widget.projectId;
        final accountId = ref.read(supabaseSyncServiceProvider).currentUserId;
        final filePicker = AssetService(ref.read(supabaseSyncServiceProvider));
        final fileResult =
            await (widget.services.pickAnyFile?.call(projectId: projectId) ??
                filePicker.pickAnyFile(projectId: projectId));
        if (!_isArtifactOperationCurrent(
              generation: generation,
              projectId: projectId,
              accountId: accountId,
            ) ||
            fileResult == null) {
          return;
        }
        final fileName = fileResult.name;
        final ext = fileResult.fileExt;
        final sizeStr = fileResult.formattedSize;
        final bytes = fileResult.bytes;
        final savedFile = bytes == null || bytes.isEmpty
            ? null
            : await _fileArtifactStore.save(bytes, fileName: fileName);
        if (!_isArtifactOperationCurrent(
          generation: generation,
          projectId: projectId,
          accountId: accountId,
        )) {
          return;
        }
        final artifactReference = validFileArtifactReference(
          savedFile?.reference,
        );
        if (!mounted) return;
        if (artifactReference == null) {
          showUiToast(
            context,
            'The file could not be stored in owned artifact storage.',
            variant: UiToastVariant.error,
          );
          return;
        }
        final asset = buildDocumentAsset(
          id: id,
          kind: DocumentAssetKind.document,
          name: fileName,
          mimeType: fileResult.detectedMimeType,
          artifactReference: artifactReference,
          storagePath: null,
          declaredSize: fileResult.size,
          bytes: bytes,
        );
        if (asset == null) {
          if (!mounted) return;
          showUiToast(
            context,
            'The file could not be registered in the asset manifest.',
            variant: UiToastVariant.error,
          );
          return;
        }
        pendingAsset = asset;
        pendingArtifactGeneration = generation;
        pendingArtifactProjectId = projectId;
        pendingArtifactAccountId = accountId;

        newNode = CanvasNode(
          id: id,
          type: NodeType.fileCard,
          x: pos.dx - 120,
          y: pos.dy - 35,
          width: 240,
          height: 70,
          payload: FilePayload(
            fileName: fileName,
            fileExtension: ext,
            fileSizeText: sizeStr,
            assetId: id,
            artifactReference: artifactReference,
          ),
        );
        break;
      case CanvasTool.linkCard:
        newNode = CanvasNode(
          id: id,
          type: NodeType.linkCard,
          x: pos.dx - 160,
          y: pos.dy - 110,
          width: 320,
          height: 220,
          payload: LinkPayload(),
        );
        break;
      case CanvasTool.videoCard:
        final videoResult = AssetPickerResult(name: 'Add video from Inspector');
        newNode = CanvasNode(
          id: id,
          type: NodeType.videoCard,
          x: pos.dx - 120,
          y: pos.dy - 75,
          width: 240,
          height: 150,
          payload: VideoPayload(
            title: videoResult.name,
            durationText: 'Unknown',
          ),
        );
        break;
      case CanvasTool.audioCard:
        final audioResult = AssetPickerResult(name: 'Add audio from Inspector');
        newNode = CanvasNode(
          id: id,
          type: NodeType.audioCard,
          x: pos.dx - 120,
          y: pos.dy - 35,
          width: 240,
          height: 70,
          payload: AudioPayload(trackName: audioResult.name),
        );
        break;
      case CanvasTool.mapCard:
        newNode = CanvasNode(
          id: id,
          type: NodeType.mapCard,
          x: pos.dx - 100,
          y: pos.dy - 80,
          width: 200,
          height: 160,
          payload: MapPayload(
            locationTitle: '',
            address: '',
            latitude: 0,
            longitude: 0,
            zoomLevel: 12,
          ),
        );
        break;
      case CanvasTool.colorSwatch:
        newNode = CanvasNode(
          id: id,
          type: NodeType.colorSwatch,
          x: pos.dx - 60,
          y: pos.dy - 70,
          width: 120,
          height: 140,
          payload: ColorSwatchPayload(
            label: 'Industrial Orange',
            color: const Color(0xFFF97316),
            colorHex: '#F97316',
          ),
        );
        break;
      case CanvasTool.document:
        newNode = CanvasNode(
          id: id,
          type: NodeType.document,
          x: pos.dx - 140,
          y: pos.dy - 100,
          width: 280,
          height: 200,
          payload: DocumentPayload(),
        );
        break;
      case CanvasTool.embed:
        newNode = CanvasNode(
          id: id,
          type: NodeType.embed,
          x: pos.dx - 140,
          y: pos.dy - 90,
          width: 280,
          height: 180,
          payload: EmbedPayload(),
        );
        break;
      case CanvasTool.mermaid:
        newNode = CanvasNode(
          id: id,
          type: NodeType.mermaid,
          x: pos.dx - 240,
          y: pos.dy - 160,
          width: 480,
          height: 320,
          payload: MermaidPayload(),
        );
        break;
      case CanvasTool.sketchCard:
        newNode = CanvasNode(
          id: id,
          type: NodeType.sketchCard,
          x: pos.dx - 120,
          y: pos.dy - 80,
          width: 240,
          height: 160,
          payload: SketchCardPayload(
            title: 'Quick Wireframe',
            strokes: const [
              [
                Offset(30, 60),
                Offset(60, 40),
                Offset(110, 80),
                Offset(170, 50),
                Offset(210, 90),
              ],
            ],
            strokeColor: const Color(0xFFF59E0B),
            strokeWidth: 2.5,
            backgroundColor: const Color(0xFF1E2028),
            cardPattern: 'dots',
            smoothCurves: true,
          ),
        );
        break;
      case CanvasTool.columnContainer:
        newNode = CanvasNode(
          id: id,
          type: NodeType.columnContainer,
          x: pos.dx - 110,
          y: pos.dy - 120,
          width: 220,
          height: 240,
          payload: ColumnPayload(
            headerTitle: 'Sprint Backlog',
            headerColor: const Color(0xFFF97316),
            itemTitles: const [
              '1. Implement Canvas Engine',
              '2. Add Color Palette',
              '3. QA & Release',
            ],
          ),
        );
        break;
      case CanvasTool.nestedBoard:
        newNode = CanvasNode(
          id: id,
          type: NodeType.nestedBoard,
          x: pos.dx - 125,
          y: pos.dy - 80,
          width: 250,
          height: 160,
          payload: NestedBoardPayload(
            boardName: 'Brand Strategy Board',
            childNodeCount: 16,
          ),
        );
        break;
      case CanvasTool.tableGrid:
        newNode = CanvasNode(
          id: id,
          type: NodeType.tableGrid,
          x: pos.dx - 140,
          y: pos.dy - 65,
          width: 280,
          height: 130,
          payload: TablePayload(
            columns: const ['Module', 'Effort', 'Lead'],
            rows: const [
              ['Canvas Painter', '3 Days', 'Alex'],
              ['Vector Engine', '5 Days', 'Sarah'],
              ['Cloud Sync', '2 Days', 'Dev'],
            ],
          ),
        );
        break;
      case CanvasTool.todoList:
        newNode = CanvasNode(
          id: id,
          type: NodeType.todoList,
          x: pos.dx - 100,
          y: pos.dy - 80,
          width: 200,
          height: 160,
          payload: TodoListPayload(
            title: 'Design Review Checklist',
            items: [
              TodoItem(id: '1', text: 'Color contrast check', isDone: true),
              TodoItem(id: '2', text: 'Typography hierarchy', isDone: true),
              TodoItem(id: '3', text: 'Touch targets >= 44px', isDone: false),
            ],
          ),
        );
        break;
      case CanvasTool.image:
        final generation = ++_artifactOperationGeneration;
        final projectId = widget.projectId;
        final sync = ref.read(supabaseSyncServiceProvider);
        final accountId = sync.currentUserId;
        final picker = AssetService(sync);
        final assetResult =
            await (widget.services.pickImage?.call(projectId: projectId) ??
                picker.pickImage(projectId: projectId));
        if (!_isArtifactOperationCurrent(
              generation: generation,
              projectId: projectId,
              accountId: accountId,
            ) ||
            assetResult == null) {
          return;
        }
        final bytes = assetResult.bytes;
        final imageReference = bytes == null || bytes.isEmpty
            ? null
            : validImageArtifactReference(
                (await _imageArtifactStore.save(
                  bytes,
                  fileName: assetResult.name,
                )).reference,
              );
        if (!_isArtifactOperationCurrent(
          generation: generation,
          projectId: projectId,
          accountId: accountId,
        )) {
          return;
        }
        final storagePath = _validatedImageStoragePath(assetResult.storagePath);
        if (!mounted) return;
        if (imageReference == null && storagePath == null) {
          showUiToast(
            context,
            'The selected image could not be stored.',
            variant: UiToastVariant.error,
          );
          return;
        }
        double initW = 240;
        double initH = 180;
        if (bytes != null && bytes.isNotEmpty && imageReference != null) {
          final img = await _imageCache.decodeAndCacheBytes(
            imageReference,
            bytes,
          );
          if (!_isArtifactOperationCurrent(
            generation: generation,
            projectId: projectId,
            accountId: accountId,
          )) {
            return;
          }
          if (img != null) {
            // Scale aspect ratio naturally
            const maxDim = 320.0;
            final aspect = img.width / img.height;
            if (img.width >= img.height) {
              initW = maxDim;
              initH = maxDim / aspect;
            } else {
              initH = maxDim;
              initW = maxDim * aspect;
            }
          }
        }
        final asset = buildDocumentAsset(
          id: id,
          kind: DocumentAssetKind.image,
          name: assetResult.name,
          mimeType: assetResult.detectedMimeType,
          artifactReference: imageReference,
          storagePath: storagePath,
          declaredSize: assetResult.size,
          bytes: bytes,
        );
        if (asset == null) {
          if (!mounted) return;
          showUiToast(
            context,
            'The selected image could not be registered in the asset manifest.',
            variant: UiToastVariant.error,
          );
          return;
        }
        pendingAsset = asset;
        pendingArtifactGeneration = generation;
        pendingArtifactProjectId = projectId;
        pendingArtifactAccountId = accountId;
        newNode = CanvasNode(
          id: id,
          type: NodeType.image,
          x: pos.dx - initW / 2,
          y: pos.dy - initH / 2,
          width: initW,
          height: initH,
          payload: ImagePayload(
            imageArtifactReference: imageReference,
            storagePath: storagePath,
            assetId: id,
          ),
        );
        break;
      default:
        break;
    }

    if (newNode != null) {
      if (pendingAsset != null) {
        final generation = pendingArtifactGeneration;
        final projectId = pendingArtifactProjectId;
        final accountId = pendingArtifactAccountId;
        if (generation == null ||
            projectId == null ||
            !_isArtifactOperationCurrent(
              generation: generation,
              projectId: projectId,
              accountId: accountId,
            )) {
          return;
        }
        final originalManifest = ref.read(documentAssetsProvider);
        publishDocumentAssetAndNode(
          originalManifest: originalManifest,
          committedManifest: originalManifest.upsert(pendingAsset),
          setManifest: (next) =>
              ref.read(documentAssetsProvider.notifier).setManifest(next),
          publishNode: () {
            ref.read(documentNodesProvider.notifier).addNode(newNode!);
          },
        );
      } else {
        ref.read(documentNodesProvider.notifier).addNode(newNode);
      }
      ref.read(selectionProvider.notifier).select(newNode.id);
      if (tool == CanvasTool.text || tool == CanvasTool.diagramShape) {
        _startInlineEdit(newNode, frameLabel: false);
      } else if (tool == CanvasTool.mermaid) {
        unawaited(_openMermaidEditor(newNode));
      }
    }
  }

  void _applyEraserAt(Offset worldPos, BrushConfig config) {
    final nodes = ref.read(documentNodesProvider);
    final eraserRadius = config.strokeWidth / 2.0;

    if (config.eraserMode == EraserMode.stroke) {
      final toDeleteIds = <String>[];
      for (final node in nodes) {
        if (BrushEraserEngine.intersectsDrawingNode(
          node,
          worldPos,
          eraserRadius,
        )) {
          toDeleteIds.add(node.id);
        }
      }
      if (toDeleteIds.isNotEmpty) {
        ref.read(documentNodesProvider.notifier).deleteNodes(toDeleteIds);
      }
    } else {
      // Precise Partial/Pixel Cutout eraser mode
      for (final node in nodes) {
        if (BrushEraserEngine.intersectsDrawingNode(
          node,
          worldPos,
          eraserRadius,
        )) {
          final updatedNode = BrushEraserEngine.applyCutout(
            node,
            worldPos,
            eraserRadius,
          );
          if (updatedNode != null) {
            ref.read(documentNodesProvider.notifier).updateNode(updatedNode);
          }
        }
      }
    }
  }

  bool _isShapeTool(CanvasTool tool) {
    return tool == CanvasTool.rectangle ||
        tool == CanvasTool.ellipse ||
        tool == CanvasTool.diamond ||
        tool == CanvasTool.cylinder ||
        tool == CanvasTool.parallelogram ||
        tool == CanvasTool.line ||
        tool == CanvasTool.arrow ||
        tool == CanvasTool.stickyNote ||
        tool == CanvasTool.text ||
        tool == CanvasTool.frame ||
        tool == CanvasTool.component ||
        tool == CanvasTool.diagramShape;
  }

  bool _startConnectorControlDrag(Offset worldPos, double zoom) {
    if (_collaborationReadOnly) return false;
    final nodes = ref.read(documentNodesProvider);
    final edges = ref.read(documentEdgesProvider);
    final control = CanvasHitTester.hitTestConnectorControl(
      edges,
      {for (final node in nodes) node.id: node},
      ref.read(selectionProvider),
      worldPos,
      zoom: zoom,
    );
    if (control == null) return false;
    final edge = edges
        .where((candidate) => candidate.id == control.edgeId)
        .firstOrNull;
    if (edge == null) return false;
    setState(() {
      _connectorEditEdgeId = edge.id;
      _connectorEditControl = control;
      _connectorEditOriginal = edge;
      _connectorEditPreview = edge;
      _connectorEditLastWorldPosition = worldPos;
      _connectorSnapNodeId = null;
      _connectorSnapPoint = null;
      _isDraggingNodes = false;
    });
    return true;
  }

  (String, AnchorPosition, Offset)? _nearestConnectorSnap(
    CanvasEdge edge,
    Offset point, {
    required bool source,
    required double zoom,
  }) {
    final oppositeNodeId = source ? edge.targetNodeId : edge.sourceNodeId;
    final radius = 20.0 / zoom.clamp(0.25, 4.0);
    (String, AnchorPosition, Offset)? best;
    var bestDistance = radius;
    for (final node in ref.read(documentNodesProvider)) {
      if (!node.visible || node.locked || node.id == oppositeNodeId) continue;
      final candidate = ConnectorRouter.nearestAnchorWithin(
        node,
        point,
        radius: radius,
      );
      if (candidate == null) continue;
      final distance = (candidate.$2 - point).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = (node.id, candidate.$1, candidate.$2);
      }
    }
    return best;
  }

  CanvasEdge? _updateConnectorPreview(Offset worldPos) {
    final edge = _connectorEditPreview;
    final control = _connectorEditControl;
    if (edge == null || control == null) return null;
    final nodes = ref.read(documentNodesProvider);
    final nodeMap = {for (final node in nodes) node.id: node};
    CanvasEdge next = edge;

    switch (control.kind) {
      case ConnectorControlKind.sourceEndpoint:
      case ConnectorControlKind.targetEndpoint:
        final source = control.kind == ConnectorControlKind.sourceEndpoint;
        final snap = _nearestConnectorSnap(
          edge,
          worldPos,
          source: source,
          zoom: ref.read(viewportProvider).zoom,
        );
        if (source) {
          next = snap == null
              ? edge.copyWith(sourceNodeId: null, sourcePoint: worldPos)
              : edge.copyWith(
                  sourceNodeId: snap.$1,
                  sourceAnchor: snap.$2,
                  sourcePoint: null,
                );
        } else {
          next = snap == null
              ? edge.copyWith(targetNodeId: null, targetPoint: worldPos)
              : edge.copyWith(
                  targetNodeId: snap.$1,
                  targetAnchor: snap.$2,
                  targetPoint: null,
                );
        }
        setState(() {
          _connectorSnapNodeId = snap?.$1;
          _connectorSnapPoint = snap?.$3;
        });
        break;
      case ConnectorControlKind.waypoint:
        final index = control.waypointIndex;
        if (index == null) return null;
        var effectivePoint = worldPos;
        if (edge.routing == ConnectorRouting.orthogonal) {
          final route = ConnectorRouter.routePointsForEdge(edge, nodeMap);
          final routeIndex = index + 1;
          if (routeIndex > 0 && routeIndex < route.length - 1) {
            effectivePoint =
                ConnectorRouter.snapCornerToRightAngle(
                  route[routeIndex - 1],
                  worldPos,
                  route[routeIndex + 1],
                  tolerance:
                      12.0 / ref.read(viewportProvider).zoom.clamp(0.25, 4.0),
                ) ??
                worldPos;
          }
        }
        final waypoints = ConnectorRouter.moveWaypoint(
          edge,
          nodeMap,
          waypointIndex: index,
          point: effectivePoint,
        );
        next = edge.copyWith(waypoints: waypoints);
        setState(() {
          _connectorSnapNodeId = null;
          _connectorSnapPoint = null;
        });
        break;
      case ConnectorControlKind.segment:
        final index = control.segmentIndex;
        final previous = _connectorEditLastWorldPosition;
        if (index == null || previous == null) return null;
        final moved = ConnectorRouter.moveSegment(
          edge,
          nodeMap,
          segmentIndex: index,
          delta: worldPos - previous,
        );
        next = edge.copyWith(waypoints: moved);
        setState(() {
          _connectorSnapNodeId = null;
          _connectorSnapPoint = null;
        });
        break;
      case ConnectorControlKind.label:
        final route = ConnectorRouter.routePointsForEdge(edge, nodeMap);
        if (route.length < 2) return null;
        next = edge.copyWith(
          labelPosition: ConnectorRouter.routeFractionForPoint(route, worldPos),
        );
        setState(() {
          _connectorSnapNodeId = null;
          _connectorSnapPoint = null;
        });
        break;
    }

    setState(() {
      _connectorEditPreview = next;
      _connectorEditLastWorldPosition = worldPos;
    });
    return next;
  }

  void _cancelConnectorEdit() {
    if (_connectorEditEdgeId == null) return;
    setState(() {
      _connectorEditEdgeId = null;
      _connectorEditControl = null;
      _connectorEditOriginal = null;
      _connectorEditPreview = null;
      _connectorEditLastWorldPosition = null;
      _connectorSnapNodeId = null;
      _connectorSnapPoint = null;
    });
  }

  void _commitConnectorEdit() {
    final preview = _connectorEditPreview;
    final original = _connectorEditOriginal;
    if (preview != null && original != null) {
      ref.read(documentNodesProvider.notifier).updateEdge(preview);
    }
    _cancelConnectorEdit();
  }

  void _handleConnectorDoubleTap(Offset worldPos) {
    if (_collaborationReadOnly) return;
    final nodes = ref.read(documentNodesProvider);
    final edges = ref.read(documentEdgesProvider);
    final control = CanvasHitTester.hitTestConnectorControl(
      edges,
      {for (final node in nodes) node.id: node},
      ref.read(selectionProvider),
      worldPos,
      zoom: ref.read(viewportProvider).zoom,
    );
    if (control == null) return;
    final edge = edges
        .where((candidate) => candidate.id == control.edgeId)
        .firstOrNull;
    if (edge == null) return;

    if (control.kind == ConnectorControlKind.waypoint) {
      if (edge.waypoints.isEmpty || control.waypointIndex == null) return;
      final waypoints = List<Offset>.from(edge.waypoints)
        ..removeAt(control.waypointIndex!);
      ref
          .read(documentNodesProvider.notifier)
          .updateEdge(edge.copyWith(waypoints: waypoints));
      return;
    }
    if (control.kind != ConnectorControlKind.segment ||
        control.segmentIndex == null ||
        edge.routing != ConnectorRouting.orthogonal) {
      return;
    }
    if (edge.waypoints.length >= CanvasEdge.maxWaypoints) return;

    final route = ConnectorRouter.routePointsForEdge(edge, {
      for (final node in nodes) node.id: node,
    });
    final index = control.segmentIndex!;
    if (index < 0 || index >= route.length - 1) return;
    final start = route[index];
    final end = route[index + 1];
    final segment = end - start;
    final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
    final projection = lengthSquared == 0
        ? 0.0
        : (((worldPos - start).dx * segment.dx +
                      (worldPos - start).dy * segment.dy) /
                  lengthSquared)
              .clamp(0.0, 1.0);
    final insertionPoint = Offset(
      start.dx + segment.dx * projection,
      start.dy + segment.dy * projection,
    );
    final waypoints = edge.waypoints.isEmpty
        ? route.sublist(1, route.length - 1)
        : List<Offset>.from(edge.waypoints);
    final insertionIndex = index.clamp(0, waypoints.length);
    waypoints.insert(insertionIndex, insertionPoint);
    ref
        .read(documentNodesProvider.notifier)
        .updateEdge(edge.copyWith(waypoints: waypoints));
  }

  void _handlePanStart(DragStartDetails details, CanvasTool activeTool) {
    final startLocalPosition =
        _pointerDownLocalPosition ?? details.localPosition;
    _dragStart = startLocalPosition;
    final worldPos = ref
        .read(viewportProvider.notifier)
        .toWorld(startLocalPosition);
    if (activeTool == CanvasTool.sketchCard) {
      final nodes = ref.read(documentNodesProvider);
      final hitCard = nodes
          .where(
            (n) =>
                n.type == NodeType.sketchCard &&
                n.payload is SketchCardPayload &&
                worldPos.dx >= n.x &&
                worldPos.dx <= n.x + n.width &&
                worldPos.dy >= n.y &&
                worldPos.dy <= n.y + n.height,
          )
          .toList();

      if (hitCard.isNotEmpty) {
        final targetCard = hitCard.last;
        _drawingOnSketchCardId = targetCard.id;
        final localPos = Offset(
          worldPos.dx - targetCard.x,
          worldPos.dy - targetCard.y,
        );
        final oldPayload = targetCard.payload as SketchCardPayload;
        final newStrokes =
            oldPayload.strokes.map((s) => List<Offset>.from(s)).toList()
              ..add([localPos]);
        ref
            .read(documentNodesProvider.notifier)
            .updateNode(
              targetCard.copyWith(
                payload: oldPayload.copyWith(strokes: newStrokes),
              ),
            );
        ref.read(selectionProvider.notifier).select(targetCard.id);
        return;
      }
    }

    if (activeTool == CanvasTool.brush) {
      final brushConfig = ref.read(activeBrushConfigProvider);
      if (brushConfig.brushType == BrushType.eraser) {
        _applyEraserAt(worldPos, brushConfig);
      }
      setState(() {
        _activeBrushStroke = [worldPos];
      });
      return;
    }

    if (activeTool == CanvasTool.pen) {
      final isShiftPressed =
          HardwareKeyboard.instance.logicalKeysPressed.contains(
            LogicalKeyboardKey.shiftLeft,
          ) ||
          HardwareKeyboard.instance.logicalKeysPressed.contains(
            LogicalKeyboardKey.shiftRight,
          );
      var effectivePos = worldPos;
      if (isShiftPressed && _activePenPoints.isNotEmpty) {
        final last = _activePenPoints.last.point;
        final delta = worldPos - last;
        final angle = math.atan2(delta.dy, delta.dx);
        final snappedAngle = (angle / (math.pi / 4)).round() * (math.pi / 4);
        final dist = delta.distance;
        effectivePos = Offset(
          last.dx + dist * math.cos(snappedAngle),
          last.dy + dist * math.sin(snappedAngle),
        );
      }

      if (_activePenPoints.isNotEmpty) {
        // Dragging handle for the last point
        _isDraggingPenHandle = true;
      } else {
        setState(() {
          _activePenPoints = [BezierPoint(point: effectivePos)];
          _isDraggingPenHandle = true;
        });
      }
      return;
    }

    if (_isShapeTool(activeTool)) {
      _shapeDragStart = worldPos;
      return;
    }

    if (activeTool == CanvasTool.select) {
      final zoom = ref.read(viewportProvider).zoom;
      final selectedIds = ref.read(selectionProvider);
      final nodes = ref.read(documentNodesProvider);

      // Connector controls must win over node resize handles at shape borders.
      if (_startConnectorControlDrag(worldPos, zoom)) return;

      // 1. Check if clicking on a resize handle first
      final handleHit = CanvasHitTester.hitTestHandle(
        nodes,
        selectedIds,
        worldPos,
        zoom,
      );

      if (handleHit != null) {
        ref
            .read(documentNodesProvider.notifier)
            .beginTransaction(
              name: handleHit.$2 == ResizeHandle.rotation
                  ? 'Rotate selection'
                  : 'Resize selection',
            );
        _resizingNodeId = handleHit.$1;
        _activeResizeHandle = handleHit.$2;
        final target = nodes.firstWhere((n) => n.id == handleHit.$1);
        _initialNodeBounds = Rect.fromLTWH(
          target.x,
          target.y,
          target.width,
          target.height,
        );
        if (_activeResizeHandle == ResizeHandle.rotation) {
          final center = Offset(
            target.x + target.width / 2,
            target.y + target.height / 2,
          );
          _rotationStartPointerAngle = math.atan2(
            worldPos.dy - center.dy,
            worldPos.dx - center.dx,
          );
          _rotationStartNodeRotation = target.rotation;
        } else {
          _rotationStartPointerAngle = null;
          _rotationStartNodeRotation = null;
        }
        if (_activeResizeHandle == ResizeHandle.drawingPoint &&
            target.payload is DrawingPayload) {
          final dp = target.payload as DrawingPayload;
          final hitRadius = 10.0 / zoom;
          int? closestIdx;
          double closestDist = double.infinity;
          for (final idx in dp.controlPointIndices) {
            if (idx >= 0 && idx < dp.points.length) {
              final pt = Offset(
                target.x + dp.points[idx].dx,
                target.y + dp.points[idx].dy,
              );
              final d = (worldPos - pt).distance;
              if (d <= hitRadius && d < closestDist) {
                closestDist = d;
                closestIdx = idx;
              }
            }
          }
          _activeDrawingPointIndex = closestIdx;
        } else {
          _activeDrawingPointIndex = null;
        }

        if ((_activeResizeHandle == ResizeHandle.vectorAnchor ||
                _activeResizeHandle == ResizeHandle.vectorHandleIn ||
                _activeResizeHandle == ResizeHandle.vectorHandleOut) &&
            target.payload is VectorPathPayload) {
          final vp = target.payload as VectorPathPayload;
          final hitRadius = 10.0 / zoom;
          int? closestIdx;
          double closestDist = double.infinity;
          for (int i = 0; i < vp.points.length; i++) {
            final bp = vp.points[i];
            final anchor = Offset(
              target.x + bp.point.dx,
              target.y + bp.point.dy,
            );
            final targetOffset =
                _activeResizeHandle == ResizeHandle.vectorHandleIn
                ? anchor + bp.handleIn
                : (_activeResizeHandle == ResizeHandle.vectorHandleOut
                      ? anchor + bp.handleOut
                      : anchor);
            final d = (worldPos - targetOffset).distance;
            if (d <= hitRadius && d < closestDist) {
              closestDist = d;
              closestIdx = i;
            }
          }
          _activeVectorPointIndex = closestIdx;
        } else {
          _activeVectorPointIndex = null;
        }
        if ((target.type == NodeType.line || target.type == NodeType.arrow) &&
            target.payload is ShapePayload) {
          final p = target.payload as ShapePayload;
          if (_activeResizeHandle == ResizeHandle.startPoint) {
            _fixedLineAnchor = Offset(
              target.x + p.endXRatio * target.width,
              target.y + p.endYRatio * target.height,
            );
          } else if (_activeResizeHandle == ResizeHandle.endPoint) {
            _fixedLineAnchor = Offset(
              target.x + p.startXRatio * target.width,
              target.y + p.startYRatio * target.height,
            );
          } else {
            _fixedLineAnchor = null;
          }
        } else {
          _fixedLineAnchor = null;
        }
        _isDraggingNodes = false;
        return;
      }

      // 2. Hit-test nodes. Reuse the pointer-down result so select-through
      // cycling does not change the drag target mid-gesture.
      final hit = _pointerDownSelectionNodeId == null
          ? CanvasHitTester.hitTest(nodes, worldPos)
          : nodes
                .where((node) => node.id == _pointerDownSelectionNodeId)
                .firstOrNull;

      if (hit != null) {
        if (!selectedIds.contains(hit.id)) {
          ref.read(selectionProvider.notifier).select(hit.id);
        }
        _isDraggingNodes = true;
        ref
            .read(documentNodesProvider.notifier)
            .beginTransaction(name: 'Move selection');
        _dragOriginBounds = hit.bounds;
        _dragAccum = Offset.zero;
        return;
      }

      // 3. Hit-test connector edges
      final edges = ref.read(documentEdgesProvider);
      final nodeMap = {for (final n in nodes) n.id: n};
      final edgeHit = CanvasHitTester.hitTestEdge(
        edges,
        nodeMap,
        worldPos,
        tolerance: 10.0 / zoom,
      );

      if (edgeHit != null) {
        ref.read(selectionProvider.notifier).select(edgeHit.id);
        _isDraggingNodes = false;
      } else {
        ref.read(selectionProvider.notifier).clear();
        _isDraggingNodes = false;
      }
    }
  }

  void _handlePanUpdate(DragUpdateDetails details, CanvasTool activeTool) {
    final viewport = ref.read(viewportProvider);
    final worldPos = ref
        .read(viewportProvider.notifier)
        .toWorld(details.localPosition);
    _collaborationSession?.updatePresence(
      worldPosition: worldPos,
      selectedNodeIds: ref.read(selectionProvider),
      viewportX: viewport.x,
      viewportY: viewport.y,
      viewportZoom: viewport.zoom,
      activeNodeId: _editingNodeId,
      editing: _editingNodeId != null,
    );

    if (activeTool == CanvasTool.sketchCard && _drawingOnSketchCardId != null) {
      final nodes = ref.read(documentNodesProvider);
      final match = nodes.where((n) => n.id == _drawingOnSketchCardId).toList();
      if (match.isNotEmpty && match.first.payload is SketchCardPayload) {
        final card = match.first;
        final localPos = Offset(worldPos.dx - card.x, worldPos.dy - card.y);
        final oldPayload = card.payload as SketchCardPayload;
        final currentStrokes = oldPayload.strokes
            .map((s) => List<Offset>.from(s))
            .toList();
        if (currentStrokes.isNotEmpty) {
          currentStrokes.last.add(localPos);
          ref
              .read(documentNodesProvider.notifier)
              .updateNode(
                card.copyWith(
                  payload: oldPayload.copyWith(strokes: currentStrokes),
                ),
              );
        }
      }
      return;
    }

    if (activeTool == CanvasTool.brush) {
      final brushConfig = ref.read(activeBrushConfigProvider);
      if (brushConfig.brushType == BrushType.eraser) {
        _applyEraserAt(worldPos, brushConfig);
      }
      setState(() {
        _activeBrushStroke.add(worldPos);
        _mouseWorldPos = worldPos;
      });
      return;
    }

    if (activeTool == CanvasTool.pen &&
        _isDraggingPenHandle &&
        _activePenPoints.isNotEmpty) {
      final lastIdx = _activePenPoints.length - 1;
      final lastPt = _activePenPoints[lastIdx];
      final tangent = worldPos - lastPt.point;
      setState(() {
        _activePenPoints[lastIdx] = BezierPoint(
          point: lastPt.point,
          handleIn: -tangent,
          handleOut: tangent,
        );
        _mouseWorldPos = worldPos;
      });
      return;
    }

    if (_isShapeTool(activeTool) && _shapeDragStart != null) {
      setState(() {
        _mouseWorldPos = worldPos;
        if (activeTool == CanvasTool.line || activeTool == CanvasTool.arrow) {
          _creationPreviewLine = (_shapeDragStart!, worldPos);
          _creationPreviewRect = null;
        } else {
          final rect = Rect.fromPoints(_shapeDragStart!, worldPos);
          _creationPreviewRect = rect;
          _creationPreviewLine = null;
        }
      });
      return;
    }

    if (activeTool == CanvasTool.hand) {
      ref
          .read(viewportProvider.notifier)
          .pan(details.delta.dx, details.delta.dy);
      return;
    }

    if (activeTool == CanvasTool.select) {
      if (_connectorEditEdgeId != null) {
        _updateConnectorPreview(worldPos);
        return;
      }

      if (_resizingNodeId != null &&
          _activeResizeHandle != null &&
          _initialNodeBounds != null &&
          _dragStart != null) {
        final zoom = ref.read(viewportProvider).zoom;
        final deltaX = details.delta.dx / zoom;
        final deltaY = details.delta.dy / zoom;

        final nodes = ref.read(documentNodesProvider);
        final match = nodes.where((n) => n.id == _resizingNodeId).toList();
        if (match.isNotEmpty) {
          final node = match.first;

          if (_activeResizeHandle == ResizeHandle.rotation &&
              _rotationStartPointerAngle != null &&
              _rotationStartNodeRotation != null) {
            final center = Offset(
              node.x + node.width / 2,
              node.y + node.height / 2,
            );
            final pointerAngle = math.atan2(
              worldPos.dy - center.dy,
              worldPos.dx - center.dx,
            );
            var delta = pointerAngle - _rotationStartPointerAngle!;
            while (delta > math.pi) {
              delta -= 2 * math.pi;
            }
            while (delta < -math.pi) {
              delta += 2 * math.pi;
            }
            final keys = HardwareKeyboard.instance.logicalKeysPressed;
            if (keys.contains(LogicalKeyboardKey.shiftLeft) ||
                keys.contains(LogicalKeyboardKey.shiftRight)) {
              const snap = math.pi / 12;
              delta = (delta / snap).round() * snap;
            }
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(rotation: _rotationStartNodeRotation! + delta),
                );
            return;
          }

          if (_activeResizeHandle == ResizeHandle.cornerRadius &&
              node.payload is ShapePayload) {
            final shapePayload = node.payload as ShapePayload;
            final diagramDefinition = DiagramShapeCatalog.resolve(
              shapePayload.diagramShapeId ?? 'rectangle',
            );
            if (diagramDefinition.supportsCornerRadius) {
              final newRadius = diagramDefinition.cornerRadiusFromHandle(
                Size(node.width, node.height),
                Offset(worldPos.dx - node.x, worldPos.dy - node.y),
              );
              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: shapePayload.copyWith(
                        cornerRadius: newRadius,
                        topLeftRadius: newRadius,
                        topRightRadius: newRadius,
                        bottomRightRadius: newRadius,
                        bottomLeftRadius: newRadius,
                      ),
                    ),
                  );
              return;
            }
          }

          if ((_activeResizeHandle == ResizeHandle.arcStart ||
                  _activeResizeHandle == ResizeHandle.arcSweep ||
                  _activeResizeHandle == ResizeHandle.innerRadius) &&
              node.type == NodeType.ellipse &&
              node.payload is ShapePayload) {
            final payload = node.payload as ShapePayload;
            final center = Offset(
              node.x + node.width / 2,
              node.y + node.height / 2,
            );
            final delta = worldPos - center;
            final angle =
                (math.atan2(delta.dy / node.height, delta.dx / node.width) *
                        180 /
                        math.pi +
                    90 +
                    360) %
                360;
            ShapePayload updatedPayload;
            if (_activeResizeHandle == ResizeHandle.arcStart) {
              final endAngle = (payload.startAngle + payload.sweepAngle) % 360;
              updatedPayload = payload.copyWith(
                startAngle: angle,
                sweepAngle: ((endAngle - angle + 360) % 360).clamp(0.1, 360.0),
              );
            } else if (_activeResizeHandle == ResizeHandle.arcSweep) {
              updatedPayload = payload.copyWith(
                sweepAngle: ((angle - payload.startAngle + 360) % 360).clamp(
                  0.1,
                  360.0,
                ),
              );
            } else {
              final normalized = math.sqrt(
                math.pow(delta.dx / (node.width / 2), 2) +
                    math.pow(delta.dy / (node.height / 2), 2),
              );
              updatedPayload = payload.copyWith(
                innerRadiusRatio: normalized.clamp(0.0, 0.99),
              );
            }
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(node.copyWith(payload: updatedPayload));
            return;
          }

          if (_activeResizeHandle == ResizeHandle.skewHandle &&
              node.type == NodeType.parallelogram &&
              node.payload is ShapePayload) {
            final payload = node.payload as ShapePayload;
            final localX = worldPos.dx - node.x;
            final clampedRatio = (localX / node.width).clamp(-0.45, 0.45);
            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(
                    payload: payload.copyWith(skewRatio: clampedRatio),
                  ),
                );
            return;
          }

          if (_activeResizeHandle == ResizeHandle.curveControl &&
              (node.type == NodeType.line || node.type == NodeType.arrow) &&
              node.payload is ShapePayload) {
            final payload = node.payload as ShapePayload;
            final pStart = Offset(
              node.x + payload.startXRatio * node.width,
              node.y + payload.startYRatio * node.height,
            );
            final pEnd = Offset(
              node.x + payload.endXRatio * node.width,
              node.y + payload.endYRatio * node.height,
            );

            final mid = Offset(
              (pStart.dx + pEnd.dx) / 2,
              (pStart.dy + pEnd.dy) / 2,
            );
            final lineVec = pEnd - pStart;
            final lineLen = lineVec.distance;

            if (lineLen > 1.0) {
              // Normal perpendicular vector (-dy, dx)
              final perpUnit = Offset(
                -lineVec.dy / lineLen,
                lineVec.dx / lineLen,
              );
              final dragVec = worldPos - mid;
              // Project drag vector onto perpendicular
              final projectedDist =
                  dragVec.dx * perpUnit.dx + dragVec.dy * perpUnit.dy;
              final newDepth = (projectedDist / lineLen).clamp(-1.5, 1.5);

              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      payload: payload.copyWith(curveDepth: newDepth),
                    ),
                  );
            }
            return;
          }

          if ((_activeResizeHandle == ResizeHandle.vectorAnchor ||
                  _activeResizeHandle == ResizeHandle.vectorHandleIn ||
                  _activeResizeHandle == ResizeHandle.vectorHandleOut) &&
              _activeVectorPointIndex != null &&
              node.type == NodeType.vectorPath &&
              node.payload is VectorPathPayload) {
            final vp = node.payload as VectorPathPayload;
            final idx = _activeVectorPointIndex!;
            if (idx >= 0 && idx < vp.points.length) {
              final oldPt = vp.points[idx];
              final localPos = Offset(
                worldPos.dx - node.x,
                worldPos.dy - node.y,
              );
              final updatedPoints = List<BezierPoint>.from(vp.points);

              if (_activeResizeHandle == ResizeHandle.vectorAnchor) {
                updatedPoints[idx] = oldPt.copyWith(point: localPos);
              } else if (_activeResizeHandle == ResizeHandle.vectorHandleIn) {
                final handleVec = localPos - oldPt.point;
                if (oldPt.type == PointType.mirrored) {
                  updatedPoints[idx] = oldPt.copyWith(
                    handleIn: handleVec,
                    handleOut: -handleVec,
                  );
                } else {
                  updatedPoints[idx] = oldPt.copyWith(handleIn: handleVec);
                }
              } else if (_activeResizeHandle == ResizeHandle.vectorHandleOut) {
                final handleVec = localPos - oldPt.point;
                if (oldPt.type == PointType.mirrored) {
                  updatedPoints[idx] = oldPt.copyWith(
                    handleOut: handleVec,
                    handleIn: -handleVec,
                  );
                } else {
                  updatedPoints[idx] = oldPt.copyWith(handleOut: handleVec);
                }
              }

              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(payload: vp.copyWith(points: updatedPoints)),
                  );
            }
            return;
          }

          if (_activeResizeHandle == ResizeHandle.drawingPoint &&
              _activeDrawingPointIndex != null &&
              node.type == NodeType.drawing &&
              node.payload is DrawingPayload) {
            final dp = node.payload as DrawingPayload;
            final ptIdx = _activeDrawingPointIndex!;
            if (ptIdx >= 0 && ptIdx < dp.points.length) {
              final worldPts = dp.points
                  .map((p) => Offset(node.x + p.dx, node.y + p.dy))
                  .toList();
              worldPts[ptIdx] = worldPos;
              final xs = worldPts.map((p) => p.dx);
              final ys = worldPts.map((p) => p.dy);
              final minX = xs.reduce(math.min);
              final maxX = xs.reduce(math.max);
              final minY = ys.reduce(math.min);
              final maxY = ys.reduce(math.max);
              final normalizedPts = worldPts
                  .map((p) => Offset(p.dx - minX, p.dy - minY))
                  .toList();

              ref
                  .read(documentNodesProvider.notifier)
                  .updateNode(
                    node.copyWith(
                      x: minX,
                      y: minY,
                      width: math.max(4.0, maxX - minX),
                      height: math.max(4.0, maxY - minY),
                      payload: dp.copyWith(points: normalizedPts),
                    ),
                  );
            }
            return;
          }

          if (_activeResizeHandle == ResizeHandle.startPoint ||
              _activeResizeHandle == ResizeHandle.endPoint) {
            final isStart = _activeResizeHandle == ResizeHandle.startPoint;

            if (node.type == NodeType.drawing &&
                node.payload is DrawingPayload) {
              final dp = node.payload as DrawingPayload;
              if (dp.points.isNotEmpty) {
                final worldPts = dp.points
                    .map((p) => Offset(node.x + p.dx, node.y + p.dy))
                    .toList();
                if (isStart) {
                  worldPts[0] = worldPos;
                } else {
                  worldPts[worldPts.length - 1] = worldPos;
                }
                final xs = worldPts.map((p) => p.dx);
                final ys = worldPts.map((p) => p.dy);
                final minX = xs.reduce(math.min);
                final maxX = xs.reduce(math.max);
                final minY = ys.reduce(math.min);
                final maxY = ys.reduce(math.max);
                final normalizedPts = worldPts
                    .map((p) => Offset(p.dx - minX, p.dy - minY))
                    .toList();

                ref
                    .read(documentNodesProvider.notifier)
                    .updateNode(
                      node.copyWith(
                        x: minX,
                        y: minY,
                        width: math.max(4.0, maxX - minX),
                        height: math.max(4.0, maxY - minY),
                        payload: dp.copyWith(points: normalizedPts),
                      ),
                    );
              }
              return;
            }

            final payload = node.payload is ShapePayload
                ? node.payload as ShapePayload
                : ShapePayload();

            // True static anchor captured at drag start
            final anchor =
                _fixedLineAnchor ??
                (isStart
                    ? Offset(
                        node.x + payload.endXRatio * node.width,
                        node.y + payload.endYRatio * node.height,
                      )
                    : Offset(
                        node.x + payload.startXRatio * node.width,
                        node.y + payload.startYRatio * node.height,
                      ));

            final newStart = isStart ? worldPos : anchor;
            final newEnd = isStart ? anchor : worldPos;

            final minX = newStart.dx < newEnd.dx ? newStart.dx : newEnd.dx;
            final minY = newStart.dy < newEnd.dy ? newStart.dy : newEnd.dy;
            final rawW = (newEnd.dx - newStart.dx).abs();
            final rawH = (newEnd.dy - newStart.dy).abs();
            final width = rawW.clamp(0.01, double.infinity);
            final height = rawH.clamp(0.01, double.infinity);

            final double sxRatio = (rawW < 0.001)
                ? 0.0
                : (newStart.dx <= newEnd.dx ? 0.0 : 1.0);
            final double syRatio = (rawH < 0.001)
                ? 0.0
                : (newStart.dy <= newEnd.dy ? 0.0 : 1.0);
            final double exRatio = (rawW < 0.001)
                ? 1.0
                : (newStart.dx <= newEnd.dx ? 1.0 : 0.0);
            final double eyRatio = (rawH < 0.001)
                ? 1.0
                : (newStart.dy <= newEnd.dy ? 1.0 : 0.0);

            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(
                    x: minX,
                    y: minY,
                    width: width,
                    height: height,
                    payload: payload.copyWith(
                      startXRatio: sxRatio,
                      startYRatio: syRatio,
                      endXRatio: exRatio,
                      endYRatio: eyRatio,
                    ),
                  ),
                );
            return;
          }

          double newX = node.x;
          double newY = node.y;
          double newW = node.width;
          double newH = node.height;

          switch (_activeResizeHandle!) {
            case ResizeHandle.topLeft:
              newX += deltaX;
              newY += deltaY;
              newW -= deltaX;
              newH -= deltaY;
              break;
            case ResizeHandle.topCenter:
              newY += deltaY;
              newH -= deltaY;
              break;
            case ResizeHandle.topRight:
              newY += deltaY;
              newW += deltaX;
              newH -= deltaY;
              break;
            case ResizeHandle.centerRight:
              newW += deltaX;
              break;
            case ResizeHandle.bottomRight:
              newW += deltaX;
              newH += deltaY;
              break;
            case ResizeHandle.bottomCenter:
              newH += deltaY;
              break;
            case ResizeHandle.bottomLeft:
              newX += deltaX;
              newW -= deltaX;
              newH += deltaY;
              break;
            case ResizeHandle.centerLeft:
              newX += deltaX;
              newW -= deltaX;
              break;
            case ResizeHandle.rotation:
              break;
            case ResizeHandle.startPoint:
            case ResizeHandle.endPoint:
            case ResizeHandle.cornerRadius:
            case ResizeHandle.arcStart:
            case ResizeHandle.arcSweep:
            case ResizeHandle.innerRadius:
            case ResizeHandle.skewHandle:
            case ResizeHandle.curveControl:
            case ResizeHandle.drawingPoint:
            case ResizeHandle.vectorAnchor:
            case ResizeHandle.vectorHandleIn:
            case ResizeHandle.vectorHandleOut:
              break;
          }

          if (newW >= 10.0 && newH >= 10.0) {
            // Also scale internal vector path points / drawing points proportionally if applicable
            NodePayload updatedPayload = node.payload;
            if (node.type == NodeType.drawing &&
                node.payload is DrawingPayload &&
                node.width > 0 &&
                node.height > 0) {
              final dp = node.payload as DrawingPayload;
              final scaleX = newW / node.width;
              final scaleY = newH / node.height;
              final scaledPts = dp.points
                  .map((p) => Offset(p.dx * scaleX, p.dy * scaleY))
                  .toList();
              updatedPayload = dp.copyWith(points: scaledPts);
            } else if (node.type == NodeType.vectorPath &&
                node.payload is VectorPathPayload &&
                node.width > 0 &&
                node.height > 0) {
              final vp = node.payload as VectorPathPayload;
              final scaleX = newW / node.width;
              final scaleY = newH / node.height;
              final scaledPts = vp.points
                  .map(
                    (bp) => BezierPoint(
                      point: Offset(bp.point.dx * scaleX, bp.point.dy * scaleY),
                      handleIn: Offset(
                        bp.handleIn.dx * scaleX,
                        bp.handleIn.dy * scaleY,
                      ),
                      handleOut: Offset(
                        bp.handleOut.dx * scaleX,
                        bp.handleOut.dy * scaleY,
                      ),
                    ),
                  )
                  .toList();
              updatedPayload = vp.copyWith(points: scaledPts);
            }

            ref
                .read(documentNodesProvider.notifier)
                .updateNode(
                  node.copyWith(
                    x: newX,
                    y: newY,
                    width: newW,
                    height: newH,
                    payload: updatedPayload,
                  ),
                );
          }
        }
        return;
      }

      if (_isDraggingNodes) {
        final zoom = ref.read(viewportProvider).zoom;
        final selectedIds = ref.read(selectionProvider).toList();
        final nodes = ref.read(documentNodesProvider);

        if (selectedIds.length == 1) {
          final singleNode = nodes.firstWhere((n) => n.id == selectedIds.first);
          final otherNodes = nodes.where((n) => n.id != singleNode.id).toList();
          final origin = _dragOriginBounds;
          final rawDx = details.delta.dx / zoom;
          final rawDy = details.delta.dy / zoom;
          _dragAccum += Offset(rawDx, rawDy);

          if (origin == null) {
            ref
                .read(documentNodesProvider.notifier)
                .moveNodes(selectedIds, rawDx, rawDy);
            return;
          }

          final precision = ref.read(canvasPrecisionProvider(widget.projectId));
          final rawRect = origin.shift(_dragAccum);
          final snappedPoint = CanvasPrecisionMath.snapPoint(
            rawRect.topLeft,
            state: precision,
          );
          final desiredRect = rawRect.shift(snappedPoint - rawRect.topLeft);
          final objectSnapping =
              precision.snapMode == CanvasSnapMode.objects ||
              precision.snapMode == CanvasSnapMode.all;
          final edgeSnap = objectSnapping && precision.smartGuidesEnabled
              ? SnapEngine.calculateSnap(
                  targetRect: desiredRect,
                  otherNodes: otherNodes,
                )
              : const SnapResult(dx: 0, dy: 0);
          final spacingSnap = objectSnapping && precision.smartGuidesEnabled
              ? SpacingEngine.calculateSpacingSnap(
                  targetRect: desiredRect,
                  otherNodes: otherNodes,
                )
              : (
                  dx: 0.0,
                  dy: 0.0,
                  snappedX: false,
                  snappedY: false,
                  measurements: <SpacingMeasurement>[],
                );

          final snapX = spacingSnap.snappedX ? spacingSnap.dx : edgeSnap.dx;
          final snapY = spacingSnap.snappedY ? spacingSnap.dy : edgeSnap.dy;
          _activeSnapGuides = spacingSnap.snappedX || spacingSnap.snappedY
              ? const []
              : edgeSnap.guides;

          final snappedRect = desiredRect.shift(Offset(snapX, snapY));
          _activeMeasurements =
              precision.measurementsVisible &&
                  (spacingSnap.snappedX || spacingSnap.snappedY)
              ? spacingSnap.measurements
              : precision.measurementsVisible
              ? SpacingEngine.calculateMeasurements(
                  targetRect: snappedRect,
                  otherNodes: otherNodes,
                  altHeld: _altPressed,
                )
              : const <SpacingMeasurement>[];
          final nextX = snappedRect.left - singleNode.x;
          final nextY = snappedRect.top - singleNode.y;
          if (nextX != 0 || nextY != 0) {
            ref
                .read(documentNodesProvider.notifier)
                .moveNodes(selectedIds, nextX, nextY);
          }
        } else {
          _activeSnapGuides = [];
          _activeMeasurements = [];
          ref
              .read(documentNodesProvider.notifier)
              .moveNodes(
                selectedIds,
                details.delta.dx / zoom,
                details.delta.dy / zoom,
              );
        }
      } else if (_dragStart != null) {
        final worldStart = ref
            .read(viewportProvider.notifier)
            .toWorld(_dragStart!);
        final worldCurrent = ref
            .read(viewportProvider.notifier)
            .toWorld(details.localPosition);
        setState(() {
          _selectionMarquee = Rect.fromPoints(worldStart, worldCurrent);
        });
      }
    }
  }

  void _handlePanEnd(DragEndDetails details, CanvasTool activeTool) {
    ref.read(documentNodesProvider.notifier).commitTransaction();
    if (_connectorEditEdgeId != null) {
      _commitConnectorEdit();
      return;
    }

    if (activeTool == CanvasTool.sketchCard) {
      _drawingOnSketchCardId = null;
      return;
    }

    if (activeTool == CanvasTool.brush) {
      final brushConfig = ref.read(activeBrushConfigProvider);
      if (brushConfig.brushType == BrushType.eraser) {
        setState(() {
          _activeBrushStroke = [];
        });
        return;
      }

      if (_activeBrushStroke.length > 1) {
        final xs = _activeBrushStroke.map((p) => p.dx);
        final ys = _activeBrushStroke.map((p) => p.dy);
        final minX = xs.reduce((a, b) => a < b ? a : b);
        final maxX = xs.reduce((a, b) => a > b ? a : b);
        final minY = ys.reduce((a, b) => a < b ? a : b);
        final maxY = ys.reduce((a, b) => a > b ? a : b);

        final localPoints = _activeBrushStroke
            .map((p) => Offset(p.dx - minX, p.dy - minY))
            .toList();

        final strokeNode = CanvasNode(
          id: const Uuid().v4(),
          type: NodeType.drawing,
          x: minX,
          y: minY,
          width: (maxX - minX).clamp(4.0, double.infinity),
          height: (maxY - minY).clamp(4.0, double.infinity),
          payload: DrawingPayload(
            points: localPoints,
            brushType: brushConfig.brushType,
            strokeColor: brushConfig.color,
            strokeWidth: brushConfig.strokeWidth,
            opacity: brushConfig.opacity,
            isSmoothed: brushConfig.smoothCurves,
          ),
        );

        ref.read(documentNodesProvider.notifier).addNode(strokeNode);
      }
      setState(() {
        _activeBrushStroke = [];
      });
      return;
    }

    if (activeTool == CanvasTool.pen) {
      _isDraggingPenHandle = false;
      return;
    }

    if (_isShapeTool(activeTool) && _shapeDragStart != null) {
      final previewRect = _creationPreviewRect;
      final previewLine = _creationPreviewLine;

      if (previewLine != null) {
        final (p1, p2) = previewLine;
        final minX = p1.dx < p2.dx ? p1.dx : p2.dx;
        final minY = p1.dy < p2.dy ? p1.dy : p2.dy;
        final rawW = (p2.dx - p1.dx).abs();
        final rawH = (p2.dy - p1.dy).abs();
        final width = rawW.clamp(20.0, double.infinity);
        final height = rawH.clamp(0.0, double.infinity);

        final double sxRatio = p1.dx <= p2.dx ? 0.0 : 1.0;
        final double syRatio = (rawH < 1.0)
            ? 0.0
            : (p1.dy <= p2.dy ? 0.0 : 1.0);
        final double exRatio = p1.dx <= p2.dx ? 1.0 : 0.0;
        final double eyRatio = (rawH < 1.0)
            ? 0.0
            : (p1.dy <= p2.dy ? 1.0 : 0.0);

        final isArrow = activeTool == CanvasTool.arrow;
        final id = const Uuid().v4();
        final node = CanvasNode(
          id: id,
          type: isArrow ? NodeType.arrow : NodeType.line,
          x: minX,
          y: minY,
          width: width,
          height: height,
          payload: ShapePayload(
            strokeWidth: 2.5,
            stroke: const Color(0xFFF97316),
            startXRatio: sxRatio,
            startYRatio: syRatio,
            endXRatio: exRatio,
            endYRatio: eyRatio,
            endMarker: isArrow ? LineMarker.arrow : LineMarker.none,
          ),
        );
        ref.read(documentNodesProvider.notifier).addNode(node);
        ref.read(selectionProvider.notifier).select(node.id);
      } else if (previewRect != null &&
          previewRect.width >= 4 &&
          previewRect.height >= 4) {
        _createNodeFromRect(activeTool, previewRect);
      } else {
        // Simple tap fallback
        _spawnNodeAt(activeTool, _shapeDragStart!);
      }

      setState(() {
        _shapeDragStart = null;
        _creationPreviewRect = null;
        _creationPreviewLine = null;
      });
      ref.read(activeToolProvider.notifier).setTool(CanvasTool.select);
      return;
    }

    if (_isDraggingNodes) {
      ref.read(documentNodesProvider.notifier).reparentNodes();
    }

    if (_selectionMarquee != null) {
      final hits = CanvasHitTester.hitTestMarquee(
        ref.read(documentNodesProvider),
        _selectionMarquee!,
      );
      ref
          .read(selectionProvider.notifier)
          .selectAll(hits.map((e) => e.id).toList());
    }

    setState(() {
      _selectionMarquee = null;
      _dragStart = null;
      _isDraggingNodes = false;
      _resizingNodeId = null;
      _activeResizeHandle = null;
      _rotationStartPointerAngle = null;
      _rotationStartNodeRotation = null;
      _initialNodeBounds = null;
      _fixedLineAnchor = null;
      _activeSnapGuides = [];
      _activeMeasurements = [];
      _dragOriginBounds = null;
      _dragAccum = Offset.zero;
      _pointerDownSelectionNodeId = null;
    });
  }

  void _createNodeFromRect(CanvasTool tool, Rect rect) {
    final id = const Uuid().v4();
    CanvasNode? newNode;

    final minX = rect.left;
    final minY = rect.top;
    final width = rect.width.clamp(10.0, double.infinity);
    final height = rect.height.clamp(10.0, double.infinity);

    switch (tool) {
      case CanvasTool.diagramShape:
        final shape = ref.read(activeDiagramShapeProvider);
        final normalizedRect = DiagramShapeCatalog.normalizeCreationRect(
          shape.id,
          Rect.fromLTWH(minX, minY, width, height),
        );
        final nodeType = switch (shape.nodeKind) {
          DiagramShapeNodeKind.ellipse => NodeType.ellipse,
          DiagramShapeNodeKind.diamond => NodeType.diamond,
          DiagramShapeNodeKind.cylinder => NodeType.cylinder,
          DiagramShapeNodeKind.parallelogram => NodeType.parallelogram,
          DiagramShapeNodeKind.rectangle => NodeType.rectangle,
        };
        newNode = CanvasNode(
          id: id,
          type: nodeType,
          x: normalizedRect.left,
          y: normalizedRect.top,
          width: normalizedRect.width,
          height: normalizedRect.height,
          payload: ShapePayload(
            diagramShapeId: shape.id,
            cornerRadius: shape.defaultCornerRadius,
            label: '',
            fill: const Color(0xFF334155),
            stroke: const Color(0xFF94A3B8),
          ),
        );
        break;
      case CanvasTool.chart:
        final chartType = ref.read(activeChartTypeProvider);
        newNode = CanvasNode(
          id: id,
          type: NodeType.chart,
          x: minX,
          y: minY,
          width: width,
          height: height,
          payload: ChartPayload(
            title: '${chartType.name.toUpperCase()} CHART',
            chartType: chartType,
          ),
        );
        break;
      case CanvasTool.rectangle:
        newNode = CanvasNode(
          id: id,
          type: NodeType.rectangle,
          x: minX,
          y: minY,
          width: width,
          height: height,
          payload: ShapePayload(),
        );
        break;
      case CanvasTool.ellipse:
        newNode = CanvasNode(
          id: id,
          type: NodeType.ellipse,
          x: minX,
          y: minY,
          width: width,
          height: height,
          payload: ShapePayload(
            fill: const Color(0xFF10B981),
            stroke: const Color(0xFF34D399),
          ),
        );
        break;
      case CanvasTool.diamond:
        newNode = CanvasNode(
          id: id,
          type: NodeType.diamond,
          x: minX,
          y: minY,
          width: width,
          height: height,
          payload: ShapePayload(
            fill: const Color(0xFFD97706),
            stroke: const Color(0xFFFBBF24),
          ),
        );
        break;
      case CanvasTool.cylinder:
        newNode = CanvasNode(
          id: id,
          type: NodeType.cylinder,
          x: minX,
          y: minY,
          width: width,
          height: height,
          payload: ShapePayload(
            fill: const Color(0xFF2563EB),
            stroke: const Color(0xFF60A5FA),
          ),
        );
        break;
      case CanvasTool.parallelogram:
        newNode = CanvasNode(
          id: id,
          type: NodeType.parallelogram,
          x: minX,
          y: minY,
          width: width,
          height: height,
          payload: ShapePayload(
            fill: const Color(0xFF10B981),
            stroke: const Color(0xFF34D399),
          ),
        );
        break;
      case CanvasTool.stickyNote:
        newNode = CanvasNode(
          id: id,
          type: NodeType.stickyNote,
          x: minX,
          y: minY,
          width: width,
          height: height,
          payload: StickyNotePayload(),
        );
        break;
      case CanvasTool.text:
        newNode = CanvasNode(
          id: id,
          type: NodeType.text,
          x: minX,
          y: minY,
          width: width,
          height: height,
          payload: TextPayload(),
        );
        break;
      case CanvasTool.frame:
        newNode = CanvasNode(
          id: id,
          type: NodeType.frame,
          x: minX,
          y: minY,
          width: width,
          height: height,
          payload: FramePayload(),
        );
        break;
      case CanvasTool.component:
        newNode = CanvasNode(
          id: id,
          type: NodeType.component,
          x: minX,
          y: minY,
          width: width,
          height: height,
          payload: ComponentPayload(
            masterComponentId: id,
            componentName: 'Component',
            isMaster: true,
          ),
        );
        break;
      default:
        break;
    }

    if (newNode != null) {
      ref.read(documentNodesProvider.notifier).addNode(newNode);
      ref.read(selectionProvider.notifier).select(newNode.id);
      if (tool == CanvasTool.text || tool == CanvasTool.diagramShape) {
        _startInlineEdit(newNode, frameLabel: false);
      }
    }
  }

  void _insertFlowchartTemplate() {
    final (tplNodes, tplEdges) = DiagramTemplates.createFlowchart();
    for (final node in tplNodes) {
      ref.read(documentNodesProvider.notifier).addNode(node);
    }
    for (final edge in tplEdges) {
      ref.read(documentEdgesProvider.notifier).addEdge(edge);
    }
    showUiToast(context, 'Flowchart template inserted into canvas.');
  }

  Future<ProjectTemplateCatalog> _loadProjectTemplateCatalog() async {
    final storage = ref.read(localStorageServiceProvider);
    ProjectTemplateCatalog catalog;
    try {
      catalog = await storage.loadProjectTemplates(widget.projectId);
    } catch (_) {
      catalog = ProjectTemplateCatalog.withBuiltIns();
    }
    final sync = ref.read(supabaseSyncServiceProvider);
    if (!sync.isConfigured || !sync.isAuthenticated) return catalog;
    try {
      final result = await sync.syncProjectTemplates(
        workspaceId: widget.projectId,
        local: catalog,
      );
      catalog = result.catalog;
      if (result.failedUploads.isNotEmpty) {
        debugPrint(
          '[CanvasEditorSurface] ${result.failedUploads.length} local template uploads are pending.',
        );
      }
      await storage.saveProjectTemplates(widget.projectId, catalog);
    } catch (error) {
      debugPrint('[CanvasEditorSurface] Remote templates unavailable: $error');
    }
    return catalog;
  }

  Future<void> _saveSelectionAsTemplate() async {
    if (_collaborationReadOnly) return;
    final selectedIds = ref.read(selectionProvider);
    final allNodes = ref.read(documentNodesProvider);
    final selectedNodes = allNodes
        .where((node) => selectedIds.contains(node.id))
        .toList(growable: false);
    if (selectedNodes.isEmpty) {
      showUiToast(context, 'Select at least one canvas node first.');
      return;
    }
    final request = await showUiDialog<ProjectTemplateSaveRequest>(
      context: context,
      builder: (_) => const ProjectTemplateSaveDialog(),
    );
    if (!mounted || request == null) return;
    final selectedSet = selectedNodes.map((node) => node.id).toSet();
    final selectedEdges = ref
        .read(documentEdgesProvider)
        .where(
          (edge) =>
              (edge.sourceNodeId == null ||
                  selectedSet.contains(edge.sourceNodeId)) &&
              (edge.targetNodeId == null ||
                  selectedSet.contains(edge.targetNodeId)),
        )
        .toList(growable: false);
    final now = DateTime.now().toUtc();
    final template = ProjectTemplate(
      id: '${request.scope.name}:${const Uuid().v4()}',
      name: request.name,
      description: request.description,
      scope: request.scope,
      tags: request.tags,
      selectionNodes: selectedNodes,
      selectionEdges: selectedEdges,
      createdAt: now,
      updatedAt: now,
    );
    final storage = ref.read(localStorageServiceProvider);
    var catalog = await _loadProjectTemplateCatalog();
    catalog = catalog.upsert(template);
    await storage.saveProjectTemplates(widget.projectId, catalog);
    final sync = ref.read(supabaseSyncServiceProvider);
    if (sync.isConfigured && sync.isAuthenticated) {
      try {
        final syncedTemplate = await sync.upsertProjectTemplate(
          workspaceId: widget.projectId,
          template: template,
        );
        catalog = catalog.upsert(syncedTemplate);
        await storage.saveProjectTemplates(widget.projectId, catalog);
      } catch (error) {
        debugPrint('[CanvasEditorSurface] Template sync failed: $error');
        if (!mounted) return;
        showUiToast(
          context,
          'Template saved locally; team sync failed.',
          variant: UiToastVariant.warning,
        );
        return;
      }
    }
    if (!mounted) return;
    showUiToast(context, 'Template saved: ${request.name}');
  }

  Future<void> _insertSavedTemplateAt(Offset worldPosition) async {
    final catalog = await _loadProjectTemplateCatalog();
    if (!mounted) return;
    final template = await showUiDialog<ProjectTemplate>(
      context: context,
      builder: (_) => SavedProjectTemplatePickerDialog(catalog: catalog),
    );
    if (!mounted || template == null) return;
    final instance = template.instantiate(
      existingNodeIds: ref.read(documentNodesProvider).map((node) => node.id),
      existingEdgeIds: ref.read(documentEdgesProvider).map((edge) => edge.id),
    );
    if (instance.nodes.isEmpty) {
      showUiToast(context, 'Template has no insertable canvas nodes.');
      return;
    }
    final bounds = instance.nodes
        .map((node) => node.bounds)
        .reduce((a, b) => a.expandToInclude(b));
    final offset = worldPosition - bounds.center;
    final nodes = [
      for (final node in instance.nodes)
        node.copyWith(x: node.x + offset.dx, y: node.y + offset.dy),
    ];
    final nodesNotifier = ref.read(documentNodesProvider.notifier);
    for (final node in nodes) {
      nodesNotifier.addNode(node);
    }
    final edgesNotifier = ref.read(documentEdgesProvider.notifier);
    for (final edge in instance.edges) {
      edgesNotifier.addEdge(edge);
    }
    ref
        .read(selectionProvider.notifier)
        .selectAll(nodes.map((node) => node.id).toList(growable: false));
    showUiToast(context, 'Template inserted: ${template.name}');
  }

  void _startPresentationMode() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) =>
            PresentationScreen(document: _currentCanvasDocument()),
      ),
    );
  }

  Future<void> _joinRemotePresenterAndStart() async {
    final connection = await showPresenterRemoteHostDialog(
      context: context,
      client: ref.read(supabaseClientProvider),
      syncService: ref.read(supabaseSyncServiceProvider),
    );
    if (!mounted || connection == null) return;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => PresentationScreen(
            document: _currentCanvasDocument(),
            remoteSession: connection.session,
            remoteCommands: connection.transport.commands,
          ),
        ),
      );
    } finally {
      await connection.transport.dispose();
    }
  }

  Future<void> _openPresenterRemoteController() =>
      showPresenterRemoteControllerDialog(
        context: context,
        projectId: widget.projectId,
        client: ref.read(supabaseClientProvider),
        syncService: ref.read(supabaseSyncServiceProvider),
      );
}

class _CanvasNodeLayerPainter extends CustomPainter {
  final CanvasNode node;
  final CanvasNode? clipParent;
  final CanvasRenderTokens renderTokens;
  final DesignTokenSet designTokens;
  final double zoom;
  final CanvasImageCache imageCache;

  const _CanvasNodeLayerPainter({
    required this.node,
    required this.clipParent,
    required this.renderTokens,
    required this.designTokens,
    required this.zoom,
    required this.imageCache,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(zoom, zoom);

    if (clipParent != null) {
      final parent = clipParent!;
      final clipRect = Rect.fromLTWH(
        parent.x - node.x,
        parent.y - node.y,
        parent.width,
        parent.height,
      );
      final framePayload = parent.payload as FramePayload;
      CanvasPainter.clipToFrame(
        canvas,
        frameRect: clipRect,
        rotation: parent.rotation,
        cornerRadius: framePayload.cornerRadius,
      );
    }

    NodePainter.paint(
      canvas,
      node.copyWith(x: 0.0, y: 0.0),
      renderTokens: renderTokens,
      designTokens: designTokens,
      imageCache: imageCache,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CanvasNodeLayerPainter oldDelegate) {
    return oldDelegate.node != node ||
        oldDelegate.clipParent != clipParent ||
        oldDelegate.renderTokens != renderTokens ||
        oldDelegate.designTokens != designTokens ||
        oldDelegate.zoom != zoom ||
        !identical(oldDelegate.imageCache, imageCache);
  }
}
