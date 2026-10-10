import 'package:flutter/material.dart';

class DesktopWindowResizeArea extends StatelessWidget {
  final Widget child;
  final bool enabled;

  const DesktopWindowResizeArea({
    super.key,
    required this.child,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) => child;
}
