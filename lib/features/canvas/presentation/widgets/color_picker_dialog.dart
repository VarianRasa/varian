import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/canvas/presentation/widgets/color_picker_primitives.dart';

class ColorPickerDialog extends StatefulWidget {
  final BuildContext dialogContext;
  final String dialogLabel;
  final String title;
  final Color currentColor;
  final ValueChanged<Color> onColorChanged;

  const ColorPickerDialog({
    required this.dialogContext,
    required this.dialogLabel,
    required this.title,
    required this.currentColor,
    required this.onColorChanged,
    super.key,
  });

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  static const _channelKeys = ['r', 'g', 'b', 'h', 's', 'v'];
  static final _hexInputPattern = RegExp(r'^#?[0-9A-F]{0,8}$');
  static final _completeHexPattern = RegExp(
    r'^#?(?:[0-9A-F]{3}|[0-9A-F]{6}|[0-9A-F]{8})$',
  );
  static final _hexInputFormatter = TextInputFormatter.withFunction((
    oldValue,
    newValue,
  ) {
    final text = newValue.text.toUpperCase();
    if (!_hexInputPattern.hasMatch(text)) return oldValue;
    return newValue.copyWith(text: text);
  });

  late HSVColor _hsvColor;
  late final TextEditingController _hexController;
  late final Map<String, TextEditingController> _channelControllers;
  bool _hexHasError = false;
  bool _syncingHexController = false;
  bool _syncingChannelControllers = false;

  @override
  void initState() {
    super.initState();
    _hsvColor = HSVColor.fromColor(widget.currentColor);
    _hexController = TextEditingController(text: _hexValue);
    _channelControllers = {
      for (final channel in _channelKeys)
        channel: TextEditingController(text: _channelValue(channel)),
    };
  }

  @override
  void dispose() {
    _hexController.dispose();
    for (final controller in _channelControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String get _hexValue =>
      colorToHex(_hsvColor.toColor(), includeHashSign: true, enableAlpha: true);

  String _channelValue(String channel) {
    final color = _hsvColor.toColor();
    return switch (channel) {
      'r' => '${(color.r * 255).round()}',
      'g' => '${(color.g * 255).round()}',
      'b' => '${(color.b * 255).round()}',
      'h' => '${_hsvColor.hue.round()}',
      's' => '${(_hsvColor.saturation * 100).round()}',
      'v' => '${(_hsvColor.value * 100).round()}',
      _ => '',
    };
  }

  void _syncChannelValues() {
    _syncingChannelControllers = true;
    for (final channel in _channelKeys) {
      final controller = _channelControllers[channel]!;
      final value = _channelValue(channel);
      if (controller.text == value) continue;
      controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
    _syncingChannelControllers = false;
  }

  void _handleChannelChanged(String channel, String rawValue) {
    if (_syncingChannelControllers) return;
    final parsed = int.tryParse(rawValue);
    if (parsed == null || parsed.toString() == _channelValue(channel)) {
      return;
    }

    if (channel == 'r' || channel == 'g' || channel == 'b') {
      final current = _hsvColor.toColor();
      final red = channel == 'r'
          ? parsed.clamp(0, 255).toInt()
          : (current.r * 255).round();
      final green = channel == 'g'
          ? parsed.clamp(0, 255).toInt()
          : (current.g * 255).round();
      final blue = channel == 'b'
          ? parsed.clamp(0, 255).toInt()
          : (current.b * 255).round();
      _setHsvColor(
        HSVColor.fromColor(
          Color.from(
            alpha: _hsvColor.alpha,
            red: red / 255,
            green: green / 255,
            blue: blue / 255,
          ),
        ),
      );
      return;
    }

    final bounded = switch (channel) {
      'h' => parsed.clamp(0, 360).toDouble(),
      's' || 'v' => parsed.clamp(0, 100) / 100,
      _ => null,
    };
    if (bounded == null) return;

    _setHsvColor(switch (channel) {
      'h' => _hsvColor.withHue(bounded),
      's' => _hsvColor.withSaturation(bounded),
      'v' => _hsvColor.withValue(bounded),
      _ => _hsvColor,
    });
  }

  void _restoreChannelValue(String channel) {
    final controller = _channelControllers[channel]!;
    final value = _channelValue(channel);
    if (controller.text == value) return;

    _syncingChannelControllers = true;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _syncingChannelControllers = false;
  }

  void _syncHexValue(Color color) {
    final value = colorToHex(color, includeHashSign: true, enableAlpha: true);
    if (_hexController.text == value) return;

    _syncingHexController = true;
    _hexController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _syncingHexController = false;
  }

  void _setHsvColor(HSVColor color) {
    if (!mounted) return;
    final nextColor = color.toColor();
    setState(() {
      _hsvColor = color;
      _hexHasError = false;
    });
    _syncHexValue(nextColor);
    _syncChannelValues();
    widget.onColorChanged(nextColor);
  }

  void _handleHexChanged(String rawValue) {
    if (_syncingHexController) return;

    final value = rawValue.trim().toUpperCase();
    final color = _completeHexPattern.hasMatch(value)
        ? colorFromHex(value)
        : null;
    if (color == null) {
      final hasError = value.isNotEmpty;
      if (_hexHasError != hasError) {
        setState(() => _hexHasError = hasError);
      }
      return;
    }

    _setHsvColor(HSVColor.fromColor(color));
  }

  void _adjustHue(double delta) {
    final hue = (_hsvColor.hue + delta) % 360;
    _setHsvColor(_hsvColor.withHue(hue < 0 ? hue + 360 : hue));
  }

  void _adjustAlpha(double delta) {
    final alpha = (_hsvColor.alpha + delta).clamp(0.0, 1.0).toDouble();
    _setHsvColor(_hsvColor.withAlpha(alpha));
  }

  void _adjustValue(double delta) {
    final value = (_hsvColor.value + delta).clamp(0.0, 1.0).toDouble();
    _setHsvColor(_hsvColor.withValue(value));
  }

  Widget _buildSlider({
    required BuildContext context,
    required String label,
    required String value,
    required String increasedValue,
    required String decreasedValue,
    required Widget slider,
    required VoidCallback onIncrease,
    required VoidCallback onDecrease,
  }) {
    final tokens = context.appTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ExcludeSemantics(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium!.copyWith(
                    color: tokens.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: tokens.text),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Semantics(
          container: true,
          slider: true,
          label: label,
          value: value,
          increasedValue: increasedValue,
          decreasedValue: decreasedValue,
          onIncrease: onIncrease,
          onDecrease: onDecrease,
          child: SizedBox(height: AppControlSize.compact, child: slider),
        ),
      ],
    );
  }

  Widget _buildChannelField(String group, String channel) {
    final channelName = '$group ${channel.toUpperCase()} channel';
    final fieldLabel = switch (channel) {
      'h' => 'H°',
      's' || 'v' => '${channel.toUpperCase()}%',
      _ => channel.toUpperCase(),
    };
    return Expanded(
      child: Padding(
        padding: EdgeInsets.only(
          right: channel == 'b' || channel == 'v'
              ? 0
              : AppSpacing.xs + AppSpacing.xxs,
        ),
        child: Semantics(
          container: true,
          label: channelName,
          textField: true,
          child: UiTextField(
            key: ValueKey('color-picker-$channel'),
            controller: _channelControllers[channel],
            label: fieldLabel,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: false,
              signed: false,
            ),
            textInputAction: channel == 'v'
                ? TextInputAction.done
                : TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            onChanged: (value) => _handleChannelChanged(channel, value),
            onSubmitted: (_) => _restoreChannelValue(channel),
          ),
        ),
      ),
    );
  }

  Widget _buildChannelGroup(
    BuildContext context,
    String label,
    List<String> channels,
  ) {
    final tokens = context.appTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: tokens.textMuted,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            for (final channel in channels) _buildChannelField(label, channel),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final color = _hsvColor.toColor();
    final compact = AppResponsive.isCompact(context);
    final dialogWidth = AppResponsive.dialogWidth(context, preferred: 420);
    final dialogMaxHeight = AppResponsive.dialogHeight(context, preferred: 700);
    final hue = _hsvColor.hue.round();
    final saturation = (_hsvColor.saturation * 100).round();
    final value = (_hsvColor.value * 100).round();
    final alpha = (color.a * 100).round();

    return UiDialog(
      semanticsLabel: widget.dialogLabel,
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 420,
        maxHeight: 700,
      ),
      builder: (context, style) => SizedBox(
        width: dialogWidth,
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: dialogMaxHeight),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: style.titleTextStyle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      DecoratedBox(
                        key: const ValueKey('color-picker-selected-swatch'),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(
                            tokens.controlRadius,
                          ),
                          border: Border.all(
                            color: tokens.panelBorder,
                            width: AppBorder.thin,
                          ),
                        ),
                        child: const SizedBox.square(
                          dimension: AppControlSize.extraSmall,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          _hexValue,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall!
                              .copyWith(
                                color: tokens.textMuted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Semantics(
                    container: true,
                    button: true,
                    label: 'Color area',
                    value: 'Saturation $saturation%, value $value%',
                    increasedValue:
                        'Saturation $saturation%, value ${math.min(100, value + 5)}%',
                    decreasedValue:
                        'Saturation $saturation%, value ${math.max(0, value - 5)}%',
                    hint: 'Adjust saturation and value',
                    onIncrease: () => _adjustValue(0.05),
                    onDecrease: () => _adjustValue(-0.05),
                    child: DecoratedBox(
                      key: const ValueKey('color-picker-area-frame'),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          tokens.controlRadius,
                        ),
                        border: Border.all(
                          color: tokens.panelBorder,
                          width: AppBorder.thin,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          tokens.controlRadius,
                        ),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: InspectorColorPickerArea(
                            hsvColor: _hsvColor,
                            onColorChanged: _setHsvColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _buildSlider(
                    context: context,
                    label: 'Hue',
                    value: '$hue°',
                    increasedValue: '${(hue + 1) % 360}°',
                    decreasedValue: '${hue == 0 ? 359 : hue - 1}°',
                    slider: InspectorColorPickerSlider(
                      trackType: TrackType.hue,
                      hsvColor: _hsvColor,
                      onColorChanged: _setHsvColor,
                    ),
                    onIncrease: () => _adjustHue(1),
                    onDecrease: () => _adjustHue(-1),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildSlider(
                    context: context,
                    label: 'Alpha',
                    value: '$alpha%',
                    increasedValue: '${math.min(100, alpha + 1)}%',
                    decreasedValue: '${math.max(0, alpha - 1)}%',
                    slider: InspectorColorPickerSlider(
                      trackType: TrackType.alpha,
                      hsvColor: _hsvColor,
                      onColorChanged: _setHsvColor,
                    ),
                    onIncrease: () => _adjustAlpha(0.01),
                    onDecrease: () => _adjustAlpha(-0.01),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  DecoratedBox(
                    key: const ValueKey('color-picker-channel-frame'),
                    decoration: BoxDecoration(
                      color: tokens.panel,
                      borderRadius: BorderRadius.circular(tokens.controlRadius),
                      border: Border.all(
                        color: tokens.panelBorder,
                        width: AppBorder.thin,
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(tokens.spacing * 1.5),
                      child: compact
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildChannelGroup(context, 'RGB', [
                                  'r',
                                  'g',
                                  'b',
                                ]),
                                const SizedBox(height: AppSpacing.md),
                                _buildChannelGroup(context, 'HSV', [
                                  'h',
                                  's',
                                  'v',
                                ]),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _buildChannelGroup(context, 'RGB', [
                                    'r',
                                    'g',
                                    'b',
                                  ]),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: _buildChannelGroup(context, 'HSV', [
                                    'h',
                                    's',
                                    'v',
                                  ]),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Semantics(
                    container: true,
                    label: 'HEX color input',
                    textField: true,
                    child: UiTextField(
                      key: const ValueKey('color-picker-hex'),
                      controller: _hexController,
                      label: 'HEX',
                      hint: '#AARRGGBB',
                      description: _hexHasError
                          ? 'Use 3, 6, or 8 hexadecimal digits.'
                          : 'Use 3, 6, or 8 digits; 8 digits include alpha.',
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [_hexInputFormatter],
                      onChanged: _handleHexChanged,
                      onSubmitted: _handleHexChanged,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Align(
                    alignment: Alignment.centerRight,
                    child: UiButton(
                      semanticsLabel: 'Done',
                      onPressed: () => Navigator.of(widget.dialogContext).pop(),
                      variant: UiButtonVariant.primary,
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
