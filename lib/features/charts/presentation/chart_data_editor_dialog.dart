import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/node_payload.dart';

/// Edits chart categories and series as a compact spreadsheet-like grid.
class ChartDataEditorDialog extends StatefulWidget {
  final ChartPayload payload;
  final ValueChanged<ChartPayload> onSave;
  final bool readOnly;

  const ChartDataEditorDialog({
    required this.payload,
    required this.onSave,
    this.readOnly = false,
    super.key,
  });

  @override
  State<ChartDataEditorDialog> createState() => _ChartDataEditorDialogState();
}

class _ChartDataEditorDialogState extends State<ChartDataEditorDialog> {
  late ChartPayload _draft;
  late final TextEditingController _pasteController;
  String? _importError;

  @override
  void initState() {
    super.initState();
    _draft = widget.payload.clone();
    _pasteController = TextEditingController();
  }

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  int get _rowCount => [
    _draft.categories.length,
    for (final series in _draft.series) series.values.length,
  ].fold(1, (count, length) => count > length ? count : length);

  String _categoryAt(int index) => index < _draft.categories.length
      ? _draft.categories[index]
      : 'Category ${index + 1}';

  double _valueAt(ChartSeries series, int index) =>
      index < series.values.length ? series.values[index] : 0;

  void _updateCategory(int index, String value) {
    final categories = List<String>.from(_draft.categories);
    while (categories.length <= index) {
      categories.add('Category ${categories.length + 1}');
    }
    categories[index] = value.trim().isEmpty ? 'Category ${index + 1}' : value;
    setState(() => _draft = _draft.copyWith(categories: categories));
  }

  void _updateValue(int seriesIndex, int rowIndex, String raw) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null || !parsed.isFinite) return;
    final series = _draft.series[seriesIndex];
    final values = List<double>.from(series.values);
    while (values.length <= rowIndex) {
      values.add(0);
    }
    values[rowIndex] = parsed;
    final nextSeries = List<ChartSeries>.from(_draft.series)
      ..[seriesIndex] = series.copyWith(values: values);
    setState(() => _draft = _draft.copyWith(series: nextSeries));
  }

  void _addRow() {
    final nextCategories = List<String>.from(_draft.categories)
      ..add('Category ${_rowCount + 1}');
    final nextSeries = [
      for (final series in _draft.series)
        series.copyWith(values: [...series.values, 0]),
    ];
    setState(
      () => _draft = _draft.copyWith(
        categories: nextCategories,
        series: nextSeries,
      ),
    );
  }

  void _removeRow() {
    if (_rowCount <= 1) return;
    final nextCategories = List<String>.from(_draft.categories);
    if (nextCategories.isNotEmpty) nextCategories.removeLast();
    final nextSeries = [
      for (final series in _draft.series)
        series.copyWith(
          values: series.values.isEmpty
              ? const []
              : series.values.sublist(0, series.values.length - 1),
        ),
    ];
    setState(
      () => _draft = _draft.copyWith(
        categories: nextCategories,
        series: nextSeries,
      ),
    );
  }

  void _addSeries() {
    if (_draft.series.length >= 12) return;
    final index = _draft.series.length;
    final color = _draft.colors[index % _draft.colors.length];
    setState(
      () => _draft = _draft.copyWith(
        series: [
          ..._draft.series,
          ChartSeries(
            name: 'Series ${index + 1}',
            values: List<double>.filled(_rowCount, 0),
            color: color,
          ),
        ],
      ),
    );
  }

  void _removeSeries(int index) {
    if (_draft.series.length <= 1) return;
    final series = List<ChartSeries>.from(_draft.series)..removeAt(index);
    setState(() => _draft = _draft.copyWith(series: series));
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) return;
    _pasteController.text = text;
    _applyPastedData();
  }

  void _applyPastedData() {
    final rows = _parseDelimitedRows(_pasteController.text);
    final data = _parseDelimitedChartData(rows);
    if (data == null) return;
    _applyData(data.categories, data.series);
  }

  void _applyJsonData() {
    final text = _pasteController.text.trim();
    if (text.isEmpty) {
      setState(() => _importError = 'Paste JSON data first.');
      return;
    }

    try {
      final data = _decodeJsonChartData(jsonDecode(text));
      if (data == null) {
        setState(
          () => _importError =
              'JSON must contain chart data or numeric row fields.',
        );
        return;
      }
      _applyData(data.categories, data.series);
    } on FormatException {
      setState(() => _importError = 'Invalid JSON.');
    } on Object catch (_) {
      setState(() => _importError = 'Could not read this JSON shape.');
    }
  }

  void _applyData(List<String> categories, List<ChartSeries> series) {
    setState(() {
      _importError = null;
      _draft = _draft.copyWith(categories: categories, series: series);
    });
  }

  ({List<String> categories, List<ChartSeries> series})? _decodeJsonChartData(
    dynamic value,
  ) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final nested = map['data'];
      if (nested != null) return _decodeJsonChartData(nested);
      if (map['categories'] is List && map['series'] is List) {
        final chart = ChartPayload.fromJson(map);
        return (categories: chart.categories, series: chart.series);
      }
      return null;
    }

    if (value is! List || value.isEmpty) return null;
    if (value.every((row) => row is Map)) {
      return _decodeJsonObjectRows(value);
    }
    if (value.every((row) => row is List)) {
      final rows = [
        for (final row in value)
          [for (final cell in row as List) _jsonCell(cell)],
      ];
      return _parseDelimitedChartData(rows);
    }
    return null;
  }

  ({List<String> categories, List<ChartSeries> series})? _decodeJsonObjectRows(
    List<dynamic> rawRows,
  ) {
    final rows = rawRows
        .cast<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .take(100)
        .toList();
    final seriesNames = <String>[];
    final categoryKeys = <String?>[];
    for (final row in rows) {
      final categoryKey = _jsonCategoryKey(row);
      categoryKeys.add(categoryKey);
      for (final entry in row.entries) {
        if (entry.key == categoryKey ||
            _jsonFiniteNumber(entry.value) == null) {
          continue;
        }
        final name = entry.key;
        if (!seriesNames.contains(name)) seriesNames.add(name);
      }
    }
    if (seriesNames.isEmpty) return null;

    final categories = [
      for (var index = 0; index < rows.length; index++)
        _jsonCategoryValue(rows[index], categoryKeys[index], index),
    ];
    final series = [
      for (var seriesIndex = 0; seriesIndex < seriesNames.length; seriesIndex++)
        ChartSeries(
          name: seriesNames[seriesIndex],
          values: [
            for (final row in rows)
              _jsonFiniteNumber(row[seriesNames[seriesIndex]]) ?? 0,
          ],
          color: seriesIndex < _draft.series.length
              ? _draft.series[seriesIndex].color
              : _draft.colors[seriesIndex % _draft.colors.length],
        ),
    ];
    return (categories: categories, series: series);
  }

  ({List<String> categories, List<ChartSeries> series})?
  _parseDelimitedChartData(List<List<String>> rows) {
    if (rows.isEmpty) return null;
    final hasHeader =
        rows.length > 1 &&
        rows.first.length > 1 &&
        rows.first.skip(1).any((cell) => double.tryParse(cell) == null);
    final header = hasHeader ? rows.first : null;
    final dataRows = hasHeader ? rows.skip(1).toList() : rows;
    if (dataRows.isEmpty) return null;

    final seriesCount = dataRows.fold<int>(
      1,
      (count, row) => count > row.length - 1 ? count : row.length - 1,
    );
    final categories = <String>[];
    final values = [
      for (var seriesIndex = 0; seriesIndex < seriesCount; seriesIndex++)
        <double>[],
    ];
    for (
      var rowIndex = 0;
      rowIndex < dataRows.length && rowIndex < 100;
      rowIndex++
    ) {
      final row = dataRows[rowIndex];
      categories.add(
        row.isEmpty || row.first.trim().isEmpty
            ? 'Category ${rowIndex + 1}'
            : row.first.trim(),
      );
      for (var seriesIndex = 0; seriesIndex < seriesCount; seriesIndex++) {
        final raw = seriesIndex + 1 < row.length ? row[seriesIndex + 1] : '0';
        final value = double.tryParse(raw.trim());
        values[seriesIndex].add(value != null && value.isFinite ? value : 0);
      }
    }

    final series = [
      for (var index = 0; index < seriesCount; index++)
        ChartSeries(
          name: header != null && index + 1 < header.length
              ? header[index + 1]
              : index < _draft.series.length
              ? _draft.series[index].name
              : 'Series ${index + 1}',
          values: values[index],
          color: index < _draft.series.length
              ? _draft.series[index].color
              : _draft.colors[index % _draft.colors.length],
        ),
    ];
    return (categories: categories, series: series);
  }

  String _jsonCell(dynamic value) {
    if (value == null) return '';
    if (value is num && value.isFinite) return value.toString();
    return value.toString();
  }

  double? _jsonFiniteNumber(dynamic value) {
    if (value is num && value.isFinite) return value.toDouble();
    return null;
  }

  String? _jsonCategoryKey(Map<String, dynamic> row) {
    for (final candidate in ['category', 'label', 'name', 'x']) {
      if (row.containsKey(candidate)) return candidate;
    }
    for (final entry in row.entries) {
      if (_jsonFiniteNumber(entry.value) == null) return entry.key;
    }
    return null;
  }

  String _jsonCategoryValue(
    Map<String, dynamic> row,
    String? categoryKey,
    int index,
  ) {
    final value = categoryKey == null ? null : row[categoryKey];
    final label = value?.toString().trim();
    return label == null || label.isEmpty ? 'Category ${index + 1}' : label;
  }

  List<List<String>> _parseDelimitedRows(String raw) {
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trimRight())
        .where((line) => line.trim().isNotEmpty)
        .take(101)
        .toList();
    if (lines.isEmpty) return const [];
    final delimiter = lines.any((line) => line.contains('\t')) ? '\t' : ',';
    return [for (final line in lines) _parseDelimitedLine(line, delimiter)];
  }

  List<String> _parseDelimitedLine(String line, String delimiter) {
    final cells = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var index = 0; index < line.length; index++) {
      final char = line[index];
      if (char == '"') {
        if (quoted && index + 1 < line.length && line[index + 1] == '"') {
          buffer.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (char == delimiter && !quoted) {
        cells.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    cells.add(buffer.toString().trim());
    return cells;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final width = AppResponsive.dialogWidth(context, preferred: 1100);
    final height = AppResponsive.dialogHeight(context, preferred: 760);

    return UiDialog(
      semanticsLabel: 'Edit chart data',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 1100,
        maxHeight: 760,
      ),
      builder: (context, style) => SizedBox(
        width: width,
        height: height,
        child: UiSurface(
          padding: EdgeInsets.zero,
          color: tokens.panel,
          child: Column(
            children: [
              _buildHeader(tokens, style),
              Expanded(child: _buildBody(tokens)),
              _buildFooter(tokens),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppTokens tokens, UiDialogStyle style) {
    final title = Text(
      'CHART DATA',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style.titleTextStyle.copyWith(color: tokens.text),
    );
    final closeButton = UiIconButton(
      icon: Icons.close,
      tooltip: 'Close chart data editor',
      onPressed: () => Navigator.of(context).pop(),
    );
    final content = AppResponsive.isCompact(context)
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.table_chart_outlined,
                    color: tokens.accent,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: title),
                ],
              ),
              Align(alignment: Alignment.centerRight, child: closeButton),
            ],
          )
        : Row(
            children: [
              Icon(Icons.table_chart_outlined, color: tokens.accent, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: title),
              closeButton,
            ],
          );
    return Container(
      key: const ValueKey('chart-data-header-surface'),
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
      child: content,
    );
  }

  Widget _buildBody(AppTokens tokens) => ListView(
    padding: const EdgeInsets.all(AppSpacing.page),
    children: [
      Text(
        'Edit values directly or paste a CSV/TSV table or JSON.',
        style: Theme.of(
          context,
        ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
      ),
      const SizedBox(height: AppSpacing.sm),
      _buildPasteControls(tokens),
      const SizedBox(height: AppSpacing.md),
      _buildTable(tokens),
      const SizedBox(height: AppSpacing.sm),
      _buildTableActions(),
    ],
  );

  Widget _buildTableActions() {
    final addRow = UiButton(
      key: const ValueKey('chart-data-add-row'),
      variant: UiButtonVariant.outline,
      prefix: const Icon(Icons.add, size: 14),
      onPressed: widget.readOnly ? null : _addRow,
      child: const Text('Add Row'),
    );
    final removeRow = UiButton(
      key: const ValueKey('chart-data-remove-row'),
      variant: UiButtonVariant.outline,
      prefix: const Icon(Icons.remove, size: 14),
      onPressed: widget.readOnly || _rowCount <= 1 ? null : _removeRow,
      child: const Text('Remove Row'),
    );
    final addSeries = UiButton(
      key: const ValueKey('chart-data-add-series'),
      variant: UiButtonVariant.outline,
      prefix: const Icon(Icons.add, size: 14),
      onPressed: widget.readOnly || _draft.series.length >= 12
          ? null
          : _addSeries,
      child: const Text('Add Series'),
    );

    if (AppResponsive.isCompact(context)) {
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs + AppSpacing.xxs,
        children: [addRow, removeRow, addSeries],
      );
    }

    return Row(
      children: [
        addRow,
        const SizedBox(width: AppSpacing.sm),
        removeRow,
        const Spacer(),
        addSeries,
      ],
    );
  }

  Widget _buildPasteControls(AppTokens tokens) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      UiTextField(
        key: const ValueKey('chart-data-paste'),
        controller: _pasteController,
        label: 'Paste data',
        hint: 'Category, Revenue, Cost\nQ1, 10, 7\nQ2, 14, 9',
        minLines: 2,
        maxLines: 4,
        readOnly: widget.readOnly,
        keyboardType: TextInputType.multiline,
      ),
      const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs + AppSpacing.xxs,
        children: [
          UiButton(
            key: const ValueKey('chart-data-paste-clipboard'),
            variant: UiButtonVariant.outline,
            prefix: const Icon(Icons.content_paste, size: 14),
            onPressed: widget.readOnly ? null : _pasteFromClipboard,
            child: const Text('Paste Clipboard'),
          ),
          UiButton(
            key: const ValueKey('chart-data-apply-paste'),
            prefix: const Icon(Icons.table_rows_outlined, size: 14),
            onPressed: widget.readOnly ? null : _applyPastedData,
            child: const Text('Apply Data'),
          ),
          UiButton(
            key: const ValueKey('chart-data-apply-json'),
            prefix: const Icon(Icons.data_object, size: 14),
            onPressed: widget.readOnly ? null : _applyJsonData,
            child: const Text('Apply JSON'),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
      Text(
        'The first column is used as categories. JSON accepts chart payloads or rows with category and numeric fields.',
        style: Theme.of(
          context,
        ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
      ),
      if (_importError != null) ...[
        const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
        Text(
          _importError!,
          key: const ValueKey('chart-data-import-error'),
          style: Theme.of(
            context,
          ).textTheme.bodySmall!.copyWith(color: tokens.danger),
        ),
      ],
    ],
  );

  Widget _buildTable(AppTokens tokens) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DecoratedBox(
      key: const ValueKey('chart-data-table-surface'),
      decoration: BoxDecoration(
        border: Border.all(color: tokens.panelBorder, width: AppBorder.thin),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTableHeader(tokens),
          for (var rowIndex = 0; rowIndex < _rowCount; rowIndex++)
            _buildTableRow(tokens, rowIndex),
        ],
      ),
    ),
  );

  Widget _buildTableHeader(AppTokens tokens) => Row(
    children: [
      _headerCell(tokens, 'Category', 150),
      for (var index = 0; index < _draft.series.length; index++)
        SizedBox(
          width: 150,
          child: Row(
            children: [
              Expanded(
                child: _ChartCellField(
                  key: ValueKey('chart-data-series-name-$index'),
                  value: _draft.series[index].name,
                  enabled: !widget.readOnly,
                  semanticsLabel: 'Series ${index + 1} name',
                  onChanged: (value) {
                    final next = List<ChartSeries>.from(_draft.series)
                      ..[index] = _draft.series[index].copyWith(name: value);
                    setState(() => _draft = _draft.copyWith(series: next));
                  },
                ),
              ),
              if (_draft.series.length > 1)
                UiIconButton(
                  icon: Icons.close,
                  tooltip: 'Remove series ${index + 1}',
                  size: UiButtonSize.sm,
                  onPressed: widget.readOnly
                      ? null
                      : () => _removeSeries(index),
                ),
            ],
          ),
        ),
    ],
  );

  Widget _buildTableRow(AppTokens tokens, int rowIndex) => Row(
    children: [
      SizedBox(
        width: 150,
        child: _ChartCellField(
          key: ValueKey('chart-data-category-$rowIndex'),
          value: _categoryAt(rowIndex),
          enabled: !widget.readOnly,
          semanticsLabel: 'Category ${rowIndex + 1}',
          onChanged: (value) => _updateCategory(rowIndex, value),
        ),
      ),
      for (
        var seriesIndex = 0;
        seriesIndex < _draft.series.length;
        seriesIndex++
      )
        SizedBox(
          width: 150,
          child: _ChartCellField(
            key: ValueKey('chart-data-value-$rowIndex-$seriesIndex'),
            value: _formatValue(_valueAt(_draft.series[seriesIndex], rowIndex)),
            enabled: !widget.readOnly,
            numeric: true,
            semanticsLabel:
                '${_draft.series[seriesIndex].name} for ${_categoryAt(rowIndex)} (row ${rowIndex + 1})',
            onChanged: (value) => _updateValue(seriesIndex, rowIndex, value),
          ),
        ),
    ],
  );

  Widget _headerCell(AppTokens tokens, String label, double width) => Container(
    width: width,
    height: 42,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    color: tokens.panelElevated,
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall!.copyWith(
        color: tokens.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _buildFooter(AppTokens tokens) => Container(
    key: const ValueKey('chart-data-footer-surface'),
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.sm,
      AppSpacing.lg,
      AppSpacing.md,
    ),
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
      ),
    ),
    child: AppResponsive.isCompact(context)
        ? Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [_buildCancelButton(), _buildSaveButton()],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildCancelButton(),
              const SizedBox(width: AppSpacing.sm),
              _buildSaveButton(),
            ],
          ),
  );

  Widget _buildCancelButton() => UiButton(
    variant: UiButtonVariant.ghost,
    onPressed: () => Navigator.of(context).pop(),
    child: const Text('Cancel'),
  );

  Widget _buildSaveButton() => UiButton(
    key: const ValueKey('chart-data-save'),
    onPressed: widget.readOnly
        ? null
        : () {
            widget.onSave(_draft);
            Navigator.of(context).pop();
          },
    child: const Text('Save Data'),
  );

  String _formatValue(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();
}

class _ChartCellField extends StatefulWidget {
  final String value;
  final bool enabled;
  final bool numeric;
  final String semanticsLabel;
  final ValueChanged<String> onChanged;

  const _ChartCellField({
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.semanticsLabel,
    this.numeric = false,
    super.key,
  });

  @override
  State<_ChartCellField> createState() => _ChartCellFieldState();
}

class _ChartCellFieldState extends State<_ChartCellField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _syncingController = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _ChartCellField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.value && !_focusNode.hasFocus) {
      _syncingController = true;
      try {
        _controller.value = TextEditingValue(
          text: widget.value,
          selection: TextSelection.collapsed(offset: widget.value.length),
        );
      } finally {
        _syncingController = false;
      }
    }
  }

  void _handleChanged(String value) {
    if (!_syncingController) widget.onChanged(value);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(3),
    child: Semantics(
      container: true,
      label: widget.semanticsLabel,
      textField: true,
      child: UiTextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        keyboardType: widget.numeric
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.text,
        onChanged: _handleChanged,
      ),
    ),
  );
}
