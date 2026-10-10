import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class DesktopWindowResizeArea extends StatelessWidget {
  final Widget child;
  final bool enabled;

  const DesktopWindowResizeArea({
    super.key,
    required this.child,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows || !enabled) return child;

    return DragToResizeArea(
      enableResizeEdges: ResizeEdge.values,
      resizeEdgeSize: 8,
      child: child,
    );
  }
}
