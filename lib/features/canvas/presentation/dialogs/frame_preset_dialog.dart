import 'package:flutter/material.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/canvas/utils/frame_presets.dart';

class FramePresetDialog extends StatefulWidget {
  final FramePreset? currentPreset;
  final bool isLandscape;
  final void Function(FramePreset preset, bool isLandscape) onSelectPreset;

  const FramePresetDialog({
    super.key,
    this.currentPreset,
    this.isLandscape = false,
    required this.onSelectPreset,
  });

  @override
  State<FramePresetDialog> createState() => _FramePresetDialogState();
}

class _FramePresetDialogState extends State<FramePresetDialog> {
  late bool _isLandscape;
  FramePresetCategory _activeTab = FramePresetCategory.mobile;

  @override
  void initState() {
    super.initState();
    _isLandscape = widget.isLandscape;
    if (widget.currentPreset != null) {
      _activeTab = widget.currentPreset!.category;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final compact = AppResponsive.isCompact(context);
    final filtered = FramePresetsCatalog.presets
        .where((p) => p.category == _activeTab)
        .toList();
    final width = AppResponsive.dialogWidth(context, preferred: 620);
    final height = AppResponsive.dialogHeight(context, preferred: 520);

    return UiDialog(
      semanticsLabel: 'Frame device and artboard presets',
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.crop_free, color: tokens.accent, size: 22),
                        const SizedBox(width: AppSpacing.md - AppSpacing.xxs),
                        Expanded(
                          child: Text(
                            'FRAME DEVICE & ARTBOARD PRESETS',
                            style: style.titleTextStyle,
                          ),
                        ),
                        UiIconButton(
                          icon: Icons.close,
                          tooltip: 'Close frame presets',
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        _buildOrientationButton(
                          icon: Icons.stay_current_portrait,
                          label: 'Portrait',
                          isSelected: !_isLandscape,
                          onTap: () => setState(() => _isLandscape = false),
                        ),
                        _buildOrientationButton(
                          icon: Icons.stay_current_landscape,
                          label: 'Landscape',
                          isSelected: _isLandscape,
                          onTap: () => setState(() => _isLandscape = true),
                        ),
                      ],
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Icon(Icons.crop_free, color: tokens.accent, size: 22),
                    const SizedBox(width: AppSpacing.md - AppSpacing.xxs),
                    Expanded(
                      child: Text(
                        'FRAME DEVICE & ARTBOARD PRESETS',
                        style: style.titleTextStyle,
                      ),
                    ),
                    _buildOrientationButton(
                      icon: Icons.stay_current_portrait,
                      label: 'Portrait',
                      isSelected: !_isLandscape,
                      onTap: () => setState(() => _isLandscape = false),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _buildOrientationButton(
                      icon: Icons.stay_current_landscape,
                      label: 'Landscape',
                      isSelected: _isLandscape,
                      onTap: () => setState(() => _isLandscape = true),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    UiIconButton(
                      icon: Icons.close,
                      tooltip: 'Close frame presets',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              const SizedBox(height: AppSpacing.lg),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: FramePresetCategory.values.map((cat) {
                    final selected = _activeTab == cat;
                    return Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: UiButton(
                        onPressed: () => setState(() => _activeTab = cat),
                        variant: selected
                            ? UiButtonVariant.primary
                            : UiButtonVariant.outline,
                        size: UiButtonSize.sm,
                        child: Text(cat.name.toUpperCase()),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: width < 480 ? 420 : 280,
                    childAspectRatio: 2.8,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final preset = filtered[index];
                    final selected = widget.currentPreset?.id == preset.id;
                    final w = preset.getWidth(_isLandscape).toInt();
                    final h = preset.getHeight(_isLandscape).toInt();
                    return Semantics(
                      button: true,
                      selected: selected,
                      label: '${preset.name}, $w by $h pixels',
                      child: UiButton(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onSelectPreset(preset, _isLandscape);
                        },
                        variant: selected
                            ? UiButtonVariant.primary
                            : UiButtonVariant.outline,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              preset.icon,
                              color: selected ? tokens.accent : tokens.info,
                              size: 20,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Flexible(
                              fit: FlexFit.loose,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    preset.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium!
                                        .copyWith(
                                          color: tokens.text,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: AppSpacing.xxs),
                                  Text(
                                    '$w × $h px',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall!
                                        .copyWith(
                                          color: tokens.accent,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrientationButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) => UiButton(
    onPressed: onTap,
    variant: isSelected ? UiButtonVariant.primary : UiButtonVariant.outline,
    size: UiButtonSize.sm,
    prefix: Icon(icon),
    child: Text(label),
  );
}
