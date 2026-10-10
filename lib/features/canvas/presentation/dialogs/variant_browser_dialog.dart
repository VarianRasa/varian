import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../app/responsive.dart';
import '../../../../app/theme.dart';
import '../../../../app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/utils/canvas_image_cache.dart';

/// Browses the direct AI lineage of a canvas node and compares two image
/// variants without changing the canvas selection until the user confirms.
class VariantBrowserDialog extends StatefulWidget {
  final CanvasNode anchorNode;
  final List<CanvasNode> nodes;
  final ValueChanged<String> onSelectNode;
  final bool readOnly;
  final CanvasImageCache? imageCache;

  const VariantBrowserDialog({
    required this.anchorNode,
    required this.nodes,
    required this.onSelectNode,
    this.readOnly = false,
    this.imageCache,
    super.key,
  });

  @override
  State<VariantBrowserDialog> createState() => _VariantBrowserDialogState();
}

class _VariantBrowserDialogState extends State<VariantBrowserDialog> {
  late final List<CanvasNode> _members;
  late String _selectedId;
  final List<String> _compareIds = [];

  @override
  void initState() {
    super.initState();
    _members = _resolveMembers(widget.anchorNode, widget.nodes);
    _selectedId = _members.any((node) => node.id == widget.anchorNode.id)
        ? widget.anchorNode.id
        : (_members.isEmpty ? widget.anchorNode.id : _members.first.id);
  }

  static List<CanvasNode> _resolveMembers(
    CanvasNode anchor,
    List<CanvasNode> nodes,
  ) {
    final byId = {for (final node in nodes) node.id: node};
    final source = anchor.variantOfNodeId == null
        ? anchor
        : byId[anchor.variantOfNodeId];
    final root = source ?? anchor;
    final members = <CanvasNode>[];
    final seen = <String>{};

    void add(CanvasNode node) {
      if (seen.add(node.id)) members.add(node);
    }

    if (source != null) add(source);
    add(anchor);
    for (final node in nodes) {
      if (node.variantOfNodeId == root.id) add(node);
    }
    return members;
  }

  void _toggleCompare(CanvasNode node) {
    if (node.type != NodeType.image) return;
    setState(() {
      if (_compareIds.contains(node.id)) {
        _compareIds.remove(node.id);
      } else if (_compareIds.length < 2) {
        _compareIds.add(node.id);
      }
    });
  }

  CanvasNode? _nodeById(String id) =>
      _members.where((node) => node.id == id).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final imageCount = _members
        .where((node) => node.type == NodeType.image)
        .length;
    final maxHeight = AppResponsive.dialogHeight(
      context,
      preferred: MediaQuery.sizeOf(context).height * 0.82,
    );

    return UiDialog(
      semanticsLabel: 'Variant browser',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 760,
        maxHeight: maxHeight,
      ),
      builder: (context, style) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 760, maxHeight: maxHeight),
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.account_tree_outlined, color: tokens.accent),
                  const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
                  Expanded(
                    child: Text('VARIANT BROWSER', style: style.titleTextStyle),
                  ),
                  UiBadge('$imageCount images'),
                ],
              ),
              const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
              Text(
                'Choose a result or compare two image variants before applying it.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              Flexible(
                child: ListView.separated(
                  itemCount: _members.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final node = _members[index];
                    final isSelected = node.id == _selectedId;
                    final isCompared = _compareIds.contains(node.id);
                    return _VariantRow(
                      node: node,
                      imageCache: widget.imageCache,
                      selected: isSelected,
                      compared: isCompared,
                      compareEnabled: node.type == NodeType.image,
                      onSelect: () => setState(() => _selectedId = node.id),
                      onToggleCompare: () => _toggleCompare(node),
                    );
                  },
                ),
              ),
              if (_compareIds.length == 2) ...[
                const SizedBox(height: AppSpacing.lg),
                _ComparePanel(
                  first: _nodeById(_compareIds[0]),
                  second: _nodeById(_compareIds[1]),
                  imageCache: widget.imageCache,
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  UiButton(
                    variant: UiButtonVariant.ghost,
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                  if (!widget.readOnly) ...[
                    UiButton(
                      key: const ValueKey('variant-select-action'),
                      onPressed: _members.any((node) => node.id == _selectedId)
                          ? () {
                              widget.onSelectNode(_selectedId);
                              Navigator.pop(context);
                            }
                          : null,
                      prefix: const Icon(Icons.check, size: 16),
                      child: const Text('Use selected variant'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VariantRow extends StatelessWidget {
  final CanvasNode node;
  final CanvasImageCache? imageCache;
  final bool selected;
  final bool compared;
  final bool compareEnabled;
  final VoidCallback onSelect;
  final VoidCallback onToggleCompare;

  const _VariantRow({
    required this.node,
    this.imageCache,
    required this.selected,
    required this.compared,
    required this.compareEnabled,
    required this.onSelect,
    required this.onToggleCompare,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final label = node.name?.trim().isNotEmpty == true
        ? node.name!.trim()
        : '${node.type.name} ${node.id.substring(0, 4)}';
    final typeLabel = switch (node.type) {
      NodeType.image => 'Image',
      NodeType.videoCard => 'Video',
      _ => node.type.name,
    };

    return Semantics(
      container: true,
      label: '$label, $typeLabel${selected ? ', selected' : ''}',
      child: Material(
        key: ValueKey('variant-row-surface-${node.id}'),
        color: selected
            ? tokens.accent.withValues(alpha: 0.12)
            : tokens.panelElevated,
        borderRadius: const BorderRadius.all(
          Radius.circular(AppRadius.control),
        ),
        child: InkWell(
          key: ValueKey('variant-row-${node.id}'),
          borderRadius: const BorderRadius.all(
            Radius.circular(AppRadius.control),
          ),
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                _VariantThumbnail(node: node, imageCache: imageCache),
                const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tokens.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        typeLabel,
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          color: tokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (compareEnabled)
                  UiCheckbox(
                    key: ValueKey('compare-checkbox-${node.id}'),
                    value: compared,
                    semanticsLabel: 'Compare $label',
                    onChange: (_) => onToggleCompare(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ComparePanel extends StatelessWidget {
  final CanvasNode? first;
  final CanvasNode? second;
  final CanvasImageCache? imageCache;

  const _ComparePanel({
    required this.first,
    required this.second,
    this.imageCache,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return Container(
      key: const ValueKey('variant-compare-panel'),
      padding: const EdgeInsets.all(AppSpacing.sm + AppSpacing.xxs),
      decoration: BoxDecoration(
        color: tokens.panelElevated,
        border: Border.all(color: tokens.panelBorder, width: AppBorder.thin),
        borderRadius: BorderRadius.circular(AppRadius.panel),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'SIDE-BY-SIDE COMPARE',
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: tokens.text,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '2 of 2 images selected',
            style: Theme.of(
              context,
            ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: _CompareImage(node: first, imageCache: imageCache),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _CompareImage(node: second, imageCache: imageCache),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompareImage extends StatelessWidget {
  final CanvasNode? node;
  final CanvasImageCache? imageCache;

  const _CompareImage({required this.node, this.imageCache});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 110,
    child: _VariantThumbnail(
      node: node,
      expanded: true,
      imageCache: imageCache,
    ),
  );
}

class _VariantThumbnail extends StatefulWidget {
  final CanvasNode? node;
  final bool expanded;
  final CanvasImageCache? imageCache;

  const _VariantThumbnail({
    required this.node,
    this.expanded = false,
    this.imageCache,
  });

  @override
  State<_VariantThumbnail> createState() => _VariantThumbnailState();
}

class _VariantThumbnailState extends State<_VariantThumbnail> {
  ui.Image? _image;

  CanvasImageCache get _cache => widget.imageCache ?? CanvasImageCache.instance;

  @override
  void initState() {
    super.initState();
    _cache.addListener(_handleCacheUpdate);
    _load();
  }

  @override
  void didUpdateWidget(covariant _VariantThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageCache != widget.imageCache ||
        _sourceKeyForNode(oldWidget.node) != _sourceKeyForNode(widget.node)) {
      final oldCache = oldWidget.imageCache ?? CanvasImageCache.instance;
      oldCache.removeListener(_handleCacheUpdate);
      _cache.addListener(_handleCacheUpdate);
      _image = null;
      _load();
    }
  }

  @override
  void dispose() {
    _cache.removeListener(_handleCacheUpdate);
    super.dispose();
  }

  void _handleCacheUpdate() {
    if (!mounted) return;
    final next = _cachedImage();
    if (next != _image) setState(() => _image = next);
  }

  void _load() {
    final node = widget.node;
    if (node?.payload is! ImagePayload) return;
    final payload = node!.payload as ImagePayload;
    _image = _cache.getImage(_sourceKey(payload));
    _cache.requestImage(
      storagePath: payload.storagePath,
      localPath: payload.localPath,
      url: payload.url,
      imageArtifactReference: payload.imageArtifactReference,
    );
  }

  ui.Image? _cachedImage() {
    final node = widget.node;
    if (node?.payload is! ImagePayload) return null;
    return _cache.getImage(_sourceKey(node!.payload as ImagePayload));
  }

  String? _sourceKeyForNode(CanvasNode? node) {
    if (node?.payload is! ImagePayload) return null;
    return _sourceKey(node!.payload as ImagePayload);
  }

  String? _sourceKey(ImagePayload payload) {
    final artifactReference = payload.imageArtifactReference?.trim();
    if (artifactReference != null && artifactReference.isNotEmpty) {
      return artifactReference;
    }
    final storagePath = payload.storagePath?.trim();
    if (storagePath != null && storagePath.isNotEmpty) return storagePath;
    final localPath = payload.localPath?.trim();
    if (localPath != null && localPath.isNotEmpty) return localPath;
    return payload.url?.trim();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final node = widget.node;
    final label = node?.type == NodeType.image ? 'Image preview' : 'No preview';
    return Semantics(
      image: true,
      label: label,
      child: Container(
        width: widget.expanded ? double.infinity : 56,
        height: widget.expanded ? double.infinity : 56,
        decoration: BoxDecoration(
          color: tokens.canvas,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: tokens.panelBorder, width: AppBorder.thin),
        ),
        clipBehavior: Clip.antiAlias,
        child: _image == null
            ? Icon(
                node?.type == NodeType.image
                    ? Icons.image_outlined
                    : Icons.insert_drive_file_outlined,
                color: tokens.textMuted,
                size: widget.expanded ? 30 : 22,
              )
            : RawImage(image: _image, fit: BoxFit.cover),
      ),
    );
  }
}
