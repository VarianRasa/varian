import 'dart:convert';
import 'dart:math' as math;
import 'package:varian/app/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/document/utils/document_paper_presets.dart';
import 'package:varian/features/document/utils/quill_document_adapter.dart';

class DocumentEditorScreen extends StatefulWidget {
  final DocumentPayload initialPayload;
  final void Function(DocumentPayload updatedPayload)? onSave;
  final void Function(DocumentPayload updatedPayload) onSaveAndExit;

  const DocumentEditorScreen({
    super.key,
    required this.initialPayload,
    this.onSave,
    required this.onSaveAndExit,
  });

  @override
  State<DocumentEditorScreen> createState() => _DocumentEditorScreenState();
}

class _DocumentEditorScreenState extends State<DocumentEditorScreen> {
  late final TextEditingController _titleController;
  late final quill.QuillController _controller;
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  // Paper & Layout settings
  late String _selectedPaperPresetId;
  late bool _isLandscape;
  late String _selectedThemeId;
  late double _marginPreset;

  // Zoom
  double _zoomScale = 1.0;
  static const List<double> _zoomLevels = [
    0.5,
    0.75,
    0.9,
    1.0,
    1.1,
    1.25,
    1.5,
    1.75,
    2.0,
  ];

  int _wordCount = 0;
  int _characterCount = 0;
  bool _hasUnsavedChanges = false;
  String _saveFeedback = 'ALL CHANGES SAVED';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialPayload.title);
    _controller = quill.QuillController(
      document: QuillDocumentAdapter.toQuillDocument(widget.initialPayload),
      selection: const TextSelection.collapsed(offset: 0),
    );

    _selectedPaperPresetId = widget.initialPayload.paperPresetId;
    _isLandscape = widget.initialPayload.isLandscape;
    _selectedThemeId = widget.initialPayload.themeId;
    _marginPreset = widget.initialPayload.marginPreset;

    _titleController.addListener(_onChanged);
    _controller.addListener(_onChanged);
    _updateStatistics();
  }

  @override
  void dispose() {
    _titleController
      ..removeListener(_onChanged)
      ..dispose();
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _onChanged() {
    _updateStatistics();
    if (!_hasUnsavedChanges && mounted) {
      setState(() {
        _hasUnsavedChanges = true;
        _saveFeedback = 'UNSAVED CHANGES';
      });
    }
  }

  void _updateStatistics() {
    final text = _controller.document.toPlainText().trim();
    final words = text.isEmpty
        ? 0
        : text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
    if (mounted) {
      setState(() {
        _wordCount = words;
        _characterCount = text.length;
      });
    }
  }

  DocumentPayload _buildCurrentPayload() {
    String docTitle = _titleController.text.trim();
    final plainText = _controller.document.toPlainText().trim();
    if (docTitle.isEmpty || docTitle == 'Untitled Document') {
      final firstLine = plainText
          .split('\n')
          .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
      if (firstLine.isNotEmpty) {
        docTitle = firstLine.length > 50
            ? '${firstLine.substring(0, 47)}...'
            : firstLine;
      } else {
        docTitle = 'Untitled Document';
      }
    }

    final theme = DocumentThemeCatalog.findById(_selectedThemeId);

    final payload =
        QuillDocumentAdapter.fromQuillDocument(
          title: docTitle,
          document: _controller.document,
        ).copyWith(
          paperPresetId: _selectedPaperPresetId,
          isLandscape: _isLandscape,
          themeId: _selectedThemeId,
          marginPreset: _marginPreset,
          backgroundColor: theme.backgroundColor,
          borderColor: theme.borderColor,
        );

    return payload;
  }

  void _saveQuick() {
    setState(() => _isSaving = true);
    final payload = _buildCurrentPayload();
    if (widget.onSave != null) {
      widget.onSave!(payload);
    } else {
      widget.onSaveAndExit(payload);
    }

    if (mounted) {
      setState(() {
        _hasUnsavedChanges = false;
        _saveFeedback = 'ALL CHANGES SAVED';
        _isSaving = false;
      });
      showUiToast(
        context,
        'Document saved successfully',
        variant: UiToastVariant.success,
        duration: const Duration(seconds: 2),
      );
    }
  }

  void _saveAndExit() {
    final payload = _buildCurrentPayload();
    widget.onSaveAndExit(payload);
    Navigator.of(context).pop();
  }

  void _setZoom(double nextZoom) {
    setState(() {
      _zoomScale = nextZoom.clamp(0.4, 2.5);
    });
  }

  void _zoomIn() {
    final currentIdx = _zoomLevels.indexWhere((z) => z >= _zoomScale - 0.01);
    if (currentIdx != -1 && currentIdx < _zoomLevels.length - 1) {
      _setZoom(_zoomLevels[currentIdx + 1]);
    } else {
      _setZoom(_zoomScale + 0.15);
    }
  }

  void _zoomOut() {
    final currentIdx = _zoomLevels.lastIndexWhere(
      (z) => z <= _zoomScale + 0.01,
    );
    if (currentIdx > 0) {
      _setZoom(_zoomLevels[currentIdx - 1]);
    } else {
      _setZoom(_zoomScale - 0.15);
    }
  }

  void _showPaperSettingsDialog() {
    showUiDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final tokens = context.appTokens;
          final dialogWidth = AppResponsive.dialogWidth(
            context,
            preferred: 440,
          );
          final dialogHeight = AppResponsive.dialogHeight(
            context,
            preferred: 640,
          );
          return UiDialog(
            constraints: AppResponsive.dialogConstraints(
              context,
              maxWidth: 440,
              maxHeight: 640,
            ),
            builder: (context, style) => SizedBox(
              width: dialogWidth,
              height: dialogHeight,
              child: SingleChildScrollView(
                padding: AppResponsive.dialogPadding(context),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.aspect_ratio_outlined,
                          color: tokens.accent,
                          size: 18,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'PAGE & PAPER SETTINGS',
                            overflow: TextOverflow.ellipsis,
                            style: style.titleTextStyle.copyWith(
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Paper Size Template',
                          style: Theme.of(context).textTheme.labelMedium!
                              .copyWith(
                                color: tokens.textMuted,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        DecoratedBox(
                          key: const ValueKey('document-paper-preset-list'),
                          decoration: BoxDecoration(
                            color: tokens.panelElevated,
                            borderRadius: BorderRadius.circular(
                              tokens.controlRadius,
                            ),
                            border: Border.all(
                              color: tokens.panelBorder,
                              width: AppBorder.thin,
                            ),
                          ),
                          child: SizedBox(
                            height: 180,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.xs,
                              ),
                              itemCount: DocumentPaperCatalog.presets.length,
                              separatorBuilder: (_, _) => Divider(
                                color: tokens.panelBorder,
                                height: AppBorder.thin,
                              ),
                              itemBuilder: (ctx, idx) {
                                final preset =
                                    DocumentPaperCatalog.presets[idx];
                                final isSelected =
                                    preset.id == _selectedPaperPresetId;
                                return UiButton(
                                  onPressed: () {
                                    setDialogState(
                                      () => _selectedPaperPresetId = preset.id,
                                    );
                                    setState(() {
                                      _selectedPaperPresetId = preset.id;
                                      _hasUnsavedChanges = true;
                                    });
                                  },
                                  variant: isSelected
                                      ? UiButtonVariant.primary
                                      : UiButtonVariant.ghost,
                                  prefix: Icon(
                                    preset.icon,
                                    size: 18,
                                    color: isSelected
                                        ? tokens.accentForeground
                                        : tokens.textMuted,
                                  ),
                                  suffix: isSelected
                                      ? Icon(
                                          Icons.check,
                                          size: 16,
                                          color: tokens.accentForeground,
                                        )
                                      : null,
                                  child: Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          preset.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall!
                                              .copyWith(
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                color: isSelected
                                                    ? tokens.accentForeground
                                                    : tokens.text,
                                              ),
                                        ),
                                        Text(
                                          preset.description,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall!
                                              .copyWith(
                                                color: isSelected
                                                    ? tokens.accentForeground
                                                          .withValues(
                                                            alpha: 0.72,
                                                          )
                                                    : tokens.textMuted,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'Orientation',
                          style: Theme.of(context).textTheme.labelMedium!
                              .copyWith(
                                color: tokens.textMuted,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: UiButton(
                                onPressed: () {
                                  setDialogState(() => _isLandscape = false);
                                  setState(() {
                                    _isLandscape = false;
                                    _hasUnsavedChanges = true;
                                  });
                                },
                                variant: !_isLandscape
                                    ? UiButtonVariant.primary
                                    : UiButtonVariant.outline,
                                prefix: const Icon(
                                  Icons.crop_portrait,
                                  size: 16,
                                ),
                                child: const Text('Portrait'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: UiButton(
                                onPressed: () {
                                  setDialogState(() => _isLandscape = true);
                                  setState(() {
                                    _isLandscape = true;
                                    _hasUnsavedChanges = true;
                                  });
                                },
                                variant: _isLandscape
                                    ? UiButtonVariant.primary
                                    : UiButtonVariant.outline,
                                prefix: const Icon(
                                  Icons.crop_landscape,
                                  size: 16,
                                ),
                                child: const Text('Landscape'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'Margin Preset',
                          style: Theme.of(context).textTheme.labelMedium!
                              .copyWith(
                                color: tokens.textMuted,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Wrap(
                          spacing: AppSpacing.sm,
                          children: [
                            _buildMarginOption(
                              label: 'Compact (32pt)',
                              value: 32.0,
                              setDialogState: setDialogState,
                            ),
                            _buildMarginOption(
                              label: 'Normal (64pt)',
                              value: 64.0,
                              setDialogState: setDialogState,
                            ),
                            _buildMarginOption(
                              label: 'Wide (96pt)',
                              value: 96.0,
                              setDialogState: setDialogState,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Align(
                      alignment: Alignment.centerRight,
                      child: UiButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        variant: UiButtonVariant.ghost,
                        child: const Text('DONE'),
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

  Widget _buildMarginOption({
    required String label,
    required double value,
    required void Function(void Function()) setDialogState,
  }) {
    final isSelected = (_marginPreset - value).abs() < 1.0;
    return UiButton(
      onPressed: () {
        setDialogState(() => _marginPreset = value);
        setState(() {
          _marginPreset = value;
          _hasUnsavedChanges = true;
        });
      },
      variant: isSelected ? UiButtonVariant.primary : UiButtonVariant.outline,
      child: Text(label),
    );
  }

  void _showThemesMenu(BuildContext context) {
    final maxHeight =
        (AppResponsive.dialogHeight(context, preferred: 560) -
                MediaQuery.viewInsetsOf(context).vertical)
            .clamp(0.0, 560.0)
            .toDouble();
    final height = math.min(maxHeight, 328.0);
    showUiDialog<String>(
      context: context,
      builder: (dialogContext) {
        final tokens = dialogContext.appTokens;
        return UiDialog(
          semanticsLabel: 'Paper tone and theme',
          constraints: AppResponsive.dialogConstraints(
            context,
            maxWidth: 420,
            maxHeight: maxHeight,
          ),
          builder: (context, style) => SizedBox(
            height: height,
            child: SingleChildScrollView(
              padding: AppResponsive.dialogPadding(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.palette_outlined,
                        color: tokens.accent,
                        size: 18,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'PAPER TONE / THEME',
                        style: style.titleTextStyle.copyWith(
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: math.min(280.0, math.max(0.0, height - 100)),
                    child: ListView.separated(
                      itemCount: DocumentThemeCatalog.themes.length,
                      separatorBuilder: (_, _) => const SizedBox(
                        height: AppSpacing.xs + AppSpacing.xxs,
                      ),
                      itemBuilder: (context, index) {
                        final theme = DocumentThemeCatalog.themes[index];
                        final isSelected = theme.id == _selectedThemeId;
                        return UiButton(
                          onPressed: () =>
                              Navigator.pop(dialogContext, theme.id),
                          variant: isSelected
                              ? UiButtonVariant.primary
                              : UiButtonVariant.outline,
                          prefix: DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.backgroundColor,
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(color: theme.borderColor),
                            ),
                            child: const SizedBox(width: 18, height: 18),
                          ),
                          suffix: isSelected
                              ? const Icon(Icons.check, size: 16)
                              : null,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(theme.name),
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
                      child: const Text('CANCEL'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((themeId) {
      if (themeId != null && themeId != _selectedThemeId && mounted) {
        setState(() {
          _selectedThemeId = themeId;
          _hasUnsavedChanges = true;
        });
      }
    });
  }

  void _showExportMenu(BuildContext context) {
    final plainText = _controller.document.toPlainText();
    final jsonString = jsonEncode(_controller.document.toDelta().toJson());
    final maxHeight =
        (AppResponsive.dialogHeight(context, preferred: 560) -
                MediaQuery.viewInsetsOf(context).vertical)
            .clamp(0.0, 560.0)
            .toDouble();

    showUiDialog<void>(
      context: context,
      builder: (dialogContext) {
        final tokens = dialogContext.appTokens;
        void copyAndClose(String value, String message) {
          Clipboard.setData(ClipboardData(text: value));
          Navigator.pop(dialogContext);
          showUiToast(context, message, variant: UiToastVariant.success);
        }

        Widget exportOption({
          required IconData icon,
          required Color color,
          required String title,
          required String subtitle,
          required VoidCallback onPressed,
        }) => UiButton(
          onPressed: onPressed,
          variant: UiButtonVariant.outline,
          prefix: Icon(icon, color: color, size: 18),
          child: Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
        );

        return UiDialog(
          semanticsLabel: 'Export document',
          constraints: AppResponsive.dialogConstraints(
            context,
            maxWidth: 440,
            maxHeight: maxHeight,
          ),
          builder: (context, style) => SingleChildScrollView(
            padding: AppResponsive.dialogPadding(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.ios_share_outlined,
                      color: tokens.accent,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'EXPORT DOCUMENT',
                      style: style.titleTextStyle.copyWith(letterSpacing: 1.0),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
                exportOption(
                  icon: Icons.copy_outlined,
                  color: tokens.accent,
                  title: 'Copy Plain Text to Clipboard',
                  subtitle: 'Standard unformatted text',
                  onPressed: () => copyAndClose(
                    plainText,
                    'Plain text copied to clipboard!',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                exportOption(
                  icon: Icons.code_outlined,
                  color: tokens.info,
                  title: 'Copy Delta JSON',
                  subtitle: 'Rich text structure and formatting ops',
                  onPressed: () => copyAndClose(
                    jsonString,
                    'Delta JSON copied to clipboard!',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                exportOption(
                  icon: Icons.description_outlined,
                  color: tokens.success,
                  title: 'Export as Markdown (.md)',
                  subtitle: 'Formatted headers, quotes, lists',
                  onPressed: () => copyAndClose(
                    plainText,
                    'Markdown text copied to clipboard!',
                  ),
                ),
                const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
                Align(
                  alignment: Alignment.centerRight,
                  child: UiButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    variant: UiButtonVariant.ghost,
                    child: const Text('CANCEL'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirmExit() async {
    if (!_hasUnsavedChanges) return true;
    final shouldDiscard = await showUiDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final tokens = dialogContext.appTokens;
        return UiDialog(
          builder: (context, style) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Discard unsaved changes?', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.md),
              Text(
                'The latest document changes have not been saved.',
                style: TextStyle(color: tokens.textMuted),
              ),
              const SizedBox(height: AppSpacing.pageWide),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  UiButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    variant: UiButtonVariant.ghost,
                    child: const Text('Keep editing'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  UiButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    variant: UiButtonVariant.destructive,
                    child: const Text('Discard'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    return shouldDiscard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      autofocus: true,
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS):
            const _QuickSaveIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyS):
            const _QuickSaveIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.equal):
            const _ZoomInIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.minus):
            const _ZoomOutIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.digit0):
            const _ZoomResetIntent(),
      },
      actions: <Type, Action<Intent>>{
        _QuickSaveIntent: CallbackAction<_QuickSaveIntent>(
          onInvoke: (_) => _saveQuick(),
        ),
        _ZoomInIntent: CallbackAction<_ZoomInIntent>(
          onInvoke: (_) => _zoomIn(),
        ),
        _ZoomOutIntent: CallbackAction<_ZoomOutIntent>(
          onInvoke: (_) => _zoomOut(),
        ),
        _ZoomResetIntent: CallbackAction<_ZoomResetIntent>(
          onInvoke: (_) => _setZoom(1.0),
        ),
      },
      child: PopScope(
        canPop: !_hasUnsavedChanges,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop || !await _confirmExit() || !context.mounted) return;
          Navigator.of(context).pop();
        },
        child: Builder(
          builder: (context) {
            final tokens = context.appTokens;
            final materialTheme = Theme.of(context);
            return Theme(
              data: materialTheme.copyWith(
                scaffoldBackgroundColor: tokens.canvas,
                colorScheme: materialTheme.colorScheme.copyWith(
                  brightness: materialTheme.brightness,
                  primary: tokens.accent,
                ),
                textSelectionTheme: TextSelectionThemeData(
                  cursorColor: tokens.accent,
                  selectionColor: tokens.accent.withValues(alpha: 0.24),
                  selectionHandleColor: tokens.accent,
                ),
              ),
              child: UiPageScaffold(
                title: _buildHeaderTitle(),
                leading: UiIconButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                actions: _buildHeaderActions(),
                child: Column(
                  children: [
                    _buildToolbar(),
                    Expanded(child: _buildEditorViewport()),
                    _buildStatusBar(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeaderTitle() {
    final tokens = context.appTokens;
    return Row(
      children: [
        Icon(Icons.description_outlined, color: tokens.accent, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: UiTextField(
            controller: _titleController,
            hint: 'Untitled Document',
          ),
        ),
      ],
    );
  }

  List<Widget> _buildHeaderActions() {
    final compact = AppResponsive.isNarrow(context);

    if (compact) {
      return [
        UiIconButton(
          icon: Icons.save_outlined,
          tooltip: 'Save',
          onPressed: _isSaving ? null : _saveQuick,
          variant: UiButtonVariant.outline,
        ),
        UiIconButton(
          icon: Icons.check,
          tooltip: 'Save and close',
          onPressed: _saveAndExit,
          variant: UiButtonVariant.primary,
        ),
        UiIconButton(
          icon: Icons.aspect_ratio_outlined,
          tooltip: 'Page and paper settings',
          onPressed: _showPaperSettingsDialog,
        ),
        UiIconButton(
          icon: Icons.palette_outlined,
          tooltip: 'Paper Tone / Theme',
          onPressed: () => _showThemesMenu(context),
        ),
        UiIconButton(
          icon: Icons.ios_share_outlined,
          tooltip: 'Export Document',
          onPressed: () => _showExportMenu(context),
        ),
      ];
    }

    final buttonLabelStyle = Theme.of(
      context,
    ).textTheme.labelSmall!.copyWith(fontWeight: FontWeight.bold);
    return [
      UiButton(
        onPressed: _showPaperSettingsDialog,
        variant: UiButtonVariant.outline,
        size: UiButtonSize.sm,
        prefix: Icon(
          DocumentPaperCatalog.findById(_selectedPaperPresetId).icon,
          size: 13,
        ),
        child: Text(
          '${DocumentPaperCatalog.findById(_selectedPaperPresetId).name} (${_isLandscape ? "L" : "P"})',
          style: buttonLabelStyle.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      UiIconButton(
        icon: Icons.palette_outlined,
        tooltip: 'Paper Tone / Theme',
        size: UiButtonSize.sm,
        onPressed: () => _showThemesMenu(context),
      ),
      UiIconButton(
        icon: Icons.ios_share_outlined,
        tooltip: 'Export Document',
        size: UiButtonSize.sm,
        onPressed: () => _showExportMenu(context),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: UiButton(
          onPressed: _isSaving ? null : _saveQuick,
          variant: UiButtonVariant.outline,
          size: UiButtonSize.sm,
          prefix: const Icon(Icons.save_outlined, size: 15),
          child: Text('SAVE', style: buttonLabelStyle),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: UiButton(
          onPressed: _saveAndExit,
          variant: UiButtonVariant.primary,
          size: UiButtonSize.sm,
          prefix: const Icon(Icons.check, size: 16),
          child: Text('SAVE & CLOSE', style: buttonLabelStyle),
        ),
      ),
    ];
  }

  Widget _buildToolbar() {
    final tokens = context.appTokens;
    return UiSurface(
      color: tokens.panelElevated,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.zero,
      child: Row(
        children: [
          Expanded(
            child: quill.QuillSimpleToolbar(
              controller: _controller,
              config: quill.QuillSimpleToolbarConfig(
                multiRowsDisplay: false,
                toolbarSize: AppControlSize.extraSmall,
                color: tokens.panelElevated,
                sectionDividerColor: tokens.panelBorder,
                showFontFamily: false,
                showFontSize: false,
                showSubscript: false,
                showSuperscript: false,
                showAlignmentButtons: true,
                showDirection: false,
                showSearchButton: false,
                iconTheme: quill.QuillIconTheme(
                  iconButtonUnselectedData: quill.IconButtonData(
                    color: tokens.textMuted,
                    hoverColor: tokens.accentSoft,
                  ),
                  iconButtonSelectedData: quill.IconButtonData(
                    color: tokens.accent,
                    hoverColor: tokens.accentSoft,
                  ),
                ),
                decoration: BoxDecoration(color: tokens.panelElevated),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs + AppSpacing.xxs,
              vertical: AppSpacing.xxs,
            ),
            child: UiSurface(
              color: tokens.panel,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              borderRadius: BorderRadius.circular(tokens.controlRadius),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UiIconButton(
                    icon: Icons.remove,
                    tooltip: 'Zoom Out (Ctrl -)',
                    size: UiButtonSize.sm,
                    onPressed: _zoomOut,
                  ),
                  UiButton(
                    onPressed: () => _setZoom(1.0),
                    variant: UiButtonVariant.ghost,
                    size: UiButtonSize.sm,
                    child: Text(
                      '${(_zoomScale * 100).round()}%',
                      style: Theme.of(context).textTheme.labelSmall!.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.add,
                    tooltip: 'Zoom In (Ctrl +)',
                    size: UiButtonSize.sm,
                    onPressed: _zoomIn,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorViewport() {
    final preset = DocumentPaperCatalog.findById(_selectedPaperPresetId);
    final targetWidth = preset.getEffectiveWidth(_isLandscape);
    final targetHeight = preset.getEffectiveHeight(_isLandscape);
    final theme = DocumentThemeCatalog.findById(_selectedThemeId);
    final tokens = context.appTokens;

    return Container(
      color: tokens.canvas,
      alignment: Alignment.topCenter,
      child: Scrollbar(
        controller: _horizontalScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _horizontalScrollController,
          scrollDirection: Axis.horizontal,
          child: Scrollbar(
            controller: _editorScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _editorScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
              child: Transform.scale(
                scale: _zoomScale,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: targetWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.backgroundColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: theme.borderColor),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x66000000),
                          blurRadius: 28,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: targetHeight),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (!_editorFocusNode.hasFocus) {
                            _editorFocusNode.requestFocus();
                            _controller.moveCursorToEnd();
                          }
                        },
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            _marginPreset,
                            48,
                            _marginPreset,
                            72,
                          ),
                          child: quill.QuillEditor(
                            controller: _controller,
                            focusNode: _editorFocusNode,
                            scrollController: _editorScrollController,
                            config: quill.QuillEditorConfig(
                              autoFocus: true,
                              expands: false,
                              scrollable: false,
                              padding: EdgeInsets.zero,
                              placeholder: 'Start writing your document…',
                              maxContentWidth:
                                  targetWidth - (_marginPreset * 2),
                              customStyles: _getEditorStyles(theme),
                              textSelectionThemeData: TextSelectionThemeData(
                                cursorColor: tokens.accent,
                                selectionColor: tokens.accent.withValues(
                                  alpha: 0.22,
                                ),
                                selectionHandleColor: tokens.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  quill.DefaultStyles _getEditorStyles(DocumentThemePreset theme) {
    const zeroHorizontal = quill.HorizontalSpacing(0, 0);
    const zeroVertical = quill.VerticalSpacing(0, 0);
    final paragraph = TextStyle(
      color: theme.subTextColor,
      fontSize: 16,
      height: 1.55,
    );

    return quill.DefaultStyles(
      paragraph: quill.DefaultTextBlockStyle(
        paragraph,
        zeroHorizontal,
        const quill.VerticalSpacing(4, 4),
        zeroVertical,
        null,
      ),
      h1: quill.DefaultTextBlockStyle(
        TextStyle(
          color: theme.textColor,
          fontSize: 30,
          height: 1.2,
          fontWeight: FontWeight.w800,
        ),
        zeroHorizontal,
        const quill.VerticalSpacing(18, 8),
        zeroVertical,
        null,
      ),
      h2: quill.DefaultTextBlockStyle(
        TextStyle(
          color: theme.textColor,
          fontSize: 24,
          height: 1.25,
          fontWeight: FontWeight.w700,
        ),
        zeroHorizontal,
        const quill.VerticalSpacing(14, 6),
        zeroVertical,
        null,
      ),
      h3: quill.DefaultTextBlockStyle(
        TextStyle(
          color: theme.textColor,
          fontSize: 20,
          height: 1.3,
          fontWeight: FontWeight.w700,
        ),
        zeroHorizontal,
        const quill.VerticalSpacing(12, 4),
        zeroVertical,
        null,
      ),
      lists: quill.DefaultListBlockStyle(
        paragraph,
        zeroHorizontal,
        const quill.VerticalSpacing(3, 3),
        zeroVertical,
        null,
        null,
      ),
      quote: quill.DefaultTextBlockStyle(
        TextStyle(
          color: theme.subTextColor,
          fontSize: 16,
          height: 1.5,
          fontStyle: FontStyle.italic,
        ),
        const quill.HorizontalSpacing(14, 0),
        const quill.VerticalSpacing(8, 8),
        zeroVertical,
        const BoxDecoration(
          border: Border(
            left: BorderSide(color: AppTheme.braunOrange, width: 3),
          ),
        ),
      ),
      code: quill.DefaultTextBlockStyle(
        const TextStyle(
          color: Color(0xFFE5E7EB),
          fontSize: 14,
          height: 1.45,
          fontFamily: 'monospace',
        ),
        const quill.HorizontalSpacing(12, 12),
        const quill.VerticalSpacing(10, 10),
        zeroVertical,
        BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      link: const TextStyle(
        color: Color(0xFF2563EB),
        decoration: TextDecoration.underline,
      ),
      placeHolder: const quill.DefaultTextBlockStyle(
        TextStyle(color: Color(0xFF9CA3AF), fontSize: 16, height: 1.55),
        zeroHorizontal,
        zeroVertical,
        zeroVertical,
        null,
      ),
      inlineCode: quill.InlineCodeStyle(
        style: const TextStyle(
          color: Color(0xFFEA580C),
          fontSize: 14,
          fontFamily: 'monospace',
        ),
        backgroundColor: const Color(0xFFFFF7ED),
        radius: const Radius.circular(3),
      ),
    );
  }

  Widget _buildStatusBar() {
    final readingTimeMinutes = (_wordCount / 200).ceil();
    final tokens = context.appTokens;
    final statusColor = _hasUnsavedChanges ? tokens.warning : tokens.success;
    final statusTextStyle = Theme.of(context).textTheme.labelSmall!.copyWith(
      color: tokens.textMuted,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.7,
    );
    final compact = AppResponsive.isNarrow(context);
    final saveStatus = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _hasUnsavedChanges ? Icons.circle : Icons.cloud_done_outlined,
          size: _hasUnsavedChanges ? 7 : 13,
          color: statusColor,
        ),
        const SizedBox(width: 7),
        Text(_saveFeedback, style: statusTextStyle),
      ],
    );
    final documentStats = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$_wordCount WORDS', style: statusTextStyle),
        const SizedBox(width: AppSpacing.md + AppSpacing.xxs),
        Text('$_characterCount CHARS', style: statusTextStyle),
        const SizedBox(width: AppSpacing.md + AppSpacing.xxs),
        Text('~$readingTimeMinutes MIN READ', style: statusTextStyle),
      ],
    );
    return UiSurface(
      color: tokens.panel,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      borderRadius: BorderRadius.zero,
      child: SizedBox(
        height: 30,
        child: compact
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    saveStatus,
                    const SizedBox(width: AppSpacing.lg),
                    documentStats,
                  ],
                ),
              )
            : Row(children: [saveStatus, const Spacer(), documentStats]),
      ),
    );
  }
}

class _QuickSaveIntent extends Intent {
  const _QuickSaveIntent();
}

class _ZoomInIntent extends Intent {
  const _ZoomInIntent();
}

class _ZoomOutIntent extends Intent {
  const _ZoomOutIntent();
}

class _ZoomResetIntent extends Intent {
  const _ZoomResetIntent();
}
