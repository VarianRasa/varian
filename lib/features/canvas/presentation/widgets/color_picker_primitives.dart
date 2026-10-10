import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class InspectorColorPickerArea extends StatelessWidget {
  final HSVColor hsvColor;
  final ValueChanged<HSVColor> onColorChanged;

  const InspectorColorPickerArea({
    required this.hsvColor,
    required this.onColorChanged,
    super.key,
  });

  void _handleGesture(
    Offset position,
    BuildContext context,
    double width,
    double height,
  ) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || width <= 0 || height <= 0) return;

    final local = box.globalToLocal(position);
    final saturation = (local.dx / width).clamp(0.0, 1.0).toDouble();
    final value = (1 - local.dy / height).clamp(0.0, 1.0).toDouble();
    onColorChanged(hsvColor.withSaturation(saturation).withValue(value));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      return RawGestureDetector(
        gestures: {
          _AlwaysWinPanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                _AlwaysWinPanGestureRecognizer
              >(() => _AlwaysWinPanGestureRecognizer(), (instance) {
                instance
                  ..onDown = (details) {
                    _handleGesture(
                      details.globalPosition,
                      context,
                      width,
                      height,
                    );
                  }
                  ..onUpdate = (details) {
                    _handleGesture(
                      details.globalPosition,
                      context,
                      width,
                      height,
                    );
                  };
              }),
        },
        child: SizedBox.expand(
          child: CustomPaint(painter: _RepaintingHsvPainter(hsvColor)),
        ),
      );
    },
  );
}

class InspectorColorPickerSlider extends StatelessWidget {
  final TrackType trackType;
  final HSVColor hsvColor;
  final ValueChanged<HSVColor> onColorChanged;

  const InspectorColorPickerSlider({
    required this.trackType,
    required this.hsvColor,
    required this.onColorChanged,
    super.key,
  });

  void _handleGesture(Offset position, BuildContext context, double width) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || width <= 30) return;

    final localDx = box.globalToLocal(position).dx - 15;
    final usableWidth = width - 30;
    final progress = (localDx.clamp(0.0, usableWidth) / usableWidth)
        .clamp(0.0, 1.0)
        .toDouble();

    switch (trackType) {
      case TrackType.hue:
        onColorChanged(hsvColor.withHue(progress * 359));
      case TrackType.alpha:
        onColorChanged(hsvColor.withAlpha(progress));
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      return RawGestureDetector(
        gestures: {
          _AlwaysWinPanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                _AlwaysWinPanGestureRecognizer
              >(() => _AlwaysWinPanGestureRecognizer(), (instance) {
                instance
                  ..onDown = (details) {
                    _handleGesture(details.globalPosition, context, width);
                  }
                  ..onUpdate = (details) {
                    _handleGesture(details.globalPosition, context, width);
                  };
              }),
        },
        child: SizedBox.expand(
          child: CustomPaint(
            painter: _ColorPickerSliderPainter(trackType, hsvColor),
          ),
        ),
      );
    },
  );
}

class _RepaintingHsvPainter extends HSVWithHueColorPainter {
  const _RepaintingHsvPainter(super.hsvColor);

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class _ColorPickerSliderPainter extends CustomPainter {
  final TrackType trackType;
  final HSVColor hsvColor;

  const _ColorPickerSliderPainter(this.trackType, this.hsvColor);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 30 || size.height <= 0) return;

    final trackSize = Size(size.width - 30, size.height / 5);
    canvas.save();
    canvas.translate(15, size.height * 0.4);
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Offset.zero & trackSize,
        Radius.circular(trackSize.height / 2),
      ),
    );
    TrackPainter(trackType, hsvColor).paint(canvas, trackSize);
    canvas.restore();

    final progress = switch (trackType) {
      TrackType.hue => hsvColor.hue / 360,
      TrackType.alpha => hsvColor.alpha,
      _ => 0.0,
    };
    final thumbOffset = 15 + (size.width - 30) * progress;
    final thumbColor = switch (trackType) {
      TrackType.hue => HSVColor.fromAHSV(1.0, hsvColor.hue, 1.0, 1.0).toColor(),
      TrackType.alpha => hsvColor.toColor().withValues(alpha: 1),
      _ => null,
    };

    canvas.save();
    canvas.translate(thumbOffset, size.height * 0.4);
    ThumbPainter(
      thumbColor: thumbColor,
      fullThumbColor: false,
    ).paint(canvas, Size(5, size.height / 4));
    canvas.restore();
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class _AlwaysWinPanGestureRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }

  @override
  String get debugDescription => 'alwaysWin';
}
