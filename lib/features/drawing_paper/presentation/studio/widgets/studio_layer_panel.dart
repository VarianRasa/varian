import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/state/drawing_paper_provider.dart';

int _layerDepth(List<DrawingLayer> layers, DrawingLayer layer) {
  final byId = {for (final candidate in layers) candidate.id: candidate};
  final visited = <String>{};
  var depth = 0;
  var parentId = layer.parentFolderId;
  while (parentId != null && visited.add(parentId)) {
    final parent = byId[parentId];
    if (parent == null) break;
    depth++;
    parentId = parent.parentFolderId;
  }
  return depth;
}

class StudioLayerPanel extends ConsumerWidget {
  final DrawingPaperPayload initialPayload;

  const StudioLayerPanel({super.key, required this.initialPayload});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(drawingStudioProviderFamily(initialPayload));
    final notifier = ref.read(
      drawingStudioProviderFamily(initialPayload).notifier,
    );
    final tokens = context.appTokens;

    return Container(
      key: const ValueKey('drawing-studio-layer-panel-frame'),
      width: 240,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
        ),
      ),
      child: UiSurface(
        color: tokens.panel,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.zero,
        bordered: false,
        child: Column(
          children: [
            // Header
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: tokens.panelBorder,
                    width: AppBorder.thin,
                  ),
                ),
              ),
              child: UiSurface(
                color: tokens.panel,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                borderRadius: BorderRadius.zero,
                bordered: false,
                child: Row(
                  children: [
                    Icon(Icons.layers_outlined, size: 16, color: tokens.accent),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Layers',
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        color: tokens.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    UiIconButton(
                      icon: Icons.create_new_folder_outlined,
                      tooltip: 'Add Folder Group',
                      size: UiButtonSize.sm,
                      onPressed: () => notifier.addFolderLayer(),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    UiIconButton(
                      icon: Icons.add,
                      tooltip: 'Add New Layer',
                      size: UiButtonSize.sm,
                      onPressed: () => notifier.addLayer(),
                    ),
                  ],
                ),
              ),
            ),

            // Layer Properties Toolbar (Opacity, Blend mode, Alpha lock, Clipping)
            if (state.activeLayer != null) ...[
              UiSurface(
                padding: const EdgeInsets.all(AppSpacing.sm),
                color: tokens.panelElevated,
                borderRadius: BorderRadius.zero,
                bordered: false,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          'Blend: ',
                          style: Theme.of(context).textTheme.labelSmall!
                              .copyWith(color: tokens.textMuted),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: UiSelect<BlendMode>(
                            items: const {
                              'Normal': BlendMode.srcOver,
                              'Multiply': BlendMode.multiply,
                              'Screen': BlendMode.screen,
                              'Overlay': BlendMode.overlay,
                              'Color Dodge': BlendMode.colorDodge,
                              'Color Burn': BlendMode.colorBurn,
                              'Hard Light': BlendMode.hardLight,
                              'Soft Light': BlendMode.softLight,
                            },
                            value: state.activeLayer!.blendMode,
                            label: 'BLEND',
                            onChanged: (mode) {
                              if (mode != null) {
                                notifier.updateActiveLayer(
                                  (l) => l.copyWith(blendMode: mode),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          'Opacity: ',
                          style: Theme.of(context).textTheme.labelSmall!
                              .copyWith(color: tokens.textMuted),
                        ),
                        Expanded(
                          child: UiSlider(
                            value: state.activeLayer!.opacity.clamp(0.0, 1.0),
                            onChanged: (value) {
                              notifier.updateActiveLayer(
                                (l) => l.copyWith(opacity: value),
                              );
                            },
                          ),
                        ),
                        Text(
                          '${(state.activeLayer!.opacity * 100).toInt()}%',
                          style: Theme.of(context).textTheme.labelSmall!
                              .copyWith(color: tokens.textMuted),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      alignment: WrapAlignment.center,
                      children: [
                        _MiniToggle(
                          label: 'α-Lock',
                          isActive: state.activeLayer!.alphaLocked,
                          onTap: () {
                            notifier.updateActiveLayer(
                              (l) => l.copyWith(alphaLocked: !l.alphaLocked),
                            );
                          },
                        ),
                        _MiniToggle(
                          label: 'Clip',
                          isActive: state.activeLayer!.clipToBelow,
                          onTap: () {
                            notifier.updateActiveLayer(
                              (l) => l.copyWith(clipToBelow: !l.clipToBelow),
                            );
                          },
                        ),
                        _MiniToggle(
                          label: 'Lock',
                          isActive: state.activeLayer!.locked,
                          onTap: () {
                            notifier.updateActiveLayer(
                              (l) => l.copyWith(locked: !l.locked),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // Layers List
            Expanded(
              child: ListView.builder(
                itemCount: state.payload.layers.length,
                itemBuilder: (context, index) {
                  final layer = state.payload.layers[index];
                  final isSelected = index == state.activeLayerIndex;
                  final depth = _layerDepth(state.payload.layers, layer);

                  return UiSurface(
                    padding: EdgeInsets.only(
                      left:
                          AppSpacing.md -
                          AppSpacing.xxs +
                          depth * AppSpacing.lg,
                      right: AppSpacing.sm + AppSpacing.xxs,
                      top: AppSpacing.xs + AppSpacing.xxs,
                      bottom: AppSpacing.xs + AppSpacing.xxs,
                    ),
                    color: isSelected
                        ? tokens.panelElevated
                        : Colors.transparent,
                    bordered: false,
                    child: Semantics(
                      container: true,
                      button: true,
                      selected: isSelected,
                      label: 'Layer ${layer.name}',
                      onTap: () => notifier.setActiveLayerIndex(index),
                      child: FocusableActionDetector(
                        autofocus: isSelected,
                        shortcuts: const <ShortcutActivator, Intent>{
                          SingleActivator(LogicalKeyboardKey.enter):
                              ActivateIntent(),
                          SingleActivator(LogicalKeyboardKey.space):
                              ActivateIntent(),
                        },
                        actions: <Type, Action<Intent>>{
                          ActivateIntent: CallbackAction<ActivateIntent>(
                            onInvoke: (_) =>
                                notifier.setActiveLayerIndex(index),
                          ),
                        },
                        child: GestureDetector(
                          key: ValueKey('drawing-layer-row-${layer.id}'),
                          onTap: () => notifier.setActiveLayerIndex(index),
                          child: Row(
                            children: [
                              UiIconButton(
                                icon: layer.visible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                tooltip: layer.visible
                                    ? 'Hide layer'
                                    : 'Show layer',
                                size: UiButtonSize.sm,
                                onPressed: () {
                                  notifier.updateLayerAt(
                                    index,
                                    (l) => l.copyWith(visible: !l.visible),
                                  );
                                },
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Icon(
                                layer.type == LayerType.folder
                                    ? Icons.folder_outlined
                                    : Icons.layers_outlined,
                                size: 15,
                                color: isSelected
                                    ? tokens.accent
                                    : tokens.textMuted,
                              ),
                              const SizedBox(
                                width: AppSpacing.xs + AppSpacing.xxs,
                              ),
                              Expanded(
                                child: Text(
                                  layer.name,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: isSelected
                                            ? tokens.text
                                            : tokens.textMuted,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                ),
                              ),
                              UiMenuButton<String>(
                                tooltip: 'Layer actions',
                                icon: Icons.more_vert,
                                items: const [
                                  UiMenuAction(
                                    value: 'duplicate',
                                    icon: Icons.copy_outlined,
                                    label: 'Duplicate Layer',
                                  ),
                                  UiMenuAction(
                                    value: 'merge',
                                    icon: Icons.merge_type,
                                    label: 'Merge Down',
                                  ),
                                  UiMenuAction(
                                    value: 'clear',
                                    icon: Icons.layers_clear_outlined,
                                    label: 'Clear Contents',
                                  ),
                                  UiMenuAction(
                                    value: 'delete',
                                    icon: Icons.delete_outline,
                                    label: 'Delete Layer',
                                    destructive: true,
                                  ),
                                ],
                                onSelected: (val) {
                                  if (val == 'duplicate') {
                                    notifier.duplicateLayer(index);
                                  }
                                  if (val == 'merge') {
                                    notifier.mergeLayerDown(index);
                                  }
                                  if (val == 'clear') {
                                    notifier.clearLayerAt(index);
                                  }
                                  if (val == 'delete') {
                                    notifier.removeLayer(index);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniToggle extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _MiniToggle({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return UiButton(
      onPressed: onTap,
      variant: isActive ? UiButtonVariant.primary : UiButtonVariant.outline,
      size: UiButtonSize.sm,
      child: Text(label),
    );
  }
}
