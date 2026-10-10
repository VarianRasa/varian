import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/node_payload.dart';
import 'package:varian/features/canvas/state/tool_provider.dart';

class ChartPalette extends ConsumerWidget {
  final VoidCallback? onClose;

  const ChartPalette({this.onClose, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.appTokens;
    final selected = ref.watch(activeChartTypeProvider);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 344),
      child: UiSurface(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UiSectionHeader(
              title: 'CHART TYPES',
              trailing: UiIconButton(
                tooltip: 'Close chart types',
                icon: Icons.close,
                onPressed: onClose,
                variant: UiButtonVariant.ghost,
                size: UiButtonSize.sm,
              ),
            ),
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            Text(
              'Drag a chart to the canvas or tap to select it.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs + AppSpacing.xxs,
              runSpacing: AppSpacing.xs + AppSpacing.xxs,
              children: [
                for (final chartType in ChartType.values)
                  _ChartTypeTile(
                    chartType: chartType,
                    selected: chartType == selected,
                    onPressed: () {
                      ref.read(activeChartTypeProvider.notifier).state =
                          chartType;
                      ref
                          .read(activeToolProvider.notifier)
                          .setTool(CanvasTool.chart);
                      onClose?.call();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartTypeTile extends StatelessWidget {
  final ChartType chartType;
  final bool selected;
  final VoidCallback onPressed;

  const _ChartTypeTile({
    required this.chartType,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final button = Tooltip(
      message: _chartLabel(chartType),
      child: Semantics(
        button: true,
        container: true,
        selected: selected,
        focusable: true,
        excludeSemantics: true,
        label: _chartLabel(chartType),
        hint: 'Drag to canvas or tap to select',
        onTap: onPressed,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 101,
            height: 64,
            child: UiSurface(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs + AppSpacing.xxs / 2,
                vertical: AppSpacing.sm - AppSpacing.xxs,
              ),
              borderRadius: BorderRadius.circular(tokens.controlRadius),
              color: selected
                  ? Color.alphaBlend(
                      tokens.accent.withValues(alpha: 0.12),
                      tokens.panelElevated,
                    )
                  : tokens.panelElevated,
              borderColor: selected ? tokens.accent : tokens.panelBorder,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _chartIcon(chartType),
                    size: 22,
                    color: selected ? tokens.accent : tokens.textMuted,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    _chartLabel(chartType),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected ? tokens.text : tokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Draggable<ChartType>(
      data: chartType,
      maxSimultaneousDrags: 1,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 101,
          height: 64,
          child: Center(
            child: Icon(
              _chartIcon(chartType),
              size: AppControlSize.extraSmall,
              color: tokens.accent,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: button),
      child: button,
    );
  }
}

String _chartLabel(ChartType chartType) => switch (chartType) {
  ChartType.line => 'Line',
  ChartType.bar => 'Bar / Column',
  ChartType.pie => 'Pie',
  ChartType.doughnut => 'Doughnut',
  ChartType.scatter => 'Scatter',
  ChartType.radar => 'Radar',
};

IconData _chartIcon(ChartType chartType) => switch (chartType) {
  ChartType.line => Icons.show_chart,
  ChartType.bar => Icons.bar_chart,
  ChartType.pie => Icons.pie_chart,
  ChartType.doughnut => Icons.donut_large,
  ChartType.scatter => Icons.scatter_plot,
  ChartType.radar => Icons.radar,
};
