import 'package:flutter/material.dart';

import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';

import '../../../app/widgets/ui_primitives.dart';
import '../export_presets.dart';
import '../data/export_file_saver.dart';
import 'export_preset_chooser.dart';

export '../data/export_file_saver.dart' show ExportSaveOutcome;

/// The canvas region an export should contain.
enum ExportTarget { currentCanvas, selection, selectedFrame }

/// Presents export format and target choices without generating document data.
class ExportCenterDialog extends StatefulWidget {
  final ExportPreset initialPreset;
  final ExportTarget initialTarget;
  final bool hasSelection;
  final bool hasSelectedFrame;
  final Future<ExportSaveOutcome> Function(
    ExportTarget target,
    ExportPreset preset,
  )
  onExport;

  const ExportCenterDialog({
    required this.onExport,
    this.initialPreset = ExportPresetRegistry.png,
    this.initialTarget = ExportTarget.currentCanvas,
    this.hasSelection = false,
    this.hasSelectedFrame = false,
    super.key,
  });

  @override
  State<ExportCenterDialog> createState() => _ExportCenterDialogState();
}

class _ExportCenterDialogState extends State<ExportCenterDialog> {
  late ExportPreset _selectedPreset;
  late ExportTarget _selectedTarget;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedPreset = widget.initialPreset;
    _selectedTarget = _isTargetAvailable(widget.initialTarget)
        ? widget.initialTarget
        : ExportTarget.currentCanvas;
  }

  @override
  Widget build(BuildContext context) => UiDialog(
    semanticsLabel: 'Export canvas',
    constraints: AppResponsive.dialogConstraints(
      context,
      maxWidth: 560,
      maxHeight: 700,
    ),
    builder: (context, style) => SingleChildScrollView(
      padding: AppResponsive.dialogPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('EXPORT CENTER', style: style.titleTextStyle),
              ),
              UiIconButton(
                icon: Icons.close,
                tooltip: 'Close export center',
                onPressed: _isSaving ? null : () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Choose what to export and how to format it.'),
          const SizedBox(height: AppSpacing.pageWide),
          Text(
            'Export target',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          _TargetOption(
            target: ExportTarget.currentCanvas,
            label: 'Current canvas',
            description: 'Export the complete canvas.',
            selected: _selectedTarget,
            enabled: !_isSaving,
            onChanged: _selectTarget,
          ),
          _TargetOption(
            target: ExportTarget.selection,
            label: 'Selection',
            description: widget.hasSelection
                ? 'Export the selected canvas objects.'
                : 'No canvas selection is available.',
            selected: _selectedTarget,
            enabled: widget.hasSelection && !_isSaving,
            onChanged: _selectTarget,
          ),
          _TargetOption(
            target: ExportTarget.selectedFrame,
            label: 'Selected frame',
            description: widget.hasSelectedFrame
                ? 'Export the selected frame.'
                : 'No frame is selected.',
            selected: _selectedTarget,
            enabled: widget.hasSelectedFrame && !_isSaving,
            onChanged: _selectTarget,
          ),
          const SizedBox(height: AppSpacing.lg),
          ExportPresetChooser(
            selected: _selectedPreset,
            label: 'Export format',
            hint: 'Choose a format',
            enabled: !_isSaving,
            onChanged: (preset) => setState(() {
              _selectedPreset = preset;
              _errorMessage = null;
            }),
          ),
          if (_errorMessage case final message?) ...[
            const SizedBox(height: AppSpacing.md),
            Semantics(
              liveRegion: true,
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.appTokens.danger,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.pageWide),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              UiButton(
                onPressed: _isSaving
                    ? null
                    : () => Navigator.pop(context, ExportSaveOutcome.canceled),
                variant: UiButtonVariant.ghost,
                semanticsLabel: 'Cancel export',
                child: const Text('Cancel'),
              ),
              UiButton(
                onPressed: _isSaving ? null : _handleExport,
                prefix: _isSaving
                    ? const UiProgressIndicator(semanticsLabel: 'Saving export')
                    : const Icon(Icons.save_outlined),
                semanticsLabel: _isSaving ? 'Saving export' : 'Save export',
                child: Text(_isSaving ? 'Saving...' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  bool _isTargetAvailable(ExportTarget target) => switch (target) {
    ExportTarget.currentCanvas => true,
    ExportTarget.selection => widget.hasSelection,
    ExportTarget.selectedFrame => widget.hasSelectedFrame,
  };

  void _selectTarget(ExportTarget target) {
    if (!_isTargetAvailable(target) || _isSaving) return;
    setState(() {
      _selectedTarget = target;
      _errorMessage = null;
    });
  }

  Future<void> _handleExport() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final outcome = await widget.onExport(_selectedTarget, _selectedPreset);
      if (!mounted) return;
      if (outcome == ExportSaveOutcome.failed) {
        setState(() => _errorMessage = 'Export failed. Please try again.');
      } else {
        Navigator.pop(context, outcome);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Export failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _TargetOption extends StatelessWidget {
  final ExportTarget target;
  final String label;
  final String description;
  final ExportTarget selected;
  final bool enabled;
  final ValueChanged<ExportTarget> onChanged;

  const _TargetOption({
    required this.target,
    required this.label,
    required this.description,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: UiRadioChoice(
      value: selected == target,
      enabled: enabled,
      semanticsLabel: label,
      label: Text(label),
      description: Text(description),
      onChange: (_) => onChanged(target),
    ),
  );
}
