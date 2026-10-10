import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

enum AppWindowClass { compact, medium, expanded, wide }

abstract final class AppBreakpoints {
  static const compact = 600.0;
  static const medium = 840.0;
  static const expanded = 1180.0;
  static const wide = 1440.0;
  static const ultraWide = 1600.0;
  static const compactStatusTabs = 420.0;

  const AppBreakpoints._();
}

abstract final class AppResponsive {
  static AppWindowClass windowClass(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < AppBreakpoints.compact) return AppWindowClass.compact;
    if (width < AppBreakpoints.medium) return AppWindowClass.medium;
    if (width < AppBreakpoints.expanded) return AppWindowClass.expanded;
    return AppWindowClass.wide;
  }

  static bool isCompact(BuildContext context) =>
      windowClass(context) == AppWindowClass.compact;

  static bool isMedium(BuildContext context) =>
      windowClass(context) == AppWindowClass.medium;

  static bool isNarrow(BuildContext context) =>
      MediaQuery.sizeOf(context).width < AppBreakpoints.medium;

  static bool usesTouchLayout(BuildContext context) {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => true,
      _ => false,
    };
  }

  static EdgeInsets pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < AppBreakpoints.compact
        ? AppSpacing.md
        : width < AppBreakpoints.expanded
        ? AppSpacing.page
        : AppSpacing.pageWide;
    final vertical = width < AppBreakpoints.compact
        ? AppSpacing.md
        : AppSpacing.page;
    return EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical);
  }

  static EdgeInsets dialogPadding(BuildContext context) => EdgeInsets.all(
    MediaQuery.sizeOf(context).width < AppBreakpoints.compact
        ? AppSpacing.md
        : AppSpacing.page,
  );

  static double dialogWidth(
    BuildContext context, {
    required double preferred,
    double? maxWidth,
  }) {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final inset = viewportWidth < AppBreakpoints.compact
        ? AppSpacing.md
        : AppSpacing.page;
    final available = math.max(0.0, viewportWidth - inset * 2);
    return math
        .min(available, math.min(preferred, maxWidth ?? preferred))
        .toDouble();
  }

  static double dialogHeight(
    BuildContext context, {
    required double preferred,
    double? maxHeight,
  }) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final verticalInset = viewportHeight < 560.0
        ? AppSpacing.md
        : AppSpacing.page;
    final available = math.max(0.0, viewportHeight - verticalInset * 2);
    return math
        .min(available, math.min(preferred, maxHeight ?? preferred))
        .toDouble();
  }

  static BoxConstraints dialogConstraints(
    BuildContext context, {
    required double maxWidth,
    double? maxHeight,
    double minWidth = 0,
    double minHeight = 0,
  }) {
    final width = dialogWidth(context, preferred: maxWidth, maxWidth: maxWidth);
    final height = maxHeight == null
        ? null
        : dialogHeight(context, preferred: maxHeight, maxHeight: maxHeight);
    return BoxConstraints(
      minWidth: math.min(minWidth, width).toDouble(),
      maxWidth: width,
      minHeight: height == null
          ? minHeight
          : math.min(minHeight, height).toDouble(),
      maxHeight: height ?? double.infinity,
    );
  }

  static double compactPanelWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalInset = width < AppBreakpoints.compact
        ? AppSpacing.md
        : AppSpacing.page;
    return (width - horizontalInset).clamp(0.0, 420.0).toDouble();
  }

  static double compactPanelHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final available = (size.height - AppSpacing.page)
        .clamp(0.0, double.infinity)
        .toDouble();
    final preferred = size.width < AppBreakpoints.compact
        ? size.height * 0.52
        : size.height * 0.46;
    return preferred.clamp(0.0, math.min(420.0, available)).toDouble();
  }
}

extension AppResponsiveContext on BuildContext {
  AppWindowClass get appWindowClass => AppResponsive.windowClass(this);

  bool get isCompactLayout => AppResponsive.isCompact(this);

  bool get isNarrowLayout => AppResponsive.isNarrow(this);

  bool get usesTouchLayout => AppResponsive.usesTouchLayout(this);
}
