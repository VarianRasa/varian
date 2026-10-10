import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:varian/app/theme.dart';

import 'model3d_rendering.dart';

class Model3DPreviewPane extends StatefulWidget {
  final Model3DSceneSnapshot snapshot;
  final bool checker;
  final Color canvasColor;
  final Color panelColor;
  final Color borderColor;
  final Color foregroundColor;
  final Color mutedColor;

  const Model3DPreviewPane({
    required this.snapshot,
    required this.checker,
    required this.canvasColor,
    required this.panelColor,
    required this.borderColor,
    required this.foregroundColor,
    required this.mutedColor,
    super.key,
  });

  @override
  State<Model3DPreviewPane> createState() => _Model3DPreviewPaneState();
}

class _Model3DPreviewPaneState extends State<Model3DPreviewPane> {
  ui.Image? _decodedImage;
  Uint8List? _decodedBytes;
  int _decodeGeneration = 0;

  @override
  void initState() {
    super.initState();
    _decodeBytes();
  }

  @override
  void didUpdateWidget(covariant Model3DPreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
          oldWidget.snapshot.textureBytes,
          widget.snapshot.textureBytes,
        ) ||
        oldWidget.snapshot.textureWidth != widget.snapshot.textureWidth ||
        oldWidget.snapshot.textureHeight != widget.snapshot.textureHeight) {
      _decodeBytes();
    }
  }

  Future<void> _decodeBytes() async {
    final bytes = widget.snapshot.textureBytes;
    final width = widget.snapshot.textureWidth;
    final height = widget.snapshot.textureHeight;
    final generation = ++_decodeGeneration;
    _decodedImage?.dispose();
    _decodedImage = null;
    _decodedBytes = bytes;
    if (bytes == null || width <= 0 || height <= 0) {
      if (mounted) setState(() {});
      return;
    }

    final completer = _ImageCompleter();
    ui.decodeImageFromPixels(
      bytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    if (!mounted || generation != _decodeGeneration) {
      image.dispose();
      return;
    }
    _decodedImage = image;
    setState(() {});
  }

  @override
  void dispose() {
    _decodeGeneration++;
    _decodedImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final texture = _buildTexture(snapshot);
    final checkerLightColor = Color.lerp(
      widget.canvasColor,
      widget.foregroundColor,
      0.08,
    )!;
    final checkerDarkColor = Color.lerp(
      widget.canvasColor,
      widget.foregroundColor,
      0.2,
    )!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: widget.panelColor,
        border: Border.all(color: widget.borderColor.withValues(alpha: 0.64)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _PreviewBackgroundPainter(
              color: Color(snapshot.fallbackColor),
              checker: widget.checker,
              checkerLightColor: checkerLightColor,
              checkerDarkColor: checkerDarkColor,
            ),
          ),
          ?texture,
          if (snapshot.hasUv)
            CustomPaint(
              painter: _UvLayoutPainter(
                triangles: snapshot.uvTriangles,
                color: widget.foregroundColor,
              ),
            ),
          if (!snapshot.hasUv)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  'UV layout unavailable',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: widget.mutedColor, fontSize: 10),
                ),
              ),
            ),
          Positioned(
            left: AppSpacing.xs + AppSpacing.xxs,
            right: AppSpacing.xs + AppSpacing.xxs,
            bottom: AppSpacing.xs + AppSpacing.xxs,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.panelColor.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: widget.borderColor.withValues(alpha: 0.42),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs + AppSpacing.xxs,
                  vertical: AppSpacing.xs,
                ),
                child: Text(
                  snapshot.hasTexture
                      ? '${snapshot.channelLabel} • ${snapshot.textureWidth}×${snapshot.textureHeight}'
                      : '${snapshot.channelLabel} • scalar fallback',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.foregroundColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildTexture(Model3DSceneSnapshot snapshot) {
    if (widget.checker) return null;
    final image = _decodedImage;
    if (image != null && identical(_decodedBytes, snapshot.textureBytes)) {
      return RawImage(
        image: image,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    }
    final url = snapshot.textureUrl?.trim();
    if (url == null || url.isEmpty || snapshot.textureBytes != null) {
      return null;
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}

class _ImageCompleter {
  final Completer<ui.Image> _completer = Completer<ui.Image>();

  Future<ui.Image> get future => _completer.future;

  void complete(ui.Image image) => _completer.complete(image);
}

class _PreviewBackgroundPainter extends CustomPainter {
  final Color color;
  final bool checker;
  final Color checkerLightColor;
  final Color checkerDarkColor;

  const _PreviewBackgroundPainter({
    required this.color,
    required this.checker,
    required this.checkerLightColor,
    required this.checkerDarkColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    if (!checker) return;

    const tile = 16.0;
    final paint = Paint();
    for (var y = 0.0; y < size.height; y += tile) {
      for (var x = 0.0; x < size.width; x += tile) {
        paint.color = ((x / tile).floor() + (y / tile).floor()) % 2 == 0
            ? checkerLightColor
            : checkerDarkColor;
        canvas.drawRect(Rect.fromLTWH(x, y, tile, tile), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewBackgroundPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.checker != checker ||
      oldDelegate.checkerLightColor != checkerLightColor ||
      oldDelegate.checkerDarkColor != checkerDarkColor;
}

class _UvLayoutPainter extends CustomPainter {
  final List<Model3DUvTriangle> triangles;
  final Color color;

  const _UvLayoutPainter({required this.triangles, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 8.0;
    final bounds = Rect.fromLTWH(
      padding,
      padding,
      (size.width - padding * 2).clamp(0, double.infinity),
      (size.height - padding * 2).clamp(0, double.infinity),
    );
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;

    canvas.drawRect(bounds, paint..color = color.withValues(alpha: 0.22));
    for (final triangle in triangles) {
      final path = Path()
        ..moveTo(
          bounds.left + _wrap(triangle.u1) * bounds.width,
          bounds.bottom - _wrap(triangle.v1) * bounds.height,
        )
        ..lineTo(
          bounds.left + _wrap(triangle.u2) * bounds.width,
          bounds.bottom - _wrap(triangle.v2) * bounds.height,
        )
        ..lineTo(
          bounds.left + _wrap(triangle.u3) * bounds.width,
          bounds.bottom - _wrap(triangle.v3) * bounds.height,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  double _wrap(double value) {
    final wrapped = value % 1;
    return wrapped < 0 ? wrapped + 1 : wrapped;
  }

  @override
  bool shouldRepaint(covariant _UvLayoutPainter oldDelegate) =>
      oldDelegate.triangles != triangles || oldDelegate.color != color;
}
