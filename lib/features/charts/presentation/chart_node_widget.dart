import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/charts/data/chart_database_adapter.dart';
import 'package:varian/features/charts/data/chart_source_loader.dart';

class ChartNodeWidget extends StatefulWidget {
  final ChartPayload payload;
  final ChartSourceLoader? sourceLoader;
  final ChartDatabaseAdapter? databaseAdapter;
  final ValueChanged<String>? onCategoryTap;
  final ValueChanged<ChartPayload>? onResolvedPayload;

  const ChartNodeWidget({
    required this.payload,
    this.sourceLoader,
    this.databaseAdapter,
    this.onCategoryTap,
    this.onResolvedPayload,
    super.key,
  });

  @override
  State<ChartNodeWidget> createState() => _ChartNodeWidgetState();
}

class _ChartNodeWidgetState extends State<ChartNodeWidget> {
  ChartSourceLoader? _sourceLoader;
  late ChartPayload _resolvedPayload;
  ChartPayload? _remoteData;
  String? _sourceError;
  bool _sourceLoading = false;
  int _requestToken = 0;
  bool _ownsSourceLoader = false;

  ChartPayload get payload => _resolvedPayload.filteredByCategory();

  Color get _background => context.appTokens.panelElevated;
  Color get _border => context.appTokens.panelBorder;
  Color get _muted => context.appTokens.textMuted;

  @override
  void initState() {
    super.initState();
    _resolvedPayload = widget.payload;
    _sourceLoader = widget.sourceLoader;
    _loadRemoteData();
  }

  @override
  void didUpdateWidget(covariant ChartNodeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceLoader != widget.sourceLoader) {
      if (_ownsSourceLoader) _sourceLoader?.dispose();
      _sourceLoader = widget.sourceLoader;
      _ownsSourceLoader = false;
    }

    final sourceChanged =
        oldWidget.payload.dataSourceUrl != widget.payload.dataSourceUrl ||
        oldWidget.payload.databaseTableName !=
            widget.payload.databaseTableName ||
        oldWidget.payload.databaseCategoryColumn !=
            widget.payload.databaseCategoryColumn ||
        !listEquals(
          oldWidget.payload.databaseValueColumns,
          widget.payload.databaseValueColumns,
        ) ||
        oldWidget.payload.databaseRowLimit != widget.payload.databaseRowLimit ||
        oldWidget.payload.dataRefreshRevision !=
            widget.payload.dataRefreshRevision ||
        oldWidget.databaseAdapter != widget.databaseAdapter;
    _resolvedPayload = _remoteData == null
        ? widget.payload
        : _mergeRemoteData(widget.payload, _remoteData!);
    if (sourceChanged) {
      _remoteData = null;
      _sourceError = null;
      _loadRemoteData();
    } else if (!_hasRemoteSource(widget.payload)) {
      _sourceLoading = false;
      _sourceError = null;
    }
  }

  @override
  void dispose() {
    _requestToken++;
    if (_ownsSourceLoader) _sourceLoader?.dispose();
    super.dispose();
  }

  Future<void> _loadRemoteData() async {
    final url = widget.payload.dataSourceUrl;
    final databaseTable = widget.payload.databaseTableName;
    final requestToken = ++_requestToken;
    if (!_hasRemoteSource(widget.payload)) {
      _resolvedPayload = widget.payload;
      _remoteData = null;
      _sourceLoading = false;
      _sourceError = null;
      return;
    }

    if (mounted) {
      setState(() {
        _sourceLoading = true;
        _sourceError = null;
        _resolvedPayload = _remoteData == null
            ? widget.payload
            : _mergeRemoteData(widget.payload, _remoteData!);
      });
    }

    try {
      final remote = databaseTable != null
          ? await (widget.databaseAdapter?.load(widget.payload) ??
                Future<ChartPayload>.error(
                  const ChartDatabaseException(
                    'Database adapter is not configured.',
                  ),
                ))
          : await _loadFromUrl(url!);
      if (!mounted || requestToken != _requestToken) return;
      setState(() {
        _remoteData = remote;
        _resolvedPayload = _mergeRemoteData(widget.payload, remote);
        _sourceLoading = false;
        _sourceError = null;
      });
      widget.onResolvedPayload?.call(remote);
    } on ChartSourceException catch (error) {
      _setSourceError(requestToken, error.message);
    } on ChartDatabaseException catch (error) {
      _setSourceError(requestToken, error.message);
    }
  }

  Future<ChartPayload> _loadFromUrl(String url) async {
    if (_sourceLoader == null) {
      _sourceLoader = ChartSourceLoader();
      _ownsSourceLoader = true;
    }
    return _sourceLoader!.load(url);
  }

  bool _hasRemoteSource(ChartPayload payload) =>
      payload.dataSourceUrl != null || payload.databaseTableName != null;

  void _setSourceError(int requestToken, String message) {
    if (!mounted || requestToken != _requestToken) return;
    setState(() {
      _resolvedPayload = widget.payload;
      _sourceLoading = false;
      _sourceError = message;
    });
  }

  ChartPayload _mergeRemoteData(ChartPayload local, ChartPayload remote) =>
      local.copyWith(categories: remote.categories, series: remote.series);

  @override
  Widget build(BuildContext context) {
    return UiSurface(
      color: context.appTokens.panel,
      borderRadius: BorderRadius.circular(context.appTokens.panelRadius),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm + AppSpacing.xxs,
        AppSpacing.sm,
        AppSpacing.sm + AppSpacing.xxs,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (payload.title.isNotEmpty) ...[
            Text(
              payload.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.appTokens.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          Expanded(child: _buildChart()),
          if (_sourceLoading)
            Text(
              'Refreshing data…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: context.appTokens.textMuted,
              ),
            )
          else if (_sourceError != null)
            Text(
              'Using saved chart data',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                color: context.appTokens.textMuted,
              ),
            ),
          if (payload.showLegend && payload.series.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            _ChartLegend(payload: payload),
          ],
        ],
      ),
    );
  }

  Widget _buildChart() {
    switch (payload.chartType) {
      case ChartType.line:
        return LineChart(_lineData());
      case ChartType.bar:
        return BarChart(_barData());
      case ChartType.pie:
      case ChartType.doughnut:
        return _InteractivePieChart(
          dataBuilder: (selectedSectionIndex, touchCallback) => _pieData(
            selectedSectionIndex: selectedSectionIndex,
            touchCallback: touchCallback,
          ),
          onSectionTap: widget.onCategoryTap == null
              ? null
              : (index) => widget.onCategoryTap!(_categoryAt(index)),
          tooltipBuilder: (section) =>
              '${_categoryAt(section.touchedSectionIndex)}\n'
              '${_seriesNameAt(0)}: '
              '${_formatNumber(section.touchedSection?.value ?? 0)}',
        );
      case ChartType.scatter:
        return ScatterChart(_scatterData());
      case ChartType.radar:
        return _InteractiveRadarChart(
          dataBuilder: (dataSetIndex, touchCallback) => _radarData(
            touchedDataSetIndex: dataSetIndex,
            touchCallback: touchCallback,
          ),
          onEntryTap: widget.onCategoryTap == null
              ? null
              : (index) => widget.onCategoryTap!(_categoryAt(index)),
          tooltipBuilder: (spot) =>
              '${_categoryAt(spot.touchedRadarEntryIndex)}\n'
              '${_seriesNameAt(spot.touchedDataSetIndex)}: '
              '${_formatNumber(spot.touchedRadarEntry.value)}',
        );
    }
  }

  LineChartData _lineData() {
    final bars = payload.series.map((series) {
      final values = _valuesFor(series);
      return LineChartBarData(
        spots: [
          for (var index = 0; index < values.length; index++)
            FlSpot(index.toDouble(), values[index]),
        ],
        color: series.color,
        barWidth: 2.5,
        isCurved: payload.lineCurved,
        dotData: FlDotData(show: payload.showDots),
        belowBarData: BarAreaData(show: false),
      );
    }).toList();
    final safeBars = bars.isEmpty
        ? [
            LineChartBarData(
              spots: const [FlSpot(0, 0), FlSpot(1, 0)],
              color: payload.colors.first,
              dotData: const FlDotData(show: false),
            ),
          ]
        : bars;
    final count = math.max(2, payload.categories.length).toDouble();
    final bounds = _axisBounds(
      payload.series.expand((series) => _valuesFor(series)),
    );
    return LineChartData(
      lineBarsData: safeBars,
      minX: 0,
      maxX: count - 1,
      minY: payload.minY ?? bounds.$1,
      maxY: payload.maxY ?? bounds.$2,
      titlesData: _titlesData(),
      gridData: FlGridData(show: payload.showGrid),
      borderData: _borderData(),
      lineTouchData: payload.showTooltips || widget.onCategoryTap != null
          ? LineTouchData(
              handleBuiltInTouches: payload.showTooltips,
              touchCallback: widget.onCategoryTap == null
                  ? null
                  : (event, response) {
                      if (event is FlTapUpEvent &&
                          response?.lineBarSpots?.isNotEmpty == true) {
                        widget.onCategoryTap!(
                          _categoryAt(response!.lineBarSpots!.first.spotIndex),
                        );
                      }
                    },
              touchTooltipData: LineTouchTooltipData(
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipColor: (_) => _background,
                getTooltipItems: payload.showTooltips
                    ? (spots) => [
                        for (final spot in spots)
                          LineTooltipItem(
                            '${_categoryAt(spot.spotIndex)}\n'
                            '${_seriesNameAt(spot.barIndex)}: ${_formatNumber(spot.y)}',
                            TextStyle(
                              color: context.appTokens.text,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ]
                    : (_) => const [],
              ),
            )
          : const LineTouchData(enabled: false),
    );
  }

  BarChartData _barData() {
    final groupCount = math.max(
      1,
      math.max(
        payload.categories.length,
        payload.series.fold<int>(0, (maxLength, series) {
          return math.max(maxLength, series.values.length);
        }),
      ),
    );
    final groups = [
      for (var index = 0; index < groupCount; index++)
        BarChartGroupData(
          x: index,
          barRods: [
            for (
              var seriesIndex = 0;
              seriesIndex < payload.series.length;
              seriesIndex++
            )
              BarChartRodData(
                toY: _valueAt(payload.series[seriesIndex], index),
                color: payload.series[seriesIndex].color,
                width: 12,
                borderRadius: BorderRadius.circular(2),
              ),
          ],
        ),
    ];
    final values = payload.series.expand((series) => _valuesFor(series));
    final bounds = _axisBounds(values);
    return BarChartData(
      barGroups: groups,
      minY: payload.minY ?? bounds.$1,
      maxY: payload.maxY ?? bounds.$2,
      rotationQuarterTurns:
          payload.barOrientation == ChartBarOrientation.horizontal ? 1 : 0,
      titlesData: _titlesData(),
      gridData: FlGridData(show: payload.showGrid),
      borderData: _borderData(),
      barTouchData: payload.showTooltips || widget.onCategoryTap != null
          ? BarTouchData(
              handleBuiltInTouches: payload.showTooltips,
              touchCallback: widget.onCategoryTap == null
                  ? null
                  : (event, response) {
                      final spot = response?.spot;
                      if (event is FlTapUpEvent && spot != null) {
                        widget.onCategoryTap!(
                          _categoryAt(spot.touchedBarGroupIndex),
                        );
                      }
                    },
              touchTooltipData: BarTouchTooltipData(
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipColor: (_) => _background,
                getTooltipItem: payload.showTooltips
                    ? (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                        '${_categoryAt(groupIndex)}\n'
                        '${_seriesNameAt(rodIndex)}: ${_formatNumber(rod.toY)}',
                        TextStyle(
                          color: context.appTokens.text,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : (_, _, _, _) => null,
              ),
            )
          : const BarTouchData(enabled: false),
    );
  }

  PieChartData _pieData({
    int? selectedSectionIndex,
    BaseTouchCallback<PieTouchResponse>? touchCallback,
  }) {
    final source = payload.series.isEmpty
        ? ChartSeries(values: [1])
        : payload.series.first;
    final values = _valuesFor(source);
    final safeValues = values.isEmpty ? [1.0] : values;
    final total = safeValues.fold<double>(0, (sum, value) => sum + value.abs());
    final normalized = total == 0
        ? List<double>.filled(safeValues.length, 1.0)
        : safeValues.map((value) => value.abs()).toList();
    return PieChartData(
      sections: [
        for (var index = 0; index < normalized.length; index++)
          PieChartSectionData(
            value: normalized[index],
            color: _colorAt(index, source.color),
            title: payload.showValues ? _formatNumber(safeValues[index]) : '',
            showTitle: payload.showValues,
            titleStyle: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            radius: selectedSectionIndex == index ? 60 : 54,
          ),
      ],
      centerSpaceRadius: payload.chartType == ChartType.doughnut
          ? 54 * payload.doughnutHoleRatio
          : 0,
      borderData: _borderData(),
      pieTouchData: payload.showTooltips || widget.onCategoryTap != null
          ? PieTouchData(touchCallback: touchCallback)
          : PieTouchData(enabled: false),
    );
  }

  ScatterChartData _scatterData() {
    final spots = <ScatterSpot>[];
    for (
      var seriesIndex = 0;
      seriesIndex < payload.series.length;
      seriesIndex++
    ) {
      final series = payload.series[seriesIndex];
      final points = series.points.isEmpty
          ? [
              for (var index = 0; index < series.values.length; index++)
                ChartPoint(x: index.toDouble(), y: series.values[index]),
            ]
          : series.points;
      spots.addAll(
        points.map(
          (point) => ScatterSpot(
            point.x,
            point.y,
            dotPainter: FlDotCirclePainter(radius: 4, color: series.color),
          ),
        ),
      );
    }
    final safeSpots = spots.isEmpty
        ? [
            ScatterSpot(
              0,
              0,
              dotPainter: FlDotCirclePainter(
                radius: 4,
                color: payload.colors.first,
              ),
            ),
          ]
        : spots;
    final xBounds = _axisBounds(safeSpots.map((spot) => spot.x));
    final yBounds = _axisBounds(safeSpots.map((spot) => spot.y));
    return ScatterChartData(
      scatterSpots: safeSpots,
      minX: xBounds.$1,
      maxX: xBounds.$2,
      minY: payload.minY ?? yBounds.$1,
      maxY: payload.maxY ?? yBounds.$2,
      titlesData: _titlesData(),
      gridData: FlGridData(show: payload.showGrid),
      borderData: _borderData(),
      scatterTouchData: payload.showTooltips || widget.onCategoryTap != null
          ? ScatterTouchData(
              handleBuiltInTouches: payload.showTooltips,
              touchCallback: widget.onCategoryTap == null
                  ? null
                  : (event, response) {
                      final spot = response?.touchedSpot;
                      if (event is FlTapUpEvent && spot != null) {
                        widget.onCategoryTap!(_categoryAt(spot.spot.x.round()));
                      }
                    },
              touchTooltipData: ScatterTouchTooltipData(
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipColor: (_) => _background,
                getTooltipItems: payload.showTooltips
                    ? (spot) => ScatterTooltipItem(
                        'X: ${_formatNumber(spot.x)}\nY: ${_formatNumber(spot.y)}',
                        textStyle: TextStyle(
                          color: context.appTokens.text,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : (_) => null,
              ),
            )
          : ScatterTouchData(enabled: false),
    );
  }

  RadarChartData _radarData({
    int? touchedDataSetIndex,
    BaseTouchCallback<RadarTouchResponse>? touchCallback,
  }) {
    final count = math.max(
      3,
      math.max(
        payload.categories.length,
        payload.series.fold<int>(0, (maxLength, series) {
          return math.max(maxLength, series.values.length);
        }),
      ),
    );
    final dataSets = [
      for (var index = 0; index < math.max(1, payload.series.length); index++)
        RadarDataSet(
          dataEntries: [
            for (var entryIndex = 0; entryIndex < count; entryIndex++)
              RadarEntry(
                value: payload.series.isEmpty
                    ? 0
                    : _valueAt(payload.series[index], entryIndex),
              ),
          ],
          fillColor: _colorAt(
            index,
            payload.colors.first,
          ).withValues(alpha: touchedDataSetIndex == index ? 0.3 : 0.18),
          borderColor: _colorAt(index, payload.colors.first),
          borderWidth: touchedDataSetIndex == index ? 3 : 2,
          entryRadius: 3,
        ),
    ];
    return RadarChartData(
      dataSets: dataSets,
      radarShape: RadarShape.polygon,
      radarBackgroundColor: _background,
      radarBorderData: BorderSide(
        color: _border,
        width: payload.showAxes ? 1.2 : 0,
      ),
      gridBorderData: BorderSide(
        color: _border.withValues(alpha: payload.showGrid ? 1 : 0),
        width: payload.showGrid ? 1 : 0,
      ),
      tickBorderData: BorderSide(
        color: _border.withValues(alpha: payload.showGrid ? 0.7 : 0),
        width: payload.showGrid ? 1 : 0,
      ),
      titleTextStyle: TextStyle(color: _muted, fontSize: 9),
      ticksTextStyle: TextStyle(color: _muted, fontSize: 8),
      tickCount: 4,
      getTitle: (index, angle) =>
          RadarChartTitle(text: _categoryAt(index), angle: angle),
      radarTouchData: payload.showTooltips || widget.onCategoryTap != null
          ? RadarTouchData(touchCallback: touchCallback)
          : RadarTouchData(enabled: false),
    );
  }

  FlTitlesData _titlesData() {
    if (!payload.showAxes) return const FlTitlesData(show: false);
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: const AxisTitles(
        sideTitles: SideTitles(showTitles: true, reservedSize: 28),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 22,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            child: Text(
              _categoryAt(value.round()),
              style: TextStyle(color: _muted, fontSize: 9),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }

  FlBorderData _borderData() => FlBorderData(
    show: payload.showAxes,
    border: Border.all(color: _border, width: 1),
  );

  List<double> _valuesFor(ChartSeries series) => series.values.isEmpty
      ? [for (final point in series.points) point.y]
      : series.values;

  double _valueAt(ChartSeries series, int index) {
    final values = _valuesFor(series);
    return index < values.length ? values[index] : 0;
  }

  String _categoryAt(int index) {
    if (index >= 0 && index < payload.categories.length) {
      return payload.categories[index];
    }
    return '${index + 1}';
  }

  String _seriesNameAt(int index) {
    if (index >= 0 && index < payload.series.length) {
      return payload.series[index].name;
    }
    return 'Series ${index + 1}';
  }

  Color _colorAt(int index, Color fallback) {
    if (payload.colors.isNotEmpty) {
      return payload.colors[index % payload.colors.length];
    }
    return fallback;
  }

  (double, double) _axisBounds(Iterable<double> values) {
    final finite = values.where((value) => value.isFinite).toList();
    var minY = finite.isEmpty
        ? 0.0
        : math.min(0.0, finite.reduce((a, b) => a < b ? a : b)).toDouble();
    var maxY = finite.isEmpty
        ? 1.0
        : math.max(0.0, finite.reduce((a, b) => a > b ? a : b)).toDouble();
    minY = payload.minY ?? minY;
    maxY = payload.maxY ?? maxY;
    if (minY > maxY) (minY, maxY) = (maxY, minY);
    if (minY == maxY) return (minY - 1, maxY + 1);
    return (minY, maxY);
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }
}

class _InteractivePieChart extends StatefulWidget {
  final PieChartData Function(
    int? selectedSectionIndex,
    BaseTouchCallback<PieTouchResponse>? touchCallback,
  )
  dataBuilder;
  final ValueChanged<int>? onSectionTap;
  final String Function(PieTouchedSection section) tooltipBuilder;

  const _InteractivePieChart({
    required this.dataBuilder,
    required this.tooltipBuilder,
    this.onSectionTap,
  });

  @override
  State<_InteractivePieChart> createState() => _InteractivePieChartState();
}

class _InteractivePieChartState extends State<_InteractivePieChart> {
  int? _selectedSectionIndex;
  String? _tooltip;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PieChart(widget.dataBuilder(_selectedSectionIndex, _handleTouch)),
        if (_tooltip != null) _ChartTouchLabel(text: _tooltip!),
      ],
    );
  }

  void _handleTouch(FlTouchEvent event, PieTouchResponse? response) {
    final section = response?.touchedSection;
    if (!event.isInterestedForInteractions ||
        section == null ||
        section.touchedSectionIndex < 0) {
      if (_selectedSectionIndex != null || _tooltip != null) {
        setState(() {
          _selectedSectionIndex = null;
          _tooltip = null;
        });
      }
      return;
    }

    final selectedIndex = section.touchedSectionIndex;
    if (event is FlTapUpEvent) widget.onSectionTap?.call(selectedIndex);
    final tooltip = widget.tooltipBuilder(section);
    if (_selectedSectionIndex == selectedIndex && _tooltip == tooltip) return;
    setState(() {
      _selectedSectionIndex = selectedIndex;
      _tooltip = tooltip;
    });
  }
}

class _InteractiveRadarChart extends StatefulWidget {
  final RadarChartData Function(
    int? touchedDataSetIndex,
    BaseTouchCallback<RadarTouchResponse>? touchCallback,
  )
  dataBuilder;
  final ValueChanged<int>? onEntryTap;
  final String Function(RadarTouchedSpot spot) tooltipBuilder;

  const _InteractiveRadarChart({
    required this.dataBuilder,
    required this.tooltipBuilder,
    this.onEntryTap,
  });

  @override
  State<_InteractiveRadarChart> createState() => _InteractiveRadarChartState();
}

class _InteractiveRadarChartState extends State<_InteractiveRadarChart> {
  RadarTouchedSpot? _touchedSpot;
  String? _tooltip;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RadarChart(
          widget.dataBuilder(_touchedSpot?.touchedDataSetIndex, _handleTouch),
        ),
        if (_tooltip != null) _ChartTouchLabel(text: _tooltip!),
      ],
    );
  }

  void _handleTouch(FlTouchEvent event, RadarTouchResponse? response) {
    final spot = response?.touchedSpot;
    if (!event.isInterestedForInteractions || spot == null) {
      if (_touchedSpot != null || _tooltip != null) {
        setState(() {
          _touchedSpot = null;
          _tooltip = null;
        });
      }
      return;
    }

    if (event is FlTapUpEvent) {
      widget.onEntryTap?.call(spot.touchedRadarEntryIndex);
    }
    final tooltip = widget.tooltipBuilder(spot);
    if (_touchedSpot == spot && _tooltip == tooltip) return;
    setState(() {
      _touchedSpot = spot;
      _tooltip = tooltip;
    });
  }
}

class _ChartTouchLabel extends StatelessWidget {
  final String text;

  const _ChartTouchLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return Align(
      alignment: Alignment.topRight,
      child: IgnorePointer(
        child: DecoratedBox(
          key: const ValueKey('chart-touch-label-surface'),
          decoration: BoxDecoration(
            color: tokens.panelElevated,
            borderRadius: BorderRadius.circular(tokens.controlRadius),
            border: Border.all(
              color: tokens.panelBorder,
              width: AppBorder.thin,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: AppSpacing.xs,
            ),
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tokens.text,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  final ChartPayload payload;

  const _ChartLegend({required this.payload});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < payload.series.length; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            _LegendItem(
              color: payload.series[index].color,
              label: payload.series[index].name,
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.appTokens.textMuted, fontSize: 9),
        ),
      ],
    );
  }
}
