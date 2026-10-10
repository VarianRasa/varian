import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../app/responsive.dart';
import '../../../../app/theme.dart';
import '../../../../app/widgets/ui_primitives.dart';
import '../../domain/canvas_precision.dart';
import '../../state/canvas_precision_provider.dart';

class CanvasPrecisionDialog extends ConsumerStatefulWidget {
  final String projectId;

  const CanvasPrecisionDialog({super.key, required this.projectId});

  @override
  ConsumerState<CanvasPrecisionDialog> createState() =>
      _CanvasPrecisionDialogState();
}

class _CanvasPrecisionDialogState extends ConsumerState<CanvasPrecisionDialog> {
  late final TextEditingController _gridSpacingController;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(canvasPrecisionProvider(widget.projectId));
    _gridSpacingController = TextEditingController(
      text: initial.gridSpacing.toString(),
    );
  }

  @override
  void dispose() {
    _gridSpacingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(canvasPrecisionProvider(widget.projectId));
    final notifier = ref.read(
      canvasPrecisionProvider(widget.projectId).notifier,
    );
    final maxHeight = AppResponsive.dialogHeight(context, preferred: 620);
    return UiDialog(
      semanticsLabel: 'Canvas precision settings',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 560,
        maxHeight: maxHeight,
      ),
      builder: (dialogContext, style) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Precision settings',
                      style: style.titleTextStyle,
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close precision settings',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      UiSwitch(
                        label: const Text('Show grid'),
                        value: state.gridVisible,
                        onChange: notifier.setGridVisible,
                      ),
                      UiSelect<CanvasGridPreset>(
                        label: 'Grid preset',
                        items: {
                          for (final preset in CanvasGridPreset.values)
                            _precisionLabel(preset.name): preset,
                        },
                        value: state.gridPreset,
                        onChanged: (value) {
                          if (value != null) notifier.setGridPreset(value);
                        },
                      ),
                      UiTextField(
                        controller: _gridSpacingController,
                        label: 'Grid spacing',
                        hint: 'Pixels',
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onSubmitted: (value) {
                          final spacing = double.tryParse(value);
                          if (spacing != null) notifier.setGridSpacing(spacing);
                        },
                      ),
                      UiSelect<CanvasSnapMode>(
                        label: 'Snap mode',
                        items: {
                          for (final mode in CanvasSnapMode.values)
                            _precisionLabel(mode.name): mode,
                        },
                        value: state.snapMode,
                        onChanged: (value) {
                          if (value != null) notifier.setSnapMode(value);
                        },
                      ),
                      UiSwitch(
                        label: const Text('Show rulers'),
                        value: state.rulersVisible,
                        onChange: notifier.setRulersVisible,
                      ),
                      UiSwitch(
                        label: const Text('Show guides'),
                        value: state.guidesVisible,
                        onChange: notifier.setGuidesVisible,
                      ),
                      UiSwitch(
                        label: const Text('Smart guides'),
                        value: state.smartGuidesEnabled,
                        onChange: notifier.setSmartGuidesEnabled,
                      ),
                      UiSwitch(
                        label: const Text('Spacing measurements'),
                        value: state.measurementsVisible,
                        onChange: notifier.setMeasurementsVisible,
                      ),
                      const Divider(),
                      Text(
                        'Guides',
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (state.guides.isEmpty)
                        Text(
                          'No guides added.',
                          style: TextStyle(color: context.appTokens.textMuted),
                        )
                      else
                        for (final guide in state.guides)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: UiSurface(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md - AppSpacing.xxs,
                                vertical: AppSpacing.xs + AppSpacing.xxs,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    guide.axis == CanvasGuideAxis.vertical
                                        ? Icons.vertical_align_center
                                        : Icons.horizontal_rule,
                                  ),
                                  const SizedBox(
                                    width: AppSpacing.md - AppSpacing.xxs,
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${_precisionLabel(guide.axis.name)} · ${guide.position.toStringAsFixed(1)}',
                                        ),
                                        if (guide.label != null)
                                          Text(
                                            guide.label!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color:
                                                  context.appTokens.textMuted,
                                              fontSize: 11,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  UiIconButton(
                                    icon: Icons.delete_outline,
                                    tooltip: 'Remove guide',
                                    onPressed: guide.locked
                                        ? null
                                        : () => notifier.removeGuide(guide.id),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: UiButton(
                          variant: UiButtonVariant.ghost,
                          onPressed: () => _addGuide(dialogContext, notifier),
                          prefix: const Icon(Icons.add, size: 16),
                          child: const Text('Add guide'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: UiButton(
                  variant: UiButtonVariant.ghost,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addGuide(
    BuildContext context,
    CanvasPrecisionNotifier notifier,
  ) async {
    final result =
        await showUiDialog<({CanvasGuideAxis axis, double position})>(
          context: context,
          builder: (_) => const _CanvasGuideEditorDialog(),
        );
    if (result == null) return;
    notifier.addGuide(
      CanvasGuide(
        id: const Uuid().v4(),
        axis: result.axis,
        position: result.position,
      ),
    );
  }
}

class _CanvasGuideEditorDialog extends StatefulWidget {
  const _CanvasGuideEditorDialog();

  @override
  State<_CanvasGuideEditorDialog> createState() =>
      _CanvasGuideEditorDialogState();
}

class _CanvasGuideEditorDialogState extends State<_CanvasGuideEditorDialog> {
  final _positionController = TextEditingController(text: '0');
  CanvasGuideAxis _axis = CanvasGuideAxis.vertical;

  @override
  void dispose() {
    _positionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UiDialog(
    semanticsLabel: 'Add guide',
    constraints: AppResponsive.dialogConstraints(
      context,
      maxWidth: 420,
      maxHeight: 320,
    ),
    builder: (dialogContext, style) => Padding(
      padding: AppResponsive.dialogPadding(context),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Add guide', style: style.titleTextStyle)),
                UiIconButton(
                  icon: Icons.close,
                  tooltip: 'Close add guide',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            UiSelect<CanvasGuideAxis>(
              label: 'Axis',
              items: {
                for (final value in CanvasGuideAxis.values)
                  _precisionLabel(value.name): value,
              },
              value: _axis,
              onChanged: (value) {
                if (value != null) setState(() => _axis = value);
              },
            ),
            UiTextField(
              controller: _positionController,
              label: 'World position',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                UiButton(
                  variant: UiButtonVariant.ghost,
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                UiButton(
                  onPressed: () {
                    final position = double.tryParse(_positionController.text);
                    if (position == null) return;
                    Navigator.of(
                      dialogContext,
                    ).pop((axis: _axis, position: position));
                  },
                  prefix: const Icon(Icons.add, size: 16),
                  child: const Text('Add'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

String _precisionLabel(String value) => value
    .replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    )
    .replaceAll('_', ' ')
    .split(' ')
    .map(
      (word) =>
          word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}',
    )
    .join(' ');
