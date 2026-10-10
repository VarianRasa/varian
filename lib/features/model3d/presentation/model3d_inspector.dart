import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../../../domain/models/model3d_payload.dart';
import '../../../domain/models/model3d_studio.dart';
import '../../../domain/models/node.dart';
import '../../canvas/state/document_nodes_provider.dart';

class Model3DInspectorControls extends ConsumerWidget {
  final CanvasNode node;
  final Model3DPayload payload;
  final VoidCallback? onReset;
  final VoidCallback? onRetry;
  final Future<void> Function()? onReplace;

  const Model3DInspectorControls({
    required this.node,
    required this.payload,
    this.onReset,
    this.onRetry,
    this.onReplace,
    super.key,
  });

  List<int> _wireframeColors(BuildContext context) {
    final tokens = context.appTokens;
    final colors = <int>[
      tokens.text.toARGB32(),
      tokens.textMuted.toARGB32(),
      0xFFEF4444,
      0xFF2563EB,
      0xFF22C55E,
      0xFFFACC15,
    ];
    if (!colors.contains(payload.wireframeColor)) {
      colors.add(payload.wireframeColor);
    }
    return colors;
  }

  void _update(WidgetRef ref, Model3DPayload next) {
    ref
        .read(documentNodesProvider.notifier)
        .updateNode(node.copyWith(payload: next));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.appTokens;
    final source = payload.artifactReference?.trim().isNotEmpty == true
        ? 'Local artifact'
        : payload.modelUrl?.trim().isNotEmpty == true
        ? 'Remote URL'
        : payload.modelPath?.trim().isNotEmpty == true
        ? 'Local path'
        : 'Unavailable';

    Widget metadataRow(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall!.copyWith(color: tokens.text),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const UiSectionHeader(title: 'GLB MODEL'),
        const SizedBox(height: AppSpacing.sm),
        UiSurface(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              metadataRow('File', payload.displayName),
              metadataRow('Size', payload.fileSizeText),
              metadataRow('Source', source),
              if (payload.sourceError?.trim().isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                  child: Text(
                    payload.sourceError!,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall!.copyWith(color: tokens.danger),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        UiSurface(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _switchRow(
                context,
                label: 'Auto-rotate preview',
                value: payload.autoRotate,
                onChanged: (value) =>
                    _update(ref, payload.copyWith(autoRotate: value)),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: UiButton(
                      onPressed: onReset,
                      variant: UiButtonVariant.outline,
                      size: UiButtonSize.sm,
                      mainAxisSize: MainAxisSize.max,
                      prefix: const Icon(Icons.center_focus_strong, size: 15),
                      child: const Flexible(
                        child: Text(
                          'Reset view',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: UiButton(
                      onPressed: onRetry,
                      variant: UiButtonVariant.outline,
                      size: UiButtonSize.sm,
                      mainAxisSize: MainAxisSize.max,
                      prefix: const Icon(Icons.refresh, size: 15),
                      child: const Flexible(
                        child: Text(
                          'Retry preview',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: UiButton(
                  onPressed: onReplace,
                  variant: UiButtonVariant.outline,
                  size: UiButtonSize.sm,
                  mainAxisSize: MainAxisSize.max,
                  prefix: const Icon(Icons.upload_file_outlined, size: 15),
                  child: const Flexible(
                    child: Text(
                      'Replace GLB',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
        _buildWireframeSection(context, ref),
        const SizedBox(height: AppSpacing.md),
        _buildViewportSection(context, ref),
        const SizedBox(height: AppSpacing.md),
        _buildStudioSection(context, ref),
        const SizedBox(height: AppSpacing.md),
        _buildChoiceSection(
          context,
          ref,
          title: 'RENDER (1)',
          choices: [
            _Choice(
              'Final Render',
              Icons.lens_outlined,
              payload.inspectorSelection ==
                  Model3DInspectorSelection.finalRender,
              () => _select(ref, Model3DInspectorSelection.finalRender),
            ),
            _Choice(
              'No Post-Processing',
              Icons.lens_blur_outlined,
              payload.inspectorSelection ==
                  Model3DInspectorSelection.noPostProcessing,
              () => _select(ref, Model3DInspectorSelection.noPostProcessing),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _buildChoiceSection(
          context,
          ref,
          title: 'MATERIAL CHANNELS (2)',
          choices: [
            _materialChoice(
              ref,
              'Base Color',
              Icons.invert_colors_outlined,
              Model3DMaterialChannel.baseColor,
            ),
            _materialChoice(
              ref,
              'Metalness',
              Icons.bolt_outlined,
              Model3DMaterialChannel.metalness,
            ),
            _materialChoice(
              ref,
              'Roughness',
              Icons.grain,
              Model3DMaterialChannel.roughness,
            ),
            _materialChoice(
              ref,
              'Normal Map',
              Icons.explore_outlined,
              Model3DMaterialChannel.normalMap,
            ),
            _materialChoice(
              ref,
              'AO map',
              Icons.blur_linear,
              Model3DMaterialChannel.aoMap,
            ),
            _materialChoice(
              ref,
              'Cavity',
              Icons.filter_b_and_w_outlined,
              Model3DMaterialChannel.cavity,
            ),
            _materialChoice(
              ref,
              'Opacity',
              Icons.opacity,
              Model3DMaterialChannel.opacity,
            ),
            _materialChoice(
              ref,
              'Specular F0',
              Icons.circle_outlined,
              Model3DMaterialChannel.specularF0,
            ),
            _materialChoice(
              ref,
              'Clear Coat',
              Icons.layers_outlined,
              Model3DMaterialChannel.clearCoat,
            ),
            _materialChoice(
              ref,
              'Clear Coat Roughness',
              Icons.grain,
              Model3DMaterialChannel.clearCoatRoughness,
            ),
            _materialChoice(
              ref,
              'Clear Coat Normal Map',
              Icons.explore_outlined,
              Model3DMaterialChannel.clearCoatNormalMap,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _buildChoiceSection(
          context,
          ref,
          title: 'GEOMETRY (3)',
          choices: [
            _geometryChoice(
              ref,
              'Matcap',
              Icons.lens_outlined,
              Model3DGeometryMode.matcap,
            ),
            _geometryChoice(
              ref,
              'Matcap+Surface',
              Icons.lens_blur_outlined,
              Model3DGeometryMode.matcapSurface,
            ),
            _geometryChoice(
              ref,
              'Wireframe',
              Icons.square_outlined,
              Model3DGeometryMode.wireframe,
            ),
            if (payload.inspectorSelection ==
                Model3DInspectorSelection.wireframe)
              _Choice(
                'Disable wireframe',
                Icons.close,
                false,
                () => _select(ref, Model3DInspectorSelection.finalRender),
              ),
            _geometryChoice(
              ref,
              'Vertex Normals',
              Icons.open_in_full,
              Model3DGeometryMode.vertexNormals,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _buildChoiceSection(
          context,
          ref,
          title: 'UV (4)',
          choices: [
            _Choice(
              'UV Checker',
              Icons.grid_4x4,
              payload.inspectorSelection == Model3DInspectorSelection.uvChecker,
              () => _select(ref, Model3DInspectorSelection.uvChecker),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStudioSection(BuildContext context, WidgetRef ref) {
    final tokens = context.appTokens;
    final activeBookmark = payload.cameraBookmarks
        .where((bookmark) => bookmark.id == payload.activeCameraBookmarkId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const UiSectionHeader(title: '3D STUDIO'),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        Row(
          children: [
            Expanded(
              child: UiSelect<Model3DLightingPreset>(
                items: {
                  for (final preset in Model3DLightingPreset.values)
                    _lightingLabel(preset): preset,
                },
                value: payload.lightingPreset,
                onChanged: (value) {
                  if (value != null) {
                    _update(ref, payload.copyWith(lightingPreset: value));
                  }
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            UiButton(
              variant: UiButtonVariant.outline,
              size: UiButtonSize.sm,
              prefix: const Icon(Icons.add, size: 14),
              onPressed: () {
                final id = 'camera-${DateTime.now().microsecondsSinceEpoch}';
                final next = payload
                    .upsertCameraBookmark(
                      Model3DCameraBookmark(
                        id: id,
                        label: 'View ${payload.cameraBookmarks.length + 1}',
                      ),
                    )
                    .copyWith(activeCameraBookmarkId: id);
                _update(ref, next);
              },
              child: const Text('Camera'),
            ),
          ],
        ),
        if (payload.cameraBookmarks.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          Row(
            children: [
              Expanded(
                child: UiSelect<String>(
                  hint: 'Select camera bookmark',
                  items: {
                    for (final bookmark in payload.cameraBookmarks)
                      bookmark.label: bookmark.id,
                  },
                  value: activeBookmark?.id,
                  onChanged: (value) => _update(
                    ref,
                    payload.copyWith(activeCameraBookmarkId: value),
                  ),
                ),
              ),
              UiIconButton(
                icon: Icons.delete_outline,
                tooltip: 'Remove camera bookmark',
                onPressed: activeBookmark == null
                    ? null
                    : () => _update(
                        ref,
                        payload.removeCameraBookmark(activeBookmark.id),
                      ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                payload.annotations.isEmpty
                    ? 'No annotations'
                    : '${payload.annotations.length} annotation(s)',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
              ),
            ),
            UiButton(
              variant: UiButtonVariant.ghost,
              size: UiButtonSize.sm,
              prefix: const Icon(Icons.add_comment_outlined, size: 14),
              onPressed: () {
                final id =
                    'annotation-${DateTime.now().microsecondsSinceEpoch}';
                _update(
                  ref,
                  payload.upsertAnnotation(
                    Model3DAnnotation(
                      id: id,
                      label: 'Note ${payload.annotations.length + 1}',
                    ),
                  ),
                );
              },
              child: const Text('Add note'),
            ),
          ],
        ),
        for (final annotation in payload.annotations.take(4))
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 16,
                  color: Color(annotation.colorArgb),
                ),
                const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        annotation.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        annotation.text.isEmpty
                            ? 'No annotation text'
                            : annotation.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: tokens.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                UiIconButton(
                  icon: Icons.close,
                  tooltip: 'Remove annotation',
                  onPressed: () =>
                      _update(ref, payload.removeAnnotation(annotation.id)),
                ),
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: UiButton(
            variant: UiButtonVariant.outline,
            size: UiButtonSize.sm,
            mainAxisSize: MainAxisSize.max,
            prefix: const Icon(Icons.camera_alt_outlined, size: 14),
            onPressed: () {
              final id = 'snapshot-${DateTime.now().microsecondsSinceEpoch}';
              _update(
                ref,
                payload.upsertSnapshot(
                  Model3DSnapshot(
                    id: id,
                    label: 'Snapshot ${payload.snapshots.length + 1}',
                    cameraBookmarkId: payload.activeCameraBookmarkId,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  ),
                ),
              );
            },
            child: const Flexible(
              child: Text(
                'Save snapshot metadata',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        if (payload.snapshots.isNotEmpty)
          Text(
            '${payload.snapshots.length} snapshot(s) recorded',
            style: TextStyle(color: tokens.textMuted, fontSize: 10),
          ),
        if (payload.diagnostics.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          for (final message in payload.diagnostics)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
              child: Text(
                message,
                style: TextStyle(color: tokens.warning, fontSize: 10),
              ),
            ),
        ],
      ],
    );
  }

  String _lightingLabel(Model3DLightingPreset preset) => switch (preset) {
    Model3DLightingPreset.studio => 'Studio lighting',
    Model3DLightingPreset.neutral => 'Neutral lighting',
    Model3DLightingPreset.dramatic => 'Dramatic lighting',
    Model3DLightingPreset.flat => 'Flat lighting',
  };

  Widget _buildWireframeSection(BuildContext context, WidgetRef ref) {
    final tokens = context.appTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const UiSectionHeader(title: 'WIREFRAME (5)'),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final color in _wireframeColors(context))
              _swatchButton(
                context,
                label: 'Use wireframe color',
                color: Color(color),
                selected:
                    payload.inspectorSelection ==
                        Model3DInspectorSelection.wireframe &&
                    payload.wireframeColor == color,
                onPressed: () => _select(
                  ref,
                  Model3DInspectorSelection.wireframe,
                  wireframeColor: color,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                payload.doubleSided ? 'Double Sided' : 'Single Sided',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium!.copyWith(color: tokens.text),
              ),
            ),
            UiSwitch(
              value: payload.doubleSided,
              semanticsLabel: 'Double-sided model',
              onChange: (value) =>
                  _update(ref, payload.copyWith(doubleSided: value)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildViewportSection(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const UiSectionHeader(title: 'VIEWPORT'),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        Row(
          children: [
            for (final choice in [
              (label: '3D', mode: Model3DViewportMode.threeD),
              (label: '3D + 2D', mode: Model3DViewportMode.threeDAndTwoD),
              (label: '2D', mode: Model3DViewportMode.twoD),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: UiButton(
                    onPressed: () => _update(
                      ref,
                      payload.copyWith(viewportMode: choice.mode),
                    ),
                    variant: payload.viewportMode == choice.mode
                        ? UiButtonVariant.primary
                        : UiButtonVariant.ghost,
                    size: UiButtonSize.sm,
                    mainAxisSize: MainAxisSize.max,
                    child: Flexible(
                      child: Text(
                        choice.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        _switchRow(
          context,
          label: 'Transparent background',
          value: payload.transparentBackground,
          onChanged: (value) =>
              _update(ref, payload.copyWith(transparentBackground: value)),
        ),
      ],
    );
  }

  _Choice _materialChoice(
    WidgetRef ref,
    String label,
    IconData icon,
    Model3DMaterialChannel channel,
  ) {
    final selection = _selectionForMaterial(channel);
    return _Choice(
      label,
      icon,
      payload.inspectorSelection == selection,
      () => _select(ref, selection),
    );
  }

  _Choice _geometryChoice(
    WidgetRef ref,
    String label,
    IconData icon,
    Model3DGeometryMode mode,
  ) {
    final selection = _selectionForGeometry(mode);
    return _Choice(
      label,
      icon,
      payload.inspectorSelection == selection,
      () => _select(ref, selection),
    );
  }

  void _select(
    WidgetRef ref,
    Model3DInspectorSelection selection, {
    int? wireframeColor,
  }) => _update(
    ref,
    payload.copyWithInspectorSelection(
      selection,
      wireframeColor: wireframeColor,
    ),
  );

  Model3DInspectorSelection _selectionForMaterial(
    Model3DMaterialChannel channel,
  ) => switch (channel) {
    Model3DMaterialChannel.baseColor => Model3DInspectorSelection.baseColor,
    Model3DMaterialChannel.metalness => Model3DInspectorSelection.metalness,
    Model3DMaterialChannel.roughness => Model3DInspectorSelection.roughness,
    Model3DMaterialChannel.normalMap => Model3DInspectorSelection.normalMap,
    Model3DMaterialChannel.aoMap => Model3DInspectorSelection.aoMap,
    Model3DMaterialChannel.cavity => Model3DInspectorSelection.cavity,
    Model3DMaterialChannel.opacity => Model3DInspectorSelection.opacity,
    Model3DMaterialChannel.specularF0 => Model3DInspectorSelection.specularF0,
    Model3DMaterialChannel.clearCoat => Model3DInspectorSelection.clearCoat,
    Model3DMaterialChannel.clearCoatRoughness =>
      Model3DInspectorSelection.clearCoatRoughness,
    Model3DMaterialChannel.clearCoatNormalMap =>
      Model3DInspectorSelection.clearCoatNormalMap,
  };

  Model3DInspectorSelection _selectionForGeometry(Model3DGeometryMode mode) =>
      switch (mode) {
        Model3DGeometryMode.matcap => Model3DInspectorSelection.matcap,
        Model3DGeometryMode.matcapSurface =>
          Model3DInspectorSelection.matcapSurface,
        Model3DGeometryMode.wireframe => Model3DInspectorSelection.wireframe,
        Model3DGeometryMode.vertexNormals =>
          Model3DInspectorSelection.vertexNormals,
        Model3DGeometryMode.none => Model3DInspectorSelection.finalRender,
      };

  Widget _buildChoiceSection(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required List<_Choice> choices,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      UiSectionHeader(title: title),
      const SizedBox(height: AppSpacing.xs),
      for (final choice in choices) _choiceButton(context, choice),
    ],
  );

  Widget _choiceButton(BuildContext context, _Choice choice) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
    child: UiButton(
      onPressed: choice.onPressed,
      variant: choice.selected
          ? UiButtonVariant.primary
          : UiButtonVariant.ghost,
      size: UiButtonSize.sm,
      mainAxisSize: MainAxisSize.max,
      prefix: Icon(choice.icon, size: 16),
      semanticsLabel: choice.label,
      child: Flexible(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            choice.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ),
  );

  Widget _switchRow(
    BuildContext context, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final tokens = context.appTokens;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium!.copyWith(color: tokens.text),
          ),
        ),
        UiSwitch(value: value, semanticsLabel: label, onChange: onChanged),
      ],
    );
  }

  Widget _swatchButton(
    BuildContext context, {
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onPressed,
    IconData? icon,
  }) {
    final tokens = context.appTokens;
    return UiButton(
      onPressed: onPressed,
      variant: selected ? UiButtonVariant.primary : UiButtonVariant.ghost,
      size: UiButtonSize.sm,
      semanticsLabel: label,
      child: SizedBox(
        width: 20,
        height: 20,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: selected ? tokens.accentForeground : tokens.panelBorder,
            ),
          ),
          child: icon == null ? null : Icon(icon, size: 14, color: tokens.text),
        ),
      ),
    );
  }
}

class _Choice {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  const _Choice(this.label, this.icon, this.selected, this.onPressed);
}
