import 'dart:typed_data';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';

class ImageCropScreen extends StatefulWidget {
  final Uint8List imageData;
  final void Function(Uint8List croppedBytes)? onCropped;
  final void Function(Uint8List croppedBytes, Rect imageArea)?
  onCroppedWithArea;
  final Rect? initialArea;

  const ImageCropScreen({
    super.key,
    required this.imageData,
    this.onCropped,
    this.onCroppedWithArea,
    this.initialArea,
  }) : assert(onCropped != null || onCroppedWithArea != null);

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  final CropController _controller = CropController();
  Rect? _imageArea;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return UiPageScaffold(
      title: Text(
        'CROP IMAGE',
        style: Theme.of(context).textTheme.titleSmall!.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
      leading: UiIconButton(
        icon: Icons.arrow_back,
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      actions: [
        UiIconButton(
          icon: Icons.undo,
          tooltip: 'Undo',
          onPressed: _controller.undo,
        ),
        UiButton(
          onPressed: _controller.crop,
          prefix: const Icon(Icons.crop, size: 16),
          child: const Text('CROP'),
        ),
      ],
      child: Crop(
        image: widget.imageData,
        controller: _controller,
        initialRectBuilder: widget.initialArea == null
            ? null
            : InitialRectBuilder.withArea(widget.initialArea!),
        onMoved: (_, imageArea) => _imageArea = imageArea,
        onCropped: (result) {
          switch (result) {
            case CropSuccess(:final croppedImage):
              final imageArea = _imageArea;
              if (widget.onCroppedWithArea != null && imageArea != null) {
                widget.onCroppedWithArea!(croppedImage, imageArea);
              } else {
                widget.onCropped?.call(croppedImage);
              }
              Navigator.of(context).pop();
            case CropFailure():
              showUiToast(
                context,
                'Crop failed',
                variant: UiToastVariant.error,
              );
          }
        },
        baseColor: tokens.canvas,
        maskColor: Colors.black.withValues(alpha: 0.6),
        radius: 8,
        progressIndicator: const UiProgressIndicator(),
      ),
    );
  }
}
