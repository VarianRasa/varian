import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:varian/app/platform/desktop_window_manager.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/desktop_window_resize_area.dart';
import 'package:varian/app/widgets/varian_logo.dart';

/// Hosts the Windows-only frame chrome.
class DesktopWindowTitleBar extends StatefulWidget {
  final Widget child;

  const DesktopWindowTitleBar({super.key, required this.child});

  @override
  State<DesktopWindowTitleBar> createState() => _DesktopWindowTitleBarState();
}

class _DesktopWindowTitleBarState extends State<DesktopWindowTitleBar> {
  bool _maximized = false;

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    if (_isWindows) {
      desktopWindowManager.addListener(_handleWindowStateChanged);
      unawaited(_refreshWindowState());
    }
  }

  @override
  void dispose() {
    if (_isWindows) {
      desktopWindowManager.removeListener(_handleWindowStateChanged);
    }
    super.dispose();
  }

  void _handleWindowStateChanged(bool maximized) {
    if (mounted && _maximized != maximized) {
      setState(() => _maximized = maximized);
    }
  }

  Future<void> _refreshWindowState() async {
    try {
      final maximized = await desktopWindowManager.isMaximized();
      _handleWindowStateChanged(maximized);
    } on MissingPluginException {
      // Widget tests and older runners do not expose the native plugin.
    } on PlatformException {
      // Keep the editor usable if the native plugin cannot report state.
    }
  }

  Future<void> _invokeWindowMethod(String method) async {
    try {
      switch (method) {
        case 'minimize':
          await desktopWindowManager.minimize();
        case 'toggleMaximize':
          await desktopWindowManager.toggleMaximize();
        case 'close':
          await desktopWindowManager.close();
        case 'startDragging':
          await desktopWindowManager.startDragging();
      }
    } on MissingPluginException {
      // Widget tests and older runners do not expose the native plugin.
    } on PlatformException {
      // Keep the editor usable if the native plugin cannot handle the action.
    }
  }

  void _startDragging() => unawaited(_invokeWindowMethod('startDragging'));

  void _toggleMaximize() => unawaited(_invokeWindowMethod('toggleMaximize'));

  @override
  Widget build(BuildContext context) {
    if (!_isWindows) return widget.child;

    return DesktopWindowResizeArea(
      key: const ValueKey('desktop-window-resize-area'),
      enabled: !_maximized,
      child: Column(
        children: [
          _buildWindowsTitleBar(context),
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  AppTokens _windowTokens(BuildContext context) => context.appTokens;

  Color _windowSurface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? _windowTokens(context).canvas
      : _windowTokens(context).panel;

  Widget _buildWindowsTitleBar(BuildContext context) => DecoratedBox(
    key: const ValueKey('desktop-window-title-bar'),
    decoration: BoxDecoration(
      color: _windowSurface(context),
      border: Border(
        bottom: BorderSide(
          color: _windowTokens(context).panelBorder,
          width: AppBorder.thin,
        ),
      ),
    ),
    child: SizedBox(
      height: AppControlSize.regular,
      child: Row(
        children: [
          _buildDragRegion(
            key: const ValueKey('desktop-window-brand-drag-area'),
            child: _buildBrand(context),
          ),
          Expanded(
            child: _buildDragRegion(
              key: const ValueKey('desktop-window-empty-drag-area'),
              child: const SizedBox.expand(),
            ),
          ),
          _buildWindowButton(
            context,
            key: const ValueKey('window-minimize'),
            icon: Icons.remove,
            tooltip: 'Minimize window',
            method: 'minimize',
          ),
          _buildWindowButton(
            context,
            key: const ValueKey('window-maximize'),
            icon: _maximized ? Icons.filter_none : Icons.crop_square,
            tooltip: _maximized ? 'Restore window' : 'Maximize window',
            method: 'toggleMaximize',
          ),
          _buildWindowButton(
            context,
            key: const ValueKey('window-close'),
            icon: Icons.close,
            tooltip: 'Close window',
            method: 'close',
            close: true,
          ),
        ],
      ),
    ),
  );

  Widget _buildDragRegion({required Key key, required Widget child}) =>
      GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _toggleMaximize,
        onPanStart: (_) => _startDragging(),
        child: child,
      );

  Widget _buildBrand(BuildContext context) => Semantics(
    label: 'varian window title bar',
    child: SizedBox(
      width: 112,
      height: AppControlSize.regular,
      child: Padding(
        padding: const EdgeInsets.only(
          left: AppSpacing.sm,
          right: AppSpacing.xs + AppSpacing.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ExcludeSemantics(child: VarianBrandMark(size: 16)),
            const SizedBox(
              key: ValueKey('desktop-window-brand-gap'),
              width: AppSpacing.xs + AppSpacing.xxs / 2,
            ),
            Text(
              'varian',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _windowTokens(context).text,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildWindowButton(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String tooltip,
    required String method,
    bool close = false,
  }) {
    final tokens = context.appTokens;
    final dangerHover = Color.alphaBlend(
      tokens.danger.withValues(alpha: 0.12),
      _windowSurface(context),
    );
    return SizedBox(
      width: 42,
      height: AppControlSize.regular,
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          key: key,
          onPressed: () => unawaited(_invokeWindowMethod(method)),
          padding: EdgeInsets.zero,
          splashRadius: 15,
          hoverColor: close ? dangerHover : tokens.accentSoft,
          constraints: const BoxConstraints.tightFor(
            width: 42,
            height: AppControlSize.regular,
          ),
          icon: Icon(icon, size: 14, color: tokens.text),
        ),
      ),
    );
  }
}
