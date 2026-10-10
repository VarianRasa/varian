import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../../../domain/models/document.dart';
import '../domain/inspect_handoff.dart';
import '../../export/data/export_file_saver.dart';

typedef InspectHandoffSaveCallback =
    Future<ExportSaveOutcome> Function(
      InspectHandoffFormat format,
      String content,
    );

class InspectHandoffDialog extends StatefulWidget {
  final CanvasDocument document;
  final Iterable<String>? nodeIds;
  final InspectHandoffSaveCallback? onExport;

  const InspectHandoffDialog({
    required this.document,
    this.nodeIds,
    this.onExport,
    super.key,
  });

  @override
  State<InspectHandoffDialog> createState() => _InspectHandoffDialogState();
}

class _InspectHandoffDialogState extends State<InspectHandoffDialog> {
  late InspectHandoffFormat _format;
  late InspectHandoffBundle _bundle;
  bool _isSaving = false;
  bool _copied = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _format = InspectHandoffFormat.json;
    _bundle = InspectHandoffService.inspect(
      widget.document,
      nodeIds: widget.nodeIds,
    );
  }

  String get _content => InspectHandoffService.export(
    widget.document,
    nodeIds: _bundle.sourceNodeIds,
    format: _format,
  );

  @override
  Widget build(BuildContext context) {
    final compact = AppResponsive.isNarrow(context);
    final height = AppResponsive.dialogHeight(
      context,
      preferred: MediaQuery.sizeOf(context).height * 0.82,
      maxHeight: 640,
    );

    return UiDialog(
      semanticsLabel: 'Inspect and handoff',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 760,
        maxHeight: 640,
      ),
      builder: (context, style) => SizedBox(
        height: height,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'INSPECT & HANDOFF',
                      style: style.titleTextStyle,
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close inspect mode',
                    onPressed: _isSaving ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
              Text(
                '${_bundle.nodes.length} visible node${_bundle.nodes.length == 1 ? '' : 's'} · document schema ${_bundle.documentSchemaVersion}',
                style: TextStyle(color: context.appTokens.textMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              _buildSummary(context),
              const SizedBox(height: AppSpacing.md),
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFormatPicker(context),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _buildCopyButton(),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(child: _buildFormatPicker(context)),
                    const SizedBox(width: AppSpacing.sm),
                    _buildCopyButton(),
                  ],
                ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: compact ? 180 : 280,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.appTokens.canvas,
                    border: Border.all(
                      color: context.appTokens.panelBorder,
                      width: AppBorder.thin,
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.panel),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: SelectableText(
                      _content,
                      key: const ValueKey('inspect-handoff-content'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ),
              if (_errorMessage case final message?) ...[
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: context.appTokens.danger,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: _buildCloseButton(context),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _buildSaveButton(),
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildCloseButton(context),
                    const SizedBox(width: AppSpacing.sm),
                    _buildSaveButton(),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCopyButton() => UiButton(
    variant: UiButtonVariant.outline,
    semanticsLabel: _copied ? 'Copied handoff' : 'Copy handoff',
    onPressed: _isSaving ? null : _copyContent,
    prefix: Icon(_copied ? Icons.check : Icons.copy_outlined),
    child: Text(_copied ? 'Copied' : 'Copy'),
  );

  Widget _buildCloseButton(BuildContext context) => UiButton(
    variant: UiButtonVariant.ghost,
    semanticsLabel: 'Close inspect mode',
    onPressed: _isSaving ? null : () => Navigator.pop(context),
    child: const Text('Close'),
  );

  Widget _buildSaveButton() => UiButton(
    semanticsLabel: _isSaving ? 'Saving handoff' : 'Save handoff',
    onPressed: _isSaving || widget.onExport == null ? null : _save,
    prefix: _isSaving
        ? const UiProgressIndicator(semanticsLabel: 'Saving handoff')
        : const Icon(Icons.download_outlined),
    child: Text(_isSaving ? 'Saving...' : 'Save ${_format.name.toUpperCase()}'),
  );

  Widget _buildSummary(BuildContext context) {
    final tokens = context.appTokens;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _summaryChip(context, 'Bounds', _formatBounds(_bundle.bounds)),
        _summaryChip(context, 'Project', _bundle.projectId),
        _summaryChip(context, 'Canvas', _bundle.canvasId),
        _summaryChip(
          context,
          'Assets',
          '${_bundle.nodes.where((node) => node.asset.isNotEmpty).length}',
        ),
        _summaryChip(
          context,
          'Tokens',
          '${_bundle.nodes.where((node) => node.tokens.isNotEmpty).length}',
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: tokens.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.control),
          ),
          child: Text(
            'Non-destructive · version ${InspectHandoffBundle.schemaVersion}',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: tokens.accent),
          ),
        ),
      ],
    );
  }

  Widget _summaryChip(BuildContext context, String label, String value) {
    final tokens = context.appTokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.panelElevated,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: tokens.panelBorder, width: AppBorder.thin),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: tokens.textMuted),
      ),
    );
  }

  Widget _buildFormatPicker(BuildContext context) =>
      UiSelect<InspectHandoffFormat>(
        key: const ValueKey('inspect-handoff-format'),
        items: {
          for (final format in InspectHandoffFormat.values)
            _formatLabel(format): format,
        },
        value: _format,
        label: 'Handoff format',
        hint: 'Choose a handoff format',
        enabled: !_isSaving,
        onChanged: (value) {
          if (value == null) return;
          setState(() {
            _format = value;
            _copied = false;
            _errorMessage = null;
          });
        },
      );

  Future<void> _copyContent() async {
    await Clipboard.setData(ClipboardData(text: _content));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  Future<void> _save() async {
    final callback = widget.onExport;
    if (callback == null || _isSaving) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final outcome = await callback(_format, _content);
      if (!mounted) return;
      if (outcome == ExportSaveOutcome.failed) {
        setState(
          () => _errorMessage = 'Handoff save failed. Please try again.',
        );
      } else {
        Navigator.pop(context, outcome);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Handoff save failed. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatLabel(InspectHandoffFormat format) => switch (format) {
    InspectHandoffFormat.css => 'CSS · .css',
    InspectHandoffFormat.flutter => 'Flutter · .dart',
    InspectHandoffFormat.svg => 'SVG · .svg',
    InspectHandoffFormat.json => 'JSON · .json',
  };

  String _formatBounds(Rect bounds) =>
      '${bounds.width.toStringAsFixed(0)} × ${bounds.height.toStringAsFixed(0)}';
}
