import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/data/artifacts/artifact_store_bundle.dart';
import 'package:varian/data/local/durable/project_session.dart';
import 'package:varian/features/import/import_service.dart';

class ImportSingleFlight {
  Future<void>? _active;

  bool get isActive => _active != null;

  Future<void> run(Future<void> Function() operation) {
    final active = _active;
    if (active != null) return active;
    final future = operation();
    _active = future.whenComplete(() => _active = null);
    return _active!;
  }
}

typedef ImportApplier = Future<void> Function(ImportResult result);

class ImportDialog extends ConsumerStatefulWidget {
  const ImportDialog({
    super.key,
    required this.projectId,
    required this.onImport,
    this.readOnly = false,
    this.session,
    this.sessionGeneration,
  });

  final String projectId;
  final bool readOnly;
  final ProjectSession? session;
  final int? sessionGeneration;
  final ImportApplier onImport;

  @override
  ConsumerState<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<ImportDialog> {
  int _tabIndex = 0;
  ImportResult? _pendingJsonResult;
  final _importSingleFlight = ImportSingleFlight();
  bool _isApplyingImport = false;

  final _mermaidController = TextEditingController(
    text: '''graph TD
A[Start Process] --> B{Verify Credentials}
B -->|Valid| C(Open Dashboard)
B -->|Invalid| D[Show Error]''',
  );
  final _drawioController = TextEditingController(
    text: '''<mxGraphModel>
  <root>
    <mxCell id="0"/>
    <mxCell id="1" parent="0"/>
    <mxCell id="2" value="Start Node" style="ellipse;whiteSpace=wrap;html=1;" vertex="1" parent="1">
      <mxGeometry x="120" y="80" width="120" height="60" as="geometry"/>
    </mxCell>
    <mxCell id="3" value="Decision" style="rhombus;whiteSpace=wrap;html=1;" vertex="1" parent="1">
      <mxGeometry x="320" y="70" width="140" height="80" as="geometry"/>
    </mxCell>
    <mxCell id="4" value="Approved" edge="1" parent="1" source="2" target="3">
      <mxGeometry relative="1" as="geometry"/>
    </mxCell>
  </root>
</mxGraphModel>''',
  );
  final _pumlController = TextEditingController(
    text: '''@startuml
start -> verify : Submit Form
verify -> success : Valid
@enduml''',
  );
  final _jsonController = TextEditingController();
  final _markdownController = TextEditingController(
    text: '# Creative Studio\n\nPaste Markdown content here.',
  );
  final _csvController = TextEditingController(
    text: 'Name,Status\nCanvas,Active\nExport,Pending',
  );
  final _svgController = TextEditingController(
    text:
        '<svg xmlns="http://www.w3.org/2000/svg" width="320" height="180"><rect width="320" height="180" fill="#7c3aed"/></svg>',
  );

  @override
  void dispose() {
    _mermaidController.dispose();
    _drawioController.dispose();
    _pumlController.dispose();
    _jsonController.dispose();
    _markdownController.dispose();
    _csvController.dispose();
    _svgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final width = AppResponsive.dialogWidth(context, preferred: 620);
    final height = AppResponsive.dialogHeight(context, preferred: 520);

    return UiDialog(
      semanticsLabel: 'Import diagram or document',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 620,
        maxHeight: 520,
      ),
      builder: (context, style) => SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.input_outlined, color: tokens.accent, size: 20),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'IMPORT DIAGRAM / DOCUMENT',
                      style: style.titleTextStyle,
                    ),
                  ),
                  UiIconButton(
                    icon: Icons.folder_open_outlined,
                    tooltip: 'Import file',
                    onPressed: _pickFile,
                  ),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close import dialog',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.page),
              Expanded(
                child: UiTabs(
                  index: _tabIndex,
                  onChanged: (index) => setState(() {
                    _tabIndex = index;
                    _pendingJsonResult = null;
                  }),
                  scrollable: true,
                  expands: true,
                  tabs: [
                    UiTabEntry(
                      label: const Text('MERMAID'),
                      child: _buildCodeEditor(
                        _mermaidController,
                        'Paste Mermaid flowchart syntax here...',
                        onChanged: (_) {
                          if (_pendingJsonResult != null) {
                            setState(() => _pendingJsonResult = null);
                          }
                        },
                      ),
                    ),
                    UiTabEntry(
                      label: const Text('DRAW.IO XML'),
                      child: _buildCodeEditor(
                        _drawioController,
                        'Paste Draw.io / mxGraphModel XML syntax here...',
                        onChanged: (_) {
                          if (_pendingJsonResult != null) {
                            setState(() => _pendingJsonResult = null);
                          }
                        },
                      ),
                    ),
                    UiTabEntry(
                      label: const Text('PLANTUML'),
                      child: _buildCodeEditor(
                        _pumlController,
                        'Paste PlantUML diagram syntax here...',
                        onChanged: (_) {
                          if (_pendingJsonResult != null) {
                            setState(() => _pendingJsonResult = null);
                          }
                        },
                      ),
                    ),
                    UiTabEntry(
                      label: const Text('CANVAS JSON'),
                      child: _buildCodeEditor(
                        _jsonController,
                        'Paste raw CanvasDocument JSON structure here...',
                        onChanged: (_) {
                          if (_pendingJsonResult != null) {
                            setState(() => _pendingJsonResult = null);
                          }
                        },
                      ),
                    ),
                    UiTabEntry(
                      label: const Text('MARKDOWN'),
                      child: _buildCodeEditor(
                        _markdownController,
                        'Paste Markdown content here...',
                        onChanged: (_) {
                          if (_pendingJsonResult != null) {
                            setState(() => _pendingJsonResult = null);
                          }
                        },
                      ),
                    ),
                    UiTabEntry(
                      label: const Text('CSV'),
                      child: _buildCodeEditor(
                        _csvController,
                        'Paste CSV data here...',
                        onChanged: (_) {
                          if (_pendingJsonResult != null) {
                            setState(() => _pendingJsonResult = null);
                          }
                        },
                      ),
                    ),
                    UiTabEntry(
                      label: const Text('SVG'),
                      child: _buildCodeEditor(
                        _svgController,
                        'Paste SVG markup here...',
                        onChanged: (_) {
                          if (_pendingJsonResult != null) {
                            setState(() => _pendingJsonResult = null);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (_pendingJsonResult case final preview?) ...[
                const SizedBox(height: AppSpacing.md - AppSpacing.xxs),
                _buildJsonPreview(preview),
              ],
              const SizedBox(height: AppSpacing.page),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  UiButton(
                    onPressed: () => Navigator.pop(context),
                    variant: UiButtonVariant.ghost,
                    child: const Text('Cancel'),
                  ),
                  UiButton(
                    onPressed: _isApplyingImport ? null : _handleImport,
                    prefix: const Icon(Icons.input_outlined),
                    child: Text(
                      _isApplyingImport
                          ? 'Importing…'
                          : _pendingJsonResult == null
                          ? 'Preview Import'
                          : 'Import Nodes',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCodeEditor(
    TextEditingController controller,
    String hint, {
    ValueChanged<String>? onChanged,
  }) {
    return UiTextField(
      controller: controller,
      hint: hint,
      onChanged: onChanged,
      expands: true,
      minLines: null,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
    );
  }

  void _handleImport() {
    if (_isApplyingImport ||
        widget.projectId.trim().isEmpty ||
        (widget.session != null &&
            widget.session!.projectId != widget.projectId)) {
      return;
    }
    if (widget.readOnly && _pendingJsonResult != null) {
      showUiToast(
        context,
        'Read-only projects cannot import content.',
        variant: UiToastVariant.error,
      );
      return;
    }
    final result = _pendingJsonResult ?? _parseCurrentTab();

    if (!result.isSuccess || result.nodes.isEmpty) {
      showUiToast(
        context,
        result.error ?? 'No valid nodes discovered to import.',
        variant: UiToastVariant.error,
      );
      return;
    }

    if (_pendingJsonResult == null) {
      setState(() => _pendingJsonResult = result);
      return;
    }

    setState(() => _isApplyingImport = true);
    unawaited(
      _importSingleFlight.run(() => _applyImport(result)).whenComplete(() {
        if (mounted) setState(() => _isApplyingImport = false);
      }),
    );
  }

  ImportResult _parseCurrentTab() {
    switch (_tabIndex) {
      case 0:
        return ImportService.importFromMermaid(_mermaidController.text.trim());
      case 1:
        return ImportService.importFromDrawioXml(_drawioController.text.trim());
      case 2:
        return ImportService.importFromPlantUml(_pumlController.text.trim());
      case 3:
        return ImportService.importFromJson(_jsonController.text.trim());
      case 4:
        return ImportService.importFromMarkdown(_markdownController.text);
      case 5:
        return ImportService.importFromCsv(_csvController.text);
      case 6:
        return ImportService.importFromSvg(_svgController.text);
      default:
        return ImportResult(error: 'Unsupported import format.');
    }
  }

  void _repairJsonPreview() {
    final result = ImportService.importFromJson(
      _jsonController.text.trim(),
      repair: true,
    );
    if (!result.isSuccess || result.nodes.isEmpty) {
      showUiToast(
        context,
        result.error ?? 'Package repair did not produce importable nodes.',
        variant: UiToastVariant.error,
      );
      return;
    }
    setState(() => _pendingJsonResult = result);
  }

  Future<void> _pickFile() async {
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      final result = ImportService.importFromFileBytes(
        fileName: file.name,
        bytes: bytes,
      );
      if (!result.isSuccess || result.nodes.isEmpty) {
        if (mounted) {
          showUiToast(
            context,
            result.error ?? 'Selected file has no importable content.',
            variant: UiToastVariant.error,
          );
        }
        return;
      }
      if (mounted) {
        setState(() => _pendingJsonResult = result);
      }
    } catch (error) {
      if (!mounted) return;
      showUiToast(
        context,
        'Failed to read ${file.name}: $error',
        variant: UiToastVariant.error,
      );
    }
  }

  Widget _buildJsonPreview(ImportResult result) {
    final report = result.packageHealth;
    final issues = report?.issues ?? const [];
    final issueText = issues.isEmpty
        ? 'No package issues detected.'
        : issues.take(3).map((issue) => '• ${issue.message}').join('\n');
    final migration = result.migrationPreview;
    final lossMessages = result.lossReport?.messages ?? const <String>[];
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: AppResponsive.dialogHeight(context, preferred: 104),
      ),
      child: UiSurface(
        color: context.appTokens.accentSoft.withValues(alpha: 0.25),
        padding: const EdgeInsets.all(AppSpacing.md),
        borderRadius: BorderRadius.circular(context.appTokens.controlRadius),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'IMPORT PREVIEW',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.appTokens.textMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${result.nodes.length} node(s) • ${result.edges.length} edge(s) • ${result.assets.items.length} asset(s)',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (migration != null)
                Text(
                  migration.error == null
                      ? 'Schema ${migration.sourceVersion ?? '?'} → ${migration.targetVersion ?? '?'}'
                      : 'Migration unavailable: ${migration.error}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (report != null)
                Text(
                  'Checksum ${report.checksum.substring(0, 16)}… • ${report.isHealthy ? 'healthy' : 'review issues'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              for (final message in lossMessages.take(3))
                Text(message, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (result.repairResult case final repair?) ...[
                Text(
                  repair.changed
                      ? 'Repair applied: ${repair.actions.length} action(s).'
                      : 'No repair changes were needed.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ] else if (report?.canRepair == true)
                Align(
                  alignment: Alignment.centerLeft,
                  child: UiButton(
                    onPressed: _repairJsonPreview,
                    variant: UiButtonVariant.ghost,
                    prefix: const Icon(Icons.build_outlined, size: 15),
                    child: const Text('Repair package'),
                  ),
                ),
              Text(issueText, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applyImport(ImportResult result) async {
    try {
      final session = widget.session;
      if (widget.readOnly ||
          widget.projectId.trim().isEmpty ||
          (session != null &&
              (session.projectId != widget.projectId ||
                  session.isDisposed ||
                  (widget.sessionGeneration != null &&
                      session.generation != widget.sessionGeneration)))) {
        throw StateError('Import ownership is no longer active.');
      }
      final artifactStores = ref.read(artifactStoreBundleProvider);
      final materialized = await result.materializeArtifacts(
        artifactStoreBundle: artifactStores,
      );
      if (!mounted) return;
      final pendingFailures =
          materialized.transientAssetBytes.length +
          materialized.transientPayloadBytes.length +
          materialized.transientMediaArtifactBytes.length;
      if (pendingFailures > 0) {
        showUiToast(
          context,
          'Some imported files are unavailable. Retry materialization before importing.',
          variant: UiToastVariant.error,
        );
        return;
      }
      if (materialized.nodes.any((node) => node.id.trim().isEmpty)) {
        throw const FormatException(
          'Import contains an invalid node identity.',
        );
      }
      final currentSession = widget.session;
      if (currentSession != null &&
          (currentSession.isDisposed ||
              currentSession.projectId != widget.projectId ||
              (widget.sessionGeneration != null &&
                  currentSession.generation != widget.sessionGeneration))) {
        throw StateError('Import ownership is no longer active.');
      }
      await widget.onImport(materialized);
      if (!mounted) return;
      Navigator.pop(context);
      showUiToast(
        context,
        'Imported ${materialized.nodes.length} nodes & ${materialized.edges.length} edges successfully.',
        variant: UiToastVariant.success,
      );
    } catch (error) {
      if (mounted) {
        showUiToast(
          context,
          'Import failed: $error',
          variant: UiToastVariant.error,
        );
      }
    }
  }
}
