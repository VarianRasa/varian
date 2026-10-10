import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/data/local/durable/durable_project_store.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/viewport.dart' as canvas_model;
import 'package:varian/features/canvas/presentation/painters/canvas_painter.dart';
import 'package:varian/features/canvas/presentation/painters/grid_painter.dart';
import 'package:varian/features/canvas/domain/canvas_precision.dart';

class ProjectPreview extends StatefulWidget {
  final LocalProjectMetadata project;
  final Future<CanvasDocument?>? documentFuture;
  final DurableProjectStore? durableStore;

  const ProjectPreview({
    required this.project,
    this.documentFuture,
    this.durableStore,
    super.key,
  });

  @override
  State<ProjectPreview> createState() => _ProjectPreviewState();
}

class _ProjectPreviewState extends State<ProjectPreview> {
  late Future<CanvasDocument?> _documentFuture;

  @override
  void initState() {
    super.initState();
    _documentFuture = widget.documentFuture ?? _loadDocument();
  }

  @override
  void didUpdateWidget(covariant ProjectPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project.id != widget.project.id ||
        oldWidget.project.updatedAt != widget.project.updatedAt ||
        oldWidget.documentFuture != widget.documentFuture) {
      _documentFuture = widget.documentFuture ?? _loadDocument();
    }
  }

  Future<CanvasDocument?> _loadDocument() => _loadDurableDocument();

  Future<CanvasDocument?> _loadDurableDocument() async {
    final ownedStore = widget.durableStore == null;
    final store = widget.durableStore ?? DurableProjectStore();
    try {
      final durable = await store.loadCanvasDocument(widget.project.id);
      return durable ??
          await LocalStorageService().loadDocument(widget.project.id);
    } finally {
      if (ownedStore) await store.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<CanvasDocument?>(
            future: _documentFuture,
            builder: (context, snapshot) {
              final document = snapshot.data;
              final loading =
                  snapshot.connectionState == ConnectionState.waiting;
              final hasNodes =
                  document?.nodes.any((node) => node.visible) == true;
              return Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _ProjectPreviewPainter(
                      document: document,
                      tokens: tokens,
                    ),
                  ),
                  if (loading)
                    Center(
                      child: UiSurface(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        color: tokens.panel.withValues(alpha: .9),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox.square(
                              dimension: 14,
                              child: const UiProgressIndicator(
                                semanticsLabel: 'Loading project preview',
                                size: 14,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              'LOADING PREVIEW',
                              style: Theme.of(context).textTheme.labelSmall!
                                  .copyWith(
                                    color: tokens.textMuted,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: .5,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!loading && (snapshot.hasError || !hasNodes))
                    _EmptyCanvasPreview(
                      error: snapshot.hasError,
                      tokens: tokens,
                    ),
                ],
              );
            },
          ),
          Positioned(
            top: AppSpacing.sm + AppSpacing.xxs,
            left: AppSpacing.sm + AppSpacing.xxs,
            child: UiBadge(
              _statusLabel(widget.project.status),
              variant: UiBadgeVariant.secondary,
            ),
          ),
          if (widget.project.isPinned)
            const Positioned(
              top: AppSpacing.sm + AppSpacing.xxs,
              right: AppSpacing.sm + AppSpacing.xxs,
              child: UiBadge('PINNED', variant: UiBadgeVariant.outline),
            ),
          if (widget.project.isCollaborationRoom)
            Positioned(
              left: AppSpacing.sm + AppSpacing.xxs,
              bottom: AppSpacing.sm + AppSpacing.xxs,
              child: UiBadge(
                'ROOM ${widget.project.collaborationRoomCode}',
                variant: UiBadgeVariant.outline,
              ),
            ),
        ],
      ),
    );
  }

  String _statusLabel(ProjectStatus status) => switch (status) {
    ProjectStatus.active => 'ACTIVE',
    ProjectStatus.archived => 'ARCHIVED',
    ProjectStatus.trashed => 'TRASH',
  };
}

class _EmptyCanvasPreview extends StatelessWidget {
  final bool error;
  final AppTokens tokens;

  const _EmptyCanvasPreview({required this.error, required this.tokens});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          error
              ? Icons.broken_image_outlined
              : Icons.dashboard_customize_outlined,
          size: 24,
          color: tokens.textMuted.withValues(alpha: .72),
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        Text(
          error ? 'PREVIEW UNAVAILABLE' : 'EMPTY CANVAS',
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: tokens.textMuted,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
      ],
    ),
  );
}

class _ProjectPreviewPainter extends CustomPainter {
  final CanvasDocument? document;
  final AppTokens tokens;

  const _ProjectPreviewPainter({required this.document, required this.tokens});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final palette = CanvasRenderTokens.fromAppTokens(tokens);
    GridPainter(
      panX: 0,
      panY: 0,
      zoom: 1,
      tokens: palette,
      gridPreset: CanvasGridPreset.dots,
      gridSpacing: 28,
    ).paint(canvas, size);

    final currentDocument = document;
    if (currentDocument == null) return;

    final nodes = currentDocument.nodes
        .where((node) => node.visible)
        .toList(growable: false);
    if (nodes.isEmpty) return;

    final sceneBounds = _sceneBounds(nodes);
    final width = math.max(sceneBounds.width, 1);
    final height = math.max(sceneBounds.height, 1);
    final scale = math
        .min(
          math.max(size.width - 18, 1) / width,
          math.max(size.height - 18, 1) / height,
        )
        .clamp(0.08, 1.0)
        .toDouble();
    final viewport = canvas_model.Viewport(
      x: size.width / 2 - sceneBounds.center.dx * scale,
      y: size.height / 2 - sceneBounds.center.dy * scale,
      zoom: scale,
    );

    CanvasPainter(
      nodes: nodes,
      edges: currentDocument.edges,
      viewport: viewport,
      selectedNodeIds: const {},
      renderTokens: palette,
      designTokens: currentDocument.tokens,
      renderForeground: false,
    ).paint(canvas, size);
  }

  Rect _sceneBounds(List<CanvasNode> nodes) {
    var left = nodes.first.x;
    var top = nodes.first.y;
    var right = nodes.first.x + nodes.first.width;
    var bottom = nodes.first.y + nodes.first.height;
    for (final node in nodes.skip(1)) {
      left = math.min(left, node.x);
      top = math.min(top, node.y);
      right = math.max(right, node.x + node.width);
      bottom = math.max(bottom, node.y + node.height);
    }
    return Rect.fromLTRB(left, top, right, bottom).inflate(24);
  }

  @override
  bool shouldRepaint(covariant _ProjectPreviewPainter oldDelegate) =>
      oldDelegate.document != document || oldDelegate.tokens != tokens;
}
