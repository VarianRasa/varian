import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../../../domain/models/node.dart';
import '../../../domain/models/node_payload.dart';
import '../data/mermaid_renderer.dart';
import '../domain/mermaid_renderer.dart';
import 'mermaid_node_preview.dart';

/// Edits the canonical Mermaid source attached to a canvas node.
class MermaidEditorDialog extends StatefulWidget {
  final CanvasNode node;
  final bool readOnly;
  final MermaidRenderer? renderer;
  final ValueChanged<MermaidPayload> onSave;

  const MermaidEditorDialog({
    required this.node,
    required this.onSave,
    this.readOnly = false,
    this.renderer,
    super.key,
  });

  @override
  State<MermaidEditorDialog> createState() => _MermaidEditorDialogState();
}

class _MermaidEditorDialogState extends State<MermaidEditorDialog> {
  late MermaidPayload _draft;
  late TextEditingController _sourceController;
  late MermaidRenderer _renderer;
  Timer? _validationTimer;
  int _validationToken = 0;
  MermaidDiagnostic? _validationDiagnostic;

  @override
  void initState() {
    super.initState();
    _draft = widget.node.payload is MermaidPayload
        ? (widget.node.payload as MermaidPayload).clone()
        : MermaidPayload();
    _sourceController = TextEditingController(text: _draft.source);
    _renderer = widget.renderer ?? createPlatformMermaidRenderer();
    _scheduleValidation();
  }

  @override
  void dispose() {
    _validationTimer?.cancel();
    _sourceController.dispose();
    super.dispose();
  }

  void _onSourceChanged(String source) {
    if (source == _draft.source) return;
    setState(() {
      _draft = _draft.updateSource(source);
      _validationDiagnostic = MermaidSourceLimits.validate(source);
    });
    _scheduleValidation();
  }

  void _scheduleValidation() {
    _validationTimer?.cancel();
    final source = _draft.source;
    final revision = _draft.sourceRevision;
    _validationTimer = Timer(const Duration(milliseconds: 280), () {
      unawaited(_validate(source, revision));
    });
  }

  Future<void> _validate(String source, int revision) async {
    final localDiagnostic = MermaidSourceLimits.validate(source);
    if (localDiagnostic != null) {
      if (!mounted || revision != _draft.sourceRevision) return;
      setState(() => _validationDiagnostic = localDiagnostic);
      return;
    }

    final token = ++_validationToken;
    final result = await _renderer.validate(
      source,
      config: MermaidRenderConfig(
        theme: _draft.theme,
        direction: _draft.direction,
        overrides: _draft.config,
      ),
    );
    if (!mounted ||
        token != _validationToken ||
        revision != _draft.sourceRevision) {
      return;
    }

    setState(() {
      _validationDiagnostic = result.diagnostic;
      if (result.isValid && result.diagramType != 'unknown') {
        _draft = _draft.copyWith(diagramType: result.diagramType);
      }
    });
  }

  void _updateTheme(MermaidTheme? theme) {
    if (theme == null) return;
    setState(() {
      _draft = _draft.copyWith(
        theme: theme,
        cachedSvg: null,
        cachedSvgRevision: null,
        cachedSvgConfigKey: null,
        rendererVersion: null,
        lastError: null,
      );
      _validationDiagnostic = null;
    });
    _scheduleValidation();
  }

  void _updateDirection(String? value) {
    if (value == null) return;
    final direction = value == 'auto'
        ? null
        : MermaidDirection.fromValue(value);
    setState(() {
      _draft = _draft.copyWith(
        direction: direction,
        cachedSvg: null,
        cachedSvgRevision: null,
        cachedSvgConfigKey: null,
        rendererVersion: null,
        lastError: null,
      );
      _validationDiagnostic = null;
    });
    _scheduleValidation();
  }

  void _handleRenderState(MermaidPayload rendered) {
    if (!mounted || rendered.sourceRevision != _draft.sourceRevision) return;
    setState(() {
      _draft = rendered;
      if (rendered.lastError != null) {
        _validationDiagnostic = rendered.lastError;
      }
    });
  }

  void _save() {
    if (!_canSave) return;
    widget.onSave(_draft);
    Navigator.of(context).pop();
  }

  bool get _canSave => MermaidSourceLimits.validate(_draft.source) == null;

  @override
  Widget build(BuildContext context) {
    final dialogWidth = AppResponsive.dialogWidth(context, preferred: 1120);
    final dialogHeight = AppResponsive.dialogHeight(context, preferred: 760);
    final tokens = context.appTokens;

    return UiDialog(
      semanticsLabel: 'Edit Mermaid source',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 1120,
        maxHeight: 760,
        minWidth: AppResponsive.dialogWidth(context, preferred: 360),
      ),
      builder: (context, style) => SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: UiSurface(
          padding: EdgeInsets.zero,
          color: tokens.panel,
          child: Column(
            children: [
              _buildHeader(tokens, style),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 720;
                    final editor = _buildEditor(tokens);
                    final preview = _buildPreview(tokens);
                    if (constraints.maxHeight < 360) {
                      return SingleChildScrollView(
                        child: Column(
                          children: [
                            SizedBox(height: 240, child: editor),
                            Divider(
                              height: AppBorder.thin,
                              color: tokens.panelBorder,
                            ),
                            SizedBox(height: 240, child: preview),
                          ],
                        ),
                      );
                    }
                    if (wide) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: editor),
                          VerticalDivider(
                            width: AppBorder.thin,
                            thickness: AppBorder.thin,
                            color: tokens.panelBorder,
                          ),
                          Expanded(child: preview),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        SizedBox(
                          height: constraints.maxHeight * 0.53,
                          child: editor,
                        ),
                        Divider(
                          height: AppBorder.thin,
                          color: tokens.panelBorder,
                        ),
                        Expanded(child: preview),
                      ],
                    );
                  },
                ),
              ),
              _buildFooter(tokens),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppTokens tokens, UiDialogStyle style) => Container(
    key: const ValueKey('mermaid-editor-header'),
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.md,
      AppSpacing.md,
    ),
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
      ),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final themeSelect = UiSelect<MermaidTheme>(
          key: const ValueKey('mermaid-theme-select'),
          label: 'Theme',
          items: {
            for (final theme in MermaidTheme.values) _themeLabel(theme): theme,
          },
          value: _draft.theme,
          onChanged: widget.readOnly ? (_) {} : _updateTheme,
          enabled: !widget.readOnly,
        );
        final directionSelect = UiSelect<String>(
          key: const ValueKey('mermaid-direction-select'),
          label: 'Direction',
          items: {
            'Auto': 'auto',
            for (final direction in MermaidDirection.values)
              direction.value: direction.value,
          },
          value: _draft.direction?.value ?? 'auto',
          onChanged: widget.readOnly ? (_) {} : _updateDirection,
          enabled: !widget.readOnly,
        );
        final closeButton = UiIconButton(
          icon: Icons.close,
          tooltip: 'Close Mermaid editor',
          onPressed: () => Navigator.of(context).pop(),
        );
        final title = Text(
          'Mermaid source',
          style: style.titleTextStyle.copyWith(color: tokens.text),
        );

        if (constraints.maxWidth < AppBreakpoints.compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    color: tokens.accent,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: title),
                  closeButton,
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: themeSelect),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: directionSelect),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Icon(Icons.account_tree_outlined, color: tokens.accent, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: title),
            SizedBox(width: 170, child: themeSelect),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(width: 120, child: directionSelect),
            const SizedBox(width: AppSpacing.sm),
            closeButton,
          ],
        );
      },
    ),
  );

  Widget _buildEditor(AppTokens tokens) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: UiTextField(
            key: const ValueKey('mermaid-source-field'),
            controller: _sourceController,
            label: 'Mermaid source',
            hint: 'flowchart TD\n  A[Start] --> B[End]',
            readOnly: widget.readOnly,
            enabled: true,
            expands: true,
            minLines: null,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            inputFormatters: [
              TextInputFormatter.withFunction((oldValue, newValue) {
                return utf8.encode(newValue.text).length <=
                        MermaidSourceLimits.maxSourceBytes
                    ? newValue
                    : oldValue;
              }),
            ],
            onChanged: widget.readOnly ? null : _onSourceChanged,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Text(
                '${utf8.encode(_draft.source).length} / ${MermaidSourceLimits.maxSourceBytes} bytes',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
              ),
            ),
            Text(
              '${_draft.source.split('\n').length} lines',
              style: Theme.of(
                context,
              ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
            ),
          ],
        ),
        if (_validationDiagnostic != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _DiagnosticBanner(diagnostic: _validationDiagnostic!),
        ],
      ],
    ),
  );

  Widget _buildPreview(AppTokens tokens) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Local preview',
          style: Theme.of(context).textTheme.titleSmall!.copyWith(
            color: tokens.text,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: DecoratedBox(
            key: const ValueKey('mermaid-editor-preview-frame'),
            decoration: BoxDecoration(
              color: tokens.canvas,
              border: Border.all(
                color: tokens.panelBorder,
                width: AppBorder.thin,
              ),
            ),
            child: MermaidNodePreview(
              key: ValueKey('mermaid-dialog-preview-${_draft.sourceRevision}'),
              payload: _draft,
              renderer: _renderer,
              onRenderStateChanged: _handleRenderState,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Preview is local and passive. Mermaid links and HTML labels stay disabled.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
        ),
      ],
    ),
  );

  Widget _buildFooter(AppTokens tokens) => Container(
    key: const ValueKey('mermaid-editor-footer'),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md - AppSpacing.xxs,
    ),
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
      ),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final status = Text(
          _validationDiagnostic == null
              ? 'Source is ready to preview.'
              : _validationDiagnostic!.message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: _validationDiagnostic == null
                ? tokens.textMuted
                : tokens.danger,
          ),
        );
        final actions = Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            UiButton(
              onPressed: () => Navigator.of(context).pop(),
              variant: UiButtonVariant.outline,
              size: UiButtonSize.sm,
              child: const Text('Cancel'),
            ),
            UiButton(
              key: const ValueKey('mermaid-save-source'),
              onPressed: widget.readOnly || !_canSave ? null : _save,
              size: UiButtonSize.sm,
              prefix: const Icon(Icons.check, size: 16),
              child: const Text('Save source'),
            ),
          ],
        );
        if (constraints.maxWidth < AppBreakpoints.compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              status,
              const SizedBox(height: AppSpacing.md - AppSpacing.xxs),
              actions,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: status),
            actions,
          ],
        );
      },
    ),
  );

  static String _themeLabel(MermaidTheme theme) {
    final label = theme.value.replaceAll('-', ' ');
    return label[0].toUpperCase() + label.substring(1);
  }
}

class _DiagnosticBanner extends StatelessWidget {
  final MermaidDiagnostic diagnostic;

  const _DiagnosticBanner({required this.diagnostic});

  @override
  Widget build(BuildContext context) {
    final location = diagnostic.line == null
        ? ''
        : 'Line ${diagnostic.line}${diagnostic.column == null ? '' : ', column ${diagnostic.column}'}: ';
    return Semantics(
      liveRegion: true,
      label: '$location${diagnostic.message}',
      child: UiAlert(
        key: const ValueKey('mermaid-editor-diagnostic'),
        title: 'Mermaid source diagnostic',
        description: '$location${diagnostic.message}',
        icon: Icons.error_outline,
        variant: UiAlertVariant.destructive,
      ),
    );
  }
}
