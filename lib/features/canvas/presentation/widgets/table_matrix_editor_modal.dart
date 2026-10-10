import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/app/responsive.dart';
import '../../../../domain/models/node.dart';
import '../../../../domain/models/node_payload.dart';

class TableMatrixEditorModal extends StatefulWidget {
  final CanvasNode node;
  final ValueChanged<CanvasNode> onUpdate;

  const TableMatrixEditorModal({
    super.key,
    required this.node,
    required this.onUpdate,
  });

  static Future<void> show(
    BuildContext context, {
    required CanvasNode node,
    required ValueChanged<CanvasNode> onUpdate,
  }) {
    return showUiDialog<void>(
      context: context,
      builder: (context) =>
          TableMatrixEditorModal(node: node, onUpdate: onUpdate),
    );
  }

  @override
  State<TableMatrixEditorModal> createState() => _TableMatrixEditorModalState();
}

class _TableMatrixEditorModalState extends State<TableMatrixEditorModal> {
  late TablePayload _payload;
  late TextEditingController _titleController;
  late List<String> _columns;
  late List<List<String>> _rows;
  late List<TableCellType> _columnTypes;
  final Map<String, TextEditingController> _cellControllers = {};
  final Map<int, TextEditingController> _columnControllers = {};

  TextEditingController _cellController(
    int rowIndex,
    int colIndex,
    String value,
  ) {
    final key = '$rowIndex:$colIndex';
    final controller = _cellControllers.putIfAbsent(
      key,
      () => TextEditingController(text: value),
    );
    if (controller.text != value && !controller.value.composing.isValid) {
      controller.value = controller.value.copyWith(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
        composing: TextRange.empty,
      );
    }
    return controller;
  }

  TextEditingController _columnController(int colIndex, String value) {
    final controller = _columnControllers.putIfAbsent(
      colIndex,
      () => TextEditingController(text: value),
    );
    if (controller.text != value && !controller.value.composing.isValid) {
      controller.value = controller.value.copyWith(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
        composing: TextRange.empty,
      );
    }
    return controller;
  }

  @override
  void initState() {
    super.initState();
    _payload = widget.node.payload is TablePayload
        ? widget.node.payload as TablePayload
        : TablePayload();
    _titleController = TextEditingController(text: _payload.name);
    _columns = List<String>.from(_payload.columns);
    _rows = _payload.rows.map((r) => List<String>.from(r)).toList();
    _columnTypes = List<TableCellType>.from(_payload.columnTypes);
    while (_columnTypes.length < _columns.length) {
      _columnTypes.add(TableCellType.text);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final controller in _cellControllers.values) {
      controller.dispose();
    }
    for (final controller in _columnControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _syncChanges() {
    final updatedPayload = _payload.copyWith(
      name: _titleController.text.trim(),
      columns: _columns,
      rows: _rows,
      columnTypes: _columnTypes,
    );
    widget.onUpdate(widget.node.copyWith(payload: updatedPayload));
  }

  void _addRow() {
    setState(() {
      _rows.add(List.filled(_columns.length, ''));
    });
    _syncChanges();
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      _rows.removeAt(index);
    });
    _syncChanges();
  }

  void _addColumn() {
    setState(() {
      _columns.add('Column ${_columns.length + 1}');
      _columnTypes.add(TableCellType.text);
      for (final r in _rows) {
        r.add('');
      }
    });
    _syncChanges();
  }

  void _removeColumn(int index) {
    if (_columns.length <= 1) return;
    setState(() {
      _columns.removeAt(index);
      if (index < _columnTypes.length) {
        _columnTypes.removeAt(index);
      }
      for (final r in _rows) {
        if (index < r.length) {
          r.removeAt(index);
        }
      }
    });
    _syncChanges();
  }

  bool _validateCell(String val, TableCellType type) {
    if (val.trim().isEmpty) return true;
    switch (type) {
      case TableCellType.number:
        return double.tryParse(val.trim()) != null;
      case TableCellType.currency:
        final clean = val.replaceAll(RegExp(r'[\$,Rp\s]'), '');
        return double.tryParse(clean) != null;
      case TableCellType.percentage:
        final clean = val.replaceAll(RegExp(r'[%\s]'), '');
        return double.tryParse(clean) != null;
      case TableCellType.date:
        return DateTime.tryParse(val.trim()) != null ||
            RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(val.trim()) ||
            RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$').hasMatch(val.trim());
      case TableCellType.time:
        return RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(val.trim());
      case TableCellType.formula:
        return val.trim().startsWith('=');
      case TableCellType.checkbox:
      case TableCellType.text:
        return true;
    }
  }

  Future<void> _pickDateForCell(int rowIndex, int colIndex) async {
    final cur = _rows[rowIndex][colIndex];
    DateTime initial = DateTime.now();
    final parsed = DateTime.tryParse(cur);
    if (parsed != null) initial = parsed;

    final picked = await showUiDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2050),
    );

    if (picked != null) {
      final formatted =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {
        _rows[rowIndex][colIndex] = formatted;
      });
      _syncChanges();
    }
  }

  Future<void> _pickTimeForCell(int rowIndex, int colIndex) async {
    final picked = await showUiTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (picked != null) {
      final formatted =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        _rows[rowIndex][colIndex] = formatted;
      });
      _syncChanges();
    }
  }

  void _showImportCsvDialog() {
    final csvController = TextEditingController();
    showUiDialog<void>(
      context: context,
      builder: (dialogContext) {
        final tokens = dialogContext.appTokens;
        return UiDialog(
          constraints: AppResponsive.dialogConstraints(
            dialogContext,
            maxWidth: 520,
            maxHeight: 560,
          ),
          builder: (context, style) => SingleChildScrollView(
            child: Padding(
              padding: AppResponsive.dialogPadding(context),
              child: Column(
                children: [
                  Text('Import CSV Data', style: style.titleTextStyle),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Paste comma or tab-separated values. The first row will be used as column headers.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  UiTextField(
                    controller: csvController,
                    hint:
                        'Feature,Priority,Status\nAuth,High,Done\nEngine,High,Active',
                    minLines: 8,
                    maxLines: 8,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      UiButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        variant: UiButtonVariant.ghost,
                        child: const Text('Cancel'),
                      ),
                      UiButton(
                        onPressed: () {
                          final text = csvController.text.trim();
                          if (text.isNotEmpty) {
                            final lines = text
                                .split('\n')
                                .map((line) => line.trim())
                                .where((line) => line.isNotEmpty)
                                .toList();
                            if (lines.isNotEmpty) {
                              final delimiter = lines.first.contains('\t')
                                  ? '\t'
                                  : ',';
                              final headers = lines.first
                                  .split(delimiter)
                                  .map((header) => header.trim())
                                  .toList();
                              final parsedRows = <List<String>>[];
                              for (var i = 1; i < lines.length; i++) {
                                final row = lines[i]
                                    .split(delimiter)
                                    .map((cell) => cell.trim())
                                    .toList();
                                while (row.length < headers.length) {
                                  row.add('');
                                }
                                parsedRows.add(row.sublist(0, headers.length));
                              }
                              setState(() {
                                _columns = headers;
                                _rows = parsedRows.isEmpty
                                    ? [List.filled(headers.length, '')]
                                    : parsedRows;
                                _columnTypes = List.filled(
                                  headers.length,
                                  TableCellType.text,
                                );
                              });
                              _syncChanges();
                            }
                          }
                          Navigator.pop(dialogContext);
                        },
                        variant: UiButtonVariant.primary,
                        child: const Text('Import CSV'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _exportCsv() {
    final buffer = StringBuffer();
    buffer.writeln(
      _columns.map((c) => '"${c.replaceAll('"', '""')}"').join(','),
    );
    for (final row in _rows) {
      buffer.writeln(row.map((c) => '"${c.replaceAll('"', '""')}"').join(','));
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    showUiToast(
      context,
      'CSV data copied to clipboard!',
      variant: UiToastVariant.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final titleField = UiTextField(
      controller: _titleController,
      hint: 'Table Title...',
      onChanged: (_) => _syncChanges(),
    );
    final closeButton = UiIconButton(
      icon: Icons.close,
      tooltip: 'Close',
      size: UiButtonSize.sm,
      onPressed: () => Navigator.pop(context),
    );
    final importButton = UiButton(
      onPressed: _showImportCsvDialog,
      variant: UiButtonVariant.outline,
      size: UiButtonSize.sm,
      prefix: const Icon(Icons.file_upload_outlined, size: 14),
      child: const Text('Import CSV'),
    );
    final exportButton = UiButton(
      onPressed: _exportCsv,
      variant: UiButtonVariant.outline,
      size: UiButtonSize.sm,
      prefix: const Icon(Icons.file_download_outlined, size: 14),
      child: const Text('Copy CSV'),
    );
    return UiDialog(
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 860,
        maxHeight: 640,
      ),
      builder: (context, style) => SizedBox(
        width: AppResponsive.dialogWidth(context, preferred: 860),
        height: AppResponsive.dialogHeight(context, preferred: 640),
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar
              LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth < 700
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.table_chart_rounded,
                                color: tokens.accent,
                                size: 20,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(child: titleField),
                              closeButton,
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            children: [importButton, exportButton],
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Icon(
                            Icons.table_chart_rounded,
                            color: tokens.accent,
                            size: 20,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: titleField),
                          importButton,
                          const SizedBox(width: AppSpacing.sm),
                          exportButton,
                          const SizedBox(width: AppSpacing.sm),
                          closeButton,
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Toolbar Controls (Add Row, Add Col, Toggle Summary)
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs + AppSpacing.xxs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  UiButton(
                    onPressed: _addRow,
                    variant: UiButtonVariant.outline,
                    size: UiButtonSize.sm,
                    prefix: const Icon(Icons.add, size: 14),
                    child: const Text('Add Row'),
                  ),
                  UiButton(
                    onPressed: _addColumn,
                    variant: UiButtonVariant.outline,
                    size: UiButtonSize.sm,
                    prefix: const Icon(Icons.view_column_outlined, size: 14),
                    child: const Text('Add Column'),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Summary Row:',
                        style: Theme.of(context).textTheme.labelMedium!
                            .copyWith(color: tokens.textMuted),
                      ),
                      const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                      UiSwitch(
                        value: _payload.showSummaryRow,
                        onChange: (val) {
                          setState(() {
                            _payload = _payload.copyWith(showSummaryRow: val);
                          });
                          _syncChanges();
                        },
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.md),

              // Spreadsheet Data Table Grid
              Expanded(
                child: Container(
                  key: const ValueKey('table-editor-viewport-frame'),
                  decoration: BoxDecoration(
                    color: tokens.panelElevated,
                    borderRadius: BorderRadius.circular(tokens.controlRadius),
                    border: Border.all(
                      color: tokens.panelBorder,
                      width: AppBorder.thin,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(tokens.controlRadius),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: Table(
                          defaultColumnWidth: const FixedColumnWidth(180),
                          border: TableBorder.all(
                            color: tokens.panelBorder,
                            width: AppBorder.thin,
                          ),
                          children: [
                            // Header Row
                            TableRow(
                              decoration: BoxDecoration(color: tokens.panel),
                              children: [
                                for (int c = 0; c < _columns.length; c++)
                                  _buildHeaderCell(c),
                              ],
                            ),
                            // Data Rows
                            for (int r = 0; r < _rows.length; r++)
                              TableRow(
                                decoration: BoxDecoration(
                                  color: r % 2 == 0
                                      ? tokens.panelElevated
                                      : tokens.panel,
                                ),
                                children: [
                                  for (int c = 0; c < _columns.length; c++)
                                    _buildDataCell(r, c),
                                ],
                              ),
                            // Summary Aggregates Row (if enabled)
                            if (_payload.showSummaryRow)
                              TableRow(
                                decoration: BoxDecoration(
                                  color: tokens.accentSoft,
                                ),
                                children: [
                                  for (int c = 0; c < _columns.length; c++)
                                    _buildSummaryCell(c),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              LayoutBuilder(
                builder: (context, constraints) {
                  final formulaHint = Text(
                    '💡 Formula syntax: =SUM(A1:A5), =AVG(B1:B3), =A1+B1',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
                  );
                  final saveButton = UiButton(
                    onPressed: () => Navigator.pop(context),
                    variant: UiButtonVariant.primary,
                    prefix: const Icon(Icons.check, size: 16),
                    child: const Text('Save & Close'),
                  );
                  if (constraints.maxWidth < 500) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        formulaHint,
                        Align(
                          alignment: Alignment.centerRight,
                          child: saveButton,
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: formulaHint),
                      const SizedBox(width: AppSpacing.md),
                      saveButton,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCell(int colIndex) {
    final colType = colIndex < _columnTypes.length
        ? _columnTypes[colIndex]
        : TableCellType.text;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs + AppSpacing.xxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: UiTextField(
                  controller: _columnController(colIndex, _columns[colIndex]),
                  onChanged: (val) {
                    _columns[colIndex] = val;
                    _syncChanges();
                  },
                ),
              ),
              if (_columns.length > 1)
                UiIconButton(
                  icon: Icons.close,
                  tooltip: 'Remove column',
                  size: UiButtonSize.sm,
                  onPressed: () => _removeColumn(colIndex),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          UiSelect<TableCellType>(
            items: {
              for (final type in TableCellType.values)
                type.name.toUpperCase(): type,
            },
            value: colType,
            label: 'COLUMN TYPE',
            onChanged: (newType) {
              if (newType == null) return;
              setState(() {
                while (_columnTypes.length <= colIndex) {
                  _columnTypes.add(TableCellType.text);
                }
                _columnTypes[colIndex] = newType;
              });
              _syncChanges();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDataCell(int rowIndex, int colIndex) {
    final tokens = context.appTokens;
    final colType = colIndex < _columnTypes.length
        ? _columnTypes[colIndex]
        : TableCellType.text;
    final val = (colIndex < _rows[rowIndex].length)
        ? _rows[rowIndex][colIndex]
        : '';
    final isValid = _validateCell(val, colType);

    if (colType == TableCellType.checkbox) {
      final checked =
          val.toLowerCase() == 'true' || val == '1' || val.toLowerCase() == 'x';
      return Container(
        height: AppControlSize.minimumHitTarget,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: AppSpacing.sm + AppSpacing.xxs),
        child: Row(
          children: [
            UiCheckbox(
              value: checked,
              semanticsLabel: 'Toggle row ${rowIndex + 1}',
              onChange: (b) {
                setState(() {
                  _rows[rowIndex][colIndex] = b ? 'true' : 'false';
                });
                _syncChanges();
              },
            ),
            const Spacer(),
            if (colIndex == _columns.length - 1 && _rows.length > 1)
              UiIconButton(
                icon: Icons.delete_outline,
                tooltip: 'Remove row',
                variant: UiButtonVariant.destructive,
                size: UiButtonSize.sm,
                onPressed: () => _removeRow(rowIndex),
              ),
          ],
        ),
      );
    }

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: !isValid
            ? tokens.danger.withValues(alpha: 0.12)
            : Colors.transparent,
        border: !isValid
            ? Border.all(color: tokens.danger, width: AppBorder.thin)
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: UiTextField(
              controller: _cellController(rowIndex, colIndex, val),
              hint: colType == TableCellType.formula
                  ? '=SUM(...)'
                  : (colType == TableCellType.date
                        ? 'YYYY-MM-DD'
                        : (colType == TableCellType.time ? 'HH:MM' : null)),
              onChanged: (newVal) {
                setState(() {
                  _rows[rowIndex][colIndex] = newVal;
                });
                _syncChanges();
              },
            ),
          ),
          if (!isValid)
            Tooltip(
              message: 'Invalid format for this column type',
              child: Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: tokens.danger,
              ),
            ),
          if (colType == TableCellType.date)
            UiIconButton(
              icon: Icons.calendar_today,
              tooltip: 'Pick date',
              size: UiButtonSize.sm,
              onPressed: () => _pickDateForCell(rowIndex, colIndex),
            ),
          if (colType == TableCellType.time)
            UiIconButton(
              icon: Icons.access_time,
              tooltip: 'Pick time',
              size: UiButtonSize.sm,
              onPressed: () => _pickTimeForCell(rowIndex, colIndex),
            ),
          if (colIndex == _columns.length - 1 && _rows.length > 1)
            UiIconButton(
              icon: Icons.delete_outline,
              tooltip: 'Remove row',
              variant: UiButtonVariant.destructive,
              size: UiButtonSize.sm,
              onPressed: () => _removeRow(rowIndex),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryCell(int colIndex) {
    final tokens = context.appTokens;
    final colType = colIndex < _columnTypes.length
        ? _columnTypes[colIndex]
        : TableCellType.text;
    if (colType == TableCellType.number ||
        colType == TableCellType.currency ||
        colType == TableCellType.percentage) {
      double sum = 0;
      for (final r in _rows) {
        if (colIndex < r.length) {
          final parsed = double.tryParse(
            r[colIndex].replaceAll(RegExp(r'[^0-9.-]'), ''),
          );
          if (parsed != null) {
            sum += parsed;
          }
        }
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(
          'SUM: ${sum == sum.roundToDouble() ? sum.toInt() : sum.toStringAsFixed(2)}',
          style: TextStyle(
            color: tokens.success,
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        'Count: ${_rows.length}',
        style: TextStyle(color: tokens.textMuted, fontSize: 10),
      ),
    );
  }
}
