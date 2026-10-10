import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/drawing_paper_payload.dart';
import 'package:varian/features/drawing_paper/state/drawing_paper_provider.dart';

class StudioColorPanel extends ConsumerWidget {
  final DrawingPaperPayload initialPayload;

  const StudioColorPanel({super.key, required this.initialPayload});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(drawingStudioProviderFamily(initialPayload));
    final notifier = ref.read(
      drawingStudioProviderFamily(initialPayload).notifier,
    );
    final tokens = context.appTokens;

    const presetPalette = [
      Color(0xFF000000),
      Color(0xFFFFFFFF),
      Color(0xFF64748B),
      Color(0xFFEF4444),
      Color(0xFFF97316),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
      Color(0xFF06B6D4),
      Color(0xFF3B82F6),
      Color(0xFF6366F1),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
    ];

    return UiSurface(
      padding: const EdgeInsets.all(AppSpacing.sm),
      color: tokens.panel,
      borderRadius: BorderRadius.zero,
      child: SizedBox(
        width: 184,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const UiSectionHeader(title: 'COLOR STUDIO'),
              const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
              Row(
                children: [
                  UiButton(
                    semanticsLabel: 'Swap primary and secondary colors',
                    onPressed: notifier.swapColors,
                    variant: UiButtonVariant.ghost,
                    size: UiButtonSize.md,
                    child: const Icon(Icons.swap_calls_outlined),
                  ),
                  const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${state.primaryColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                          style: Theme.of(context).textTheme.labelSmall!
                              .copyWith(
                                color: tokens.text,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'Tap to swap',
                          style: Theme.of(context).textTheme.labelSmall!
                              .copyWith(color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'PALETTE',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs + AppSpacing.xxs,
                runSpacing: AppSpacing.xs + AppSpacing.xxs,
                children: presetPalette.map((color) {
                  final selected =
                      color.toARGB32() == state.primaryColor.toARGB32();
                  return _ColorSwatch(
                    color: color,
                    selected: selected,
                    label: 'Set color ${color.toARGB32().toRadixString(16)}',
                    borderColor: selected ? tokens.accent : tokens.panelBorder,
                    onTap: () => notifier.setPrimaryColor(color),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'RECENT COLORS',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: state.payload.colorHistory.map((hex) {
                  var parsed = Colors.black;
                  try {
                    parsed = Color(int.parse(hex.replaceFirst('#', '0xFF')));
                  } catch (_) {
                    // Ignore malformed legacy history entries.
                  }
                  return _ColorSwatch(
                    color: parsed,
                    selected: false,
                    size: 18,
                    label: 'Use recent color $hex',
                    borderColor: tokens.panelBorder,
                    onTap: () => notifier.setPrimaryColor(parsed),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool selected;
  final double size;
  final String label;
  final Color borderColor;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.label,
    required this.borderColor,
    required this.onTap,
    this.size = AppControlSize.touch,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        selected: selected,
        child: UiButton(
          onPressed: onTap,
          variant: selected ? UiButtonVariant.primary : UiButtonVariant.ghost,
          size: UiButtonSize.sm,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: borderColor,
                width: selected ? AppBorder.focus : AppBorder.thin,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
