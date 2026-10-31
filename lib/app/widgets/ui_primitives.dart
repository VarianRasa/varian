import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mix/mix.dart';

import '../responsive.dart';
import '../theme.dart';
import '../theme_mode_provider.dart';

List<Widget> _flattenActionWidgets(Widget widget) {
  if (widget is! Row) return [widget];
  return widget.children
      .where((child) => child is! SizedBox)
      .expand(_flattenActionWidgets)
      .toList(growable: false);
}

Widget? _wrapActionWidgets(List<Widget> actions) => actions.isEmpty
    ? null
    : Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            if (index > 0) const SizedBox(width: AppSpacing.xxs),
            actions[index],
          ],
        ],
      );

class UiPageScaffold extends StatelessWidget {
  final Widget child;
  final Widget title;
  final Widget? leading;
  final double? leadingWidth;
  final List<Widget> actions;
  final Set<Key> compactActionKeys;
  final bool childPad;
  final bool showHeader;
  final bool useCompactActionsMenu;
  final bool compactActionsMenuAlways;
  final bool overlayHeader;

  const UiPageScaffold({
    required this.child,
    required this.title,
    this.leading,
    this.leadingWidth,
    this.actions = const [],
    this.compactActionKeys = const {},
    this.childPad = false,
    this.showHeader = true,
    this.useCompactActionsMenu = false,
    this.compactActionsMenuAlways = false,
    this.overlayHeader = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final compactHeader = viewportWidth < AppBreakpoints.ultraWide;
    final compactActionLayout = compactHeader;
    final compactMenuEnabled =
        useCompactActionsMenu &&
        (compactActionsMenuAlways || viewportWidth < AppBreakpoints.expanded);
    final compactActionPartition =
        compactMenuEnabled && compactActionKeys.isNotEmpty;
    final leadingActions = leading == null
        ? const <Widget>[]
        : _flattenActionWidgets(leading!);
    final inlineLeadingActions = compactActionPartition
        ? leadingActions
              .where((action) => compactActionKeys.contains(action.key))
              .toList(growable: false)
        : leadingActions;
    final overflowLeadingActions = compactActionPartition
        ? leadingActions
              .where((action) => !compactActionKeys.contains(action.key))
              .toList(growable: false)
        : leadingActions;
    final inlineActions = compactActionPartition
        ? actions
              .where((action) => compactActionKeys.contains(action.key))
              .toList(growable: false)
        : actions;
    final overflowActions = compactActionPartition
        ? actions
              .where((action) => !compactActionKeys.contains(action.key))
              .toList(growable: false)
        : actions;
    final compactMenuActions = [
      ...overflowLeadingActions.where((action) => action is! SizedBox),
      ...overflowActions.where((action) => action is! SizedBox),
    ];
    final showCompactOverflowMenu =
        compactMenuEnabled && compactMenuActions.isNotEmpty;
    final leadingInActions =
        compactHeader && leading != null && !compactActionPartition;
    final compactLeadingHeader = compactActionPartition
        ? _wrapActionWidgets(inlineLeadingActions)
        : null;
    final headerTitle =
        compactActionPartition || leading == null || leadingInActions
        ? title
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading!,
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: title),
            ],
          );
    final headerActions = showCompactOverflowMenu
        ? [
            _UiCompactActionsMenu(actions: compactMenuActions),
            if (compactActionPartition) ...inlineActions,
          ]
        : compactActionLayout && (actions.isNotEmpty || leadingInActions)
        ? [
            SizedBox(
              width: math.min(
                useCompactActionsMenu ? 840.0 : 280.0,
                math.max(136.0, viewportWidth * 0.62),
              ),
              height: 44,
              child: ClipRect(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxs,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (leadingInActions) ...[
                        leading!,
                        if (actions.isNotEmpty)
                          const SizedBox(width: AppSpacing.xs),
                      ],
                      ...actions,
                    ],
                  ),
                ),
              ),
            ),
          ]
        : actions;
    return Scaffold(
      extendBodyBehindAppBar: overlayHeader,
      appBar: showHeader
          ? AppBar(
              automaticallyImplyLeading: false,
              leadingWidth: leadingWidth,
              leading: compactLeadingHeader == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.xs),
                      child: compactLeadingHeader,
                    ),
              title: headerTitle,
              actions: headerActions,
              backgroundColor: overlayHeader
                  ? Colors.transparent
                  : tokens.panel,
              foregroundColor: tokens.text,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              shape: overlayHeader
                  ? const RoundedRectangleBorder()
                  : Border(
                      bottom: BorderSide(
                        color: tokens.panelBorder,
                        width: AppBorder.thin,
                      ),
                    ),
            )
          : null,
      body: SafeArea(
        top: !overlayHeader,
        bottom: false,
        child: childPad
            ? Padding(
                padding: const EdgeInsets.all(AppSpacing.page),
                child: child,
              )
            : child,
      ),
    );
  }
}

class _UiCompactActionsMenu extends StatelessWidget {
  final List<Widget> actions;

  const _UiCompactActionsMenu({required this.actions});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final width = math.max(112.0, math.min(368.0, screenSize.width - 32));
    final maxHeight = math.max(0.0, screenSize.height - 32);
    final tokens = context.appTokens;
    final entries = <PopupMenuEntry<int>>[
      _UiCompactMenuHeader(width: width),
      PopupMenuDivider(height: AppSpacing.sm, color: tokens.panelBorder),
    ];
    for (var index = 0; index < actions.length; index++) {
      final action = actions[index];
      if (action is UiIconButton) {
        entries.add(
          PopupMenuItem<int>(
            key: action.key,
            value: index,
            enabled: action.onPressed != null,
            height: AppControlSize.minimumHitTarget,
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: action.selected ? tokens.accentSoft : tokens.panel,
                    borderRadius: BorderRadius.circular(tokens.controlRadius),
                    border: Border.all(
                      color: tokens.panelBorder,
                      width: AppBorder.thin,
                    ),
                  ),
                  child: SizedBox(
                    width: AppControlSize.regular,
                    height: AppControlSize.regular,
                    child: Icon(
                      action.icon,
                      size: action.iconSize,
                      color:
                          action.color ??
                          (action.selected ? tokens.accent : tokens.textMuted),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    action.tooltip,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (action is UiMenuButton) {
        entries.add(
          _UiCompactMenuWidgetEntry<int>(
            width: width - AppSpacing.md * 2,
            child: Builder(
              builder: (context) => KeyedSubtree(
                key: action.key,
                child: action.buildCompactActionEntry(context),
              ),
            ),
          ),
        );
      } else {
        entries.add(
          _UiCompactMenuWidgetEntry<int>(
            width: width - AppSpacing.md * 2,
            child: action,
          ),
        );
      }
    }

    return PopupMenuButton<int>(
      key: const ValueKey('ui-compact-actions-menu'),
      tooltip: 'More canvas actions',
      constraints: BoxConstraints(
        minWidth: width,
        maxWidth: width,
        maxHeight: maxHeight,
      ),
      color: tokens.panelElevated,
      elevation: 2,
      shadowColor: tokens.raisedShadow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.panelRadius),
        side: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
      ),
      popUpAnimationStyle:
          AppMotion.durationFor(context, AppMotion.standard) == Duration.zero
          ? AnimationStyle.noAnimation
          : AnimationStyle(
              duration: AppMotion.durationFor(context, AppMotion.standard),
              reverseDuration: AppMotion.durationFor(context, AppMotion.short),
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      menuPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      icon: const Icon(Icons.more_horiz_rounded),
      itemBuilder: (_) => entries,
      onSelected: (index) {
        final action = actions[index];
        if (action is UiIconButton) action.onPressed?.call();
      },
    );
  }
}

class _UiCompactMenuHeader extends PopupMenuEntry<int> {
  final double width;

  const _UiCompactMenuHeader({required this.width});

  @override
  double get height => AppControlSize.touch + AppSpacing.xs;

  @override
  bool represents(int? value) => false;

  @override
  State<_UiCompactMenuHeader> createState() => _UiCompactMenuHeaderState();
}

class _UiCompactMenuHeaderState extends State<_UiCompactMenuHeader> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: widget.width - AppSpacing.md * 2,
      height: widget.height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.accentSoft,
                borderRadius: BorderRadius.circular(tokens.controlRadius),
                border: Border.all(
                  color: tokens.panelBorder,
                  width: AppBorder.thin,
                ),
              ),
              child: SizedBox(
                width: AppControlSize.regular,
                height: AppControlSize.regular,
                child: Icon(
                  Icons.dashboard_customize_outlined,
                  size: 18,
                  color: tokens.accent,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Canvas menu',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      color: tokens.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'More tools and workspace controls',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UiCompactMenuWidgetEntry<T> extends PopupMenuEntry<T> {
  final Widget child;
  final double width;

  const _UiCompactMenuWidgetEntry({required this.child, required this.width});

  @override
  double get height => AppControlSize.touch;

  @override
  bool represents(T? value) => false;

  @override
  State<_UiCompactMenuWidgetEntry<T>> createState() =>
      _UiCompactMenuWidgetEntryState<T>();
}

class _UiCompactMenuWidgetEntryState<T>
    extends State<_UiCompactMenuWidgetEntry<T>> {
  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.width,
    child: _UiCompactMenuActionScope(
      onSelected: (action) {
        Navigator.of(context).pop();
        WidgetsBinding.instance.addPostFrameCallback((_) => action());
      },
      child: widget.child,
    ),
  );
}

class _UiCompactMenuActionScope extends InheritedWidget {
  final void Function(VoidCallback action) onSelected;

  const _UiCompactMenuActionScope({
    required this.onSelected,
    required super.child,
  });

  static _UiCompactMenuActionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_UiCompactMenuActionScope>();

  @override
  bool updateShouldNotify(_UiCompactMenuActionScope oldWidget) =>
      onSelected != oldWidget.onSelected;
}

void _runCompactMenuAction(BuildContext context, VoidCallback action) {
  final menuAction = _UiCompactMenuActionScope.maybeOf(context);
  if (menuAction == null) {
    action();
  } else {
    menuAction.onSelected(action);
  }
}

class UiSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final BorderRadiusGeometry? borderRadius;
  final Color? borderColor;
  final double borderWidth;
  final bool bordered;

  const UiSurface({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.color,
    this.borderRadius,
    this.borderColor,
    this.borderWidth = AppBorder.thin,
    this.bordered = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final radius = borderRadius ?? BorderRadius.circular(tokens.panelRadius);
    var style = AppStyles.surface
        .color(color ?? AppMixTokens.panel())
        .borderRadius(BorderRadiusGeometryMix.value(radius));
    if (bordered) {
      style = style.borderAll(
        color: borderColor ?? tokens.panelBorder,
        width: borderWidth,
      );
    }

    return MixScope.inherit(
      colors: AppMixTokens.colors(tokens),
      child: Box(
        style: style.padding(EdgeInsetsGeometryMix.value(padding)),
        child: child,
      ),
    );
  }
}

class UiSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const UiSectionHeader({required this.title, this.trailing, super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final titleWidget = Text(
          title,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: tokens.textMuted,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        );
        if (trailing == null) return titleWidget;

        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleWidget,
              const SizedBox(height: AppSpacing.sm),
              Align(alignment: Alignment.centerLeft, child: trailing!),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: titleWidget),
            trailing!,
          ],
        );
      },
    );
  }
}

enum UiAlertVariant { info, success, warning, destructive }

class UiAlert extends StatelessWidget {
  final String title;
  final String? description;
  final IconData icon;
  final UiAlertVariant variant;
  final Widget? trailing;
  final bool liveRegion;

  const UiAlert({
    required this.title,
    required this.icon,
    required this.variant,
    this.description,
    this.trailing,
    this.liveRegion = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final status = switch (variant) {
      UiAlertVariant.info => tokens.info,
      UiAlertVariant.success => tokens.success,
      UiAlertVariant.warning => tokens.warning,
      UiAlertVariant.destructive => tokens.danger,
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactTrailing = constraints.maxWidth < 360 && trailing != null;
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: tokens.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (description != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                description!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.textMuted),
              ),
            ],
          ],
        );
        final statusIcon = Icon(icon, color: status, size: 18);
        return Semantics(
          container: true,
          liveRegion: liveRegion,
          child: UiSurface(
            color: Color.alphaBlend(
              status.withValues(alpha: 0.08),
              tokens.panel,
            ),
            borderColor: status.withValues(alpha: 0.42),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: compactTrailing
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          statusIcon,
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: details),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Align(alignment: Alignment.centerLeft, child: trailing!),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      statusIcon,
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: details),
                      if (trailing != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        trailing!,
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }
}

enum UiButtonVariant { primary, secondary, outline, ghost, destructive }

enum UiButtonSize { xs, sm, md, lg }

enum UiBadgeVariant {
  primary,
  secondary,
  outline,
  destructive,
  success,
  warning,
  info,
}

class UiButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final UiButtonVariant variant;
  final UiButtonSize size;
  final MainAxisSize mainAxisSize;
  final Widget? prefix;
  final Widget? suffix;
  final String? semanticsLabel;
  final FocusNode? focusNode;
  final bool iconOnly;
  final bool selected;

  const UiButton({
    required this.child,
    required this.onPressed,
    this.variant = UiButtonVariant.primary,
    this.size = UiButtonSize.sm,
    this.mainAxisSize = MainAxisSize.min,
    this.prefix,
    this.suffix,
    this.semanticsLabel,
    this.focusNode,
    this.iconOnly = false,
    this.selected = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final compactMenuScope = _UiCompactMenuActionScope.maybeOf(context);
    final tokens = context.appTokens;
    final controlRadius = BorderRadius.circular(tokens.controlRadius);
    final height = switch (size) {
      UiButtonSize.xs => AppControlSize.extraSmall,
      UiButtonSize.sm => AppControlSize.compact,
      UiButtonSize.md => AppControlSize.regular,
      UiButtonSize.lg => AppControlSize.touch,
    };
    final verticalPadding = iconOnly ? 0.0 : AppSpacing.xxs;
    final contentHeight = height - verticalPadding * 2;
    final horizontalPadding = iconOnly
        ? 0.0
        : switch (size) {
            UiButtonSize.xs => AppSpacing.sm,
            UiButtonSize.sm => AppSpacing.md,
            UiButtonSize.md => AppSpacing.lg,
            UiButtonSize.lg => AppSpacing.xl,
          };
    final background = onPressed == null
        ? AppMixTokens.panel()
        : switch (variant) {
            UiButtonVariant.primary => AppMixTokens.accent(),
            UiButtonVariant.secondary => AppMixTokens.accentSoft(),
            UiButtonVariant.destructive => AppMixTokens.danger(),
            UiButtonVariant.outline ||
            UiButtonVariant.ghost => AppMixTokens.panel(),
          };
    final foreground = onPressed == null
        ? tokens.textMuted
        : switch (variant) {
            UiButtonVariant.primary => tokens.accentForeground,
            UiButtonVariant.secondary => tokens.text,
            UiButtonVariant.destructive => tokens.accentForeground,
            UiButtonVariant.outline || UiButtonVariant.ghost => tokens.text,
          };
    var style = AppStyles.control
        .color(background)
        .borderRadius(BorderRadiusGeometryMix.value(controlRadius))
        .padding(
          EdgeInsetsGeometryMix.value(
            EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
          ),
        );
    if (variant == UiButtonVariant.ghost) {
      style = style.boxShadows(const []);
    } else if (variant == UiButtonVariant.outline) {
      style = style.borderAll(color: tokens.panelBorder, width: AppBorder.thin);
    }
    final children = <Widget>[
      if (prefix != null) ...[prefix!, const SizedBox(width: AppSpacing.xs)],
      if (child is Flexible) child else Flexible(child: child),
      if (suffix != null) ...[const SizedBox(width: AppSpacing.xs), suffix!],
    ];
    final VoidCallback? activate = onPressed == null
        ? null
        : compactMenuScope == null
        ? onPressed
        : () => compactMenuScope.onSelected(onPressed!);
    final button = ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: AppControlSize.minimumHitTarget,
        minHeight: AppControlSize.minimumHitTarget,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          focusNode: focusNode,
          onTap: compactMenuScope == null ? onPressed : null,
          borderRadius: controlRadius,
          child: Align(
            alignment: Alignment.center,
            widthFactor: 1,
            heightFactor: 1,
            child: Box(
              style: style,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: iconOnly ? height : 0,
                  minHeight: contentHeight,
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: foreground),
                  child: IconTheme.merge(
                    data: IconThemeData(color: foreground, size: 16),
                    child: Row(
                      mainAxisSize: mainAxisSize,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: children,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final compactMenuButton = compactMenuScope == null
        ? button
        : SizedBox(
            width:
                math.max(
                  112.0,
                  math.min(480.0, MediaQuery.sizeOf(context).width - 32),
                ) -
                AppSpacing.md * 2,
            child: MenuItemButton(
              onPressed: onPressed,
              style: ButtonStyle(
                alignment: Alignment.center,
                backgroundColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
                minimumSize: const WidgetStatePropertyAll(
                  Size(
                    AppControlSize.minimumHitTarget,
                    AppControlSize.minimumHitTarget,
                  ),
                ),
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(borderRadius: controlRadius),
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: Semantics(
                label: semanticsLabel,
                selected: selected,
                child: ExcludeSemantics(child: IgnorePointer(child: button)),
              ),
            ),
          );
    return MixScope.inherit(
      colors: AppMixTokens.colors(tokens),
      child: compactMenuScope == null
          ? Semantics(
              label: semanticsLabel,
              button: true,
              selected: selected,
              enabled: onPressed != null,
              onTap: semanticsLabel == null ? null : activate,
              child: semanticsLabel == null
                  ? compactMenuButton
                  : ExcludeSemantics(child: compactMenuButton),
            )
          : MenuItemButton(
              onPressed: activate,
              style: ButtonStyle(
                alignment: Alignment.center,
                backgroundColor: const WidgetStatePropertyAll(
                  Colors.transparent,
                ),
                minimumSize: const WidgetStatePropertyAll(
                  Size(
                    AppControlSize.minimumHitTarget,
                    AppControlSize.minimumHitTarget,
                  ),
                ),
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(borderRadius: controlRadius),
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: ExcludeSemantics(child: IgnorePointer(child: button)),
            ),
    );
  }
}

class UiIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final UiButtonVariant variant;
  final UiButtonSize size;
  final double iconSize;
  final Color? color;
  final bool selected;
  final Widget? iconWidget;

  const UiIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.variant = UiButtonVariant.ghost,
    this.size = UiButtonSize.sm,
    this.iconSize = 16,
    this.color,
    this.selected = false,
    this.iconWidget,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: UiButton(
        onPressed: onPressed,
        variant: selected ? UiButtonVariant.primary : variant,
        size: size,
        semanticsLabel: tooltip,
        selected: selected,
        iconOnly: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: iconWidget ?? Icon(icon, size: iconSize, color: color),
        ),
      ),
    );
  }
}

enum SidebarPanelSide { left, right }

/// Compact outline that shows a sidebar's location and toggle direction.
class SidebarPanelToggleIcon extends StatelessWidget {
  final SidebarPanelSide side;
  final bool expanded;
  final IconData? cue;

  const SidebarPanelToggleIcon({
    required this.side,
    required this.expanded,
    this.cue,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: Stack(
        children: [
          CustomPaint(
            size: const Size.square(16),
            painter: SidebarPanelTogglePainter(
              side: side,
              expanded: expanded,
              color: IconTheme.of(context).color ?? Colors.white,
            ),
          ),
          if (cue != null)
            Positioned(
              left: side == SidebarPanelSide.left ? 9 : 2,
              top: 9,
              child: ExcludeSemantics(child: Icon(cue, size: 5)),
            ),
        ],
      ),
    );
  }
}

@immutable
class SidebarPanelTogglePainter extends CustomPainter {
  final SidebarPanelSide side;
  final bool expanded;
  final Color color;

  const SidebarPanelTogglePainter({
    required this.side,
    required this.expanded,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final panelFill = Paint()
      ..color = color.withValues(alpha: expanded ? 0.22 : 0.1)
      ..style = PaintingStyle.fill;
    final frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      const Radius.circular(2),
    );
    canvas.drawRRect(frame, stroke);

    final onLeft = side == SidebarPanelSide.left;
    final dividerX = onLeft
        ? expanded
              ? 5.5
              : 4.5
        : expanded
        ? size.width - 5.5
        : size.width - 4.5;
    final panelRect = onLeft
        ? Rect.fromLTRB(2, 2, dividerX, size.height - 2)
        : Rect.fromLTRB(dividerX, 2, size.width - 2, size.height - 2);
    canvas.drawRect(panelRect, panelFill);
    canvas.drawLine(
      Offset(dividerX, 2),
      Offset(dividerX, size.height - 2),
      stroke,
    );

    final pointsLeft = (onLeft && expanded) || (!onLeft && !expanded);
    final contentCenterX = onLeft
        ? (dividerX + size.width - 2) / 2
        : (2 + dividerX) / 2;
    final direction = pointsLeft ? -1.0 : 1.0;
    final chevron = Path()
      ..moveTo(contentCenterX - direction, 5.5)
      ..lineTo(contentCenterX + direction, 8)
      ..lineTo(contentCenterX - direction, 10.5);
    canvas.drawPath(chevron, stroke);
  }

  @override
  bool shouldRepaint(covariant SidebarPanelTogglePainter oldDelegate) =>
      side != oldDelegate.side ||
      expanded != oldDelegate.expanded ||
      color != oldDelegate.color;
}

class UiMenuAction<T> {
  final T value;
  final String label;
  final IconData icon;
  final bool enabled;
  final bool selected;
  final bool destructive;
  final bool separatorBefore;
  final Widget? suffix;
  final bool rowInteractive;

  const UiMenuAction({
    required this.value,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.selected = false,
    this.destructive = false,
    this.separatorBefore = false,
    this.suffix,
    this.rowInteractive = true,
  });
}

class UiMenuButton<T> extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final List<UiMenuAction<T>> items;
  final ValueChanged<T> onSelected;
  final Key? buttonKey;

  const UiMenuButton({
    required this.tooltip,
    required this.icon,
    required this.items,
    required this.onSelected,
    this.buttonKey,
    super.key,
  });

  @override
  Widget build(BuildContext context) => _buildMenuButton(context);

  Widget buildCompactActionEntry(BuildContext context) =>
      _buildMenuButton(context, compactAction: true);

  Widget _buildMenuButton(BuildContext context, {bool compactAction = false}) {
    final screenSize = MediaQuery.sizeOf(context);
    final maxWidth = math.max(0.0, math.min(304.0, screenSize.width - 16));
    final maxHeight = math.max(0.0, screenSize.height - 32);
    final tokens = context.appTokens;
    return Semantics(
      label: tooltip,
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: PopupMenuButton<T>(
          key: buttonKey,
          tooltip: tooltip,
          constraints: BoxConstraints(
            minWidth: math.min(112.0, maxWidth),
            maxWidth: maxWidth,
            maxHeight: maxHeight,
          ),
          onSelected: (value) =>
              _runCompactMenuAction(context, () => onSelected(value)),
          position: PopupMenuPosition.under,
          menuPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          iconSize: 16,
          color: tokens.panelElevated,
          elevation: 2,
          shadowColor: tokens.raisedShadow,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.panelRadius),
            side: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
          ),
          itemBuilder: (_) => [
            for (final item in items) ...[
              if (item.separatorBefore)
                PopupMenuDivider(
                  height: AppSpacing.md,
                  indent: AppSpacing.md,
                  endIndent: AppSpacing.md,
                  color: context.appTokens.panelBorder,
                ),
              if (item.rowInteractive)
                PopupMenuItem<T>(
                  value: item.value,
                  height: AppControlSize.minimumHitTarget,
                  enabled: item.enabled,
                  child: _buildMenuAction(context, item),
                )
              else
                _UiMenuControlEntry<T>(item: item),
            ],
          ],
          icon: compactAction ? null : Icon(icon),
          child: compactAction
              ? Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.panel,
                        borderRadius: BorderRadius.circular(
                          tokens.controlRadius,
                        ),
                        border: Border.all(
                          color: tokens.panelBorder,
                          width: AppBorder.thin,
                        ),
                      ),
                      child: SizedBox(
                        width: AppControlSize.regular,
                        height: AppControlSize.regular,
                        child: Icon(icon, size: 16, color: tokens.textMuted),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        tooltip,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens.text,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: tokens.textMuted,
                    ),
                  ],
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildMenuAction(BuildContext context, UiMenuAction<T> item) {
    final tokens = context.appTokens;
    final foreground = item.destructive ? tokens.danger : tokens.text;
    final muted = item.enabled
        ? tokens.textMuted
        : tokens.textMuted.withValues(alpha: AppOpacity.disabled);
    return Row(
      children: [
        SizedBox(
          width: AppControlSize.compact,
          child: Icon(
            item.icon,
            size: 16,
            color: item.destructive ? foreground : muted,
          ),
        ),
        Expanded(
          child: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: foreground,
              fontWeight: item.selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
        if (item.suffix != null) ...[
          const SizedBox(width: AppSpacing.sm),
          item.suffix!,
        ],
        if (item.selected) ...[
          const SizedBox(width: AppSpacing.sm),
          Icon(Icons.check, size: 16, color: tokens.accent),
        ],
      ],
    );
  }
}

class _UiMenuControlEntry<T> extends PopupMenuEntry<T> {
  final UiMenuAction<T> item;

  const _UiMenuControlEntry({required this.item});

  @override
  double get height => AppControlSize.minimumHitTarget;

  @override
  bool represents(T? value) => false;

  @override
  State<_UiMenuControlEntry<T>> createState() => _UiMenuControlEntryState<T>();
}

class _UiMenuControlEntryState<T> extends State<_UiMenuControlEntry<T>> {
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return IgnorePointer(
      ignoring: !item.enabled,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppControlSize.minimumHitTarget,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              SizedBox(
                width: AppControlSize.compact,
                child: Icon(
                  item.icon,
                  size: 16,
                  color: context.appTokens.textMuted,
                ),
              ),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: item.enabled
                        ? context.appTokens.text
                        : context.appTokens.textMuted.withValues(
                            alpha: AppOpacity.disabled,
                          ),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (item.suffix != null) ...[
                const SizedBox(width: AppSpacing.sm),
                item.suffix!,
              ],
              if (item.selected) ...[
                const SizedBox(width: AppSpacing.sm),
                Icon(Icons.check, size: 16, color: context.appTokens.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<T?> showUiContextMenu<T>({
  required BuildContext context,
  required Offset position,
  required String semanticsLabel,
  required List<UiMenuAction<T>> items,
}) {
  final screenSize = MediaQuery.sizeOf(context);
  final tokens = context.appTokens;
  final itemsWithSeparators = <PopupMenuEntry<T>>[];
  for (final item in items) {
    if (item.separatorBefore) {
      itemsWithSeparators.add(
        PopupMenuDivider(
          height: AppSpacing.md,
          indent: AppSpacing.md,
          endIndent: AppSpacing.md,
          color: tokens.panelBorder,
        ),
      );
    }
    if (!item.rowInteractive) continue;
    itemsWithSeparators.add(
      PopupMenuItem<T>(
        value: item.value,
        height: AppControlSize.minimumHitTarget,
        enabled: item.enabled,
        child: Semantics(
          label: item.label,
          selected: item.selected,
          child: _buildContextMenuAction(context, item),
        ),
      ),
    );
  }

  return showMenu<T>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      screenSize.width - position.dx,
      screenSize.height - position.dy,
    ),
    items: itemsWithSeparators,
    elevation: 2,
    shadowColor: tokens.raisedShadow,
    surfaceTintColor: Colors.transparent,
    menuPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    color: tokens.panelElevated,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.panelRadius),
      side: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
    ),
    semanticLabel: semanticsLabel,
  );
}

Widget _buildContextMenuAction<T>(BuildContext context, UiMenuAction<T> item) {
  final tokens = context.appTokens;
  final foreground = item.destructive ? tokens.danger : tokens.text;
  return Row(
    children: [
      SizedBox(
        width: AppControlSize.compact,
        child: Icon(
          item.icon,
          size: 16,
          color: item.destructive ? foreground : tokens.textMuted,
        ),
      ),
      Expanded(
        child: Text(
          item.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: foreground,
            fontWeight: item.selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
      if (item.suffix != null) ...[
        const SizedBox(width: AppSpacing.sm),
        item.suffix!,
      ],
      if (item.selected) ...[
        const SizedBox(width: AppSpacing.sm),
        Icon(Icons.check, size: 16, color: tokens.accent),
      ],
    ],
  );
}

class UiBadge extends StatelessWidget {
  final String label;
  final UiBadgeVariant variant;
  final int? maxLines;
  final TextOverflow? overflow;

  const UiBadge(
    this.label, {
    this.variant = UiBadgeVariant.outline,
    this.maxLines,
    this.overflow,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final foreground = switch (variant) {
      UiBadgeVariant.primary => tokens.accentForeground,
      UiBadgeVariant.destructive => tokens.danger,
      UiBadgeVariant.success => tokens.success,
      UiBadgeVariant.warning => tokens.warning,
      UiBadgeVariant.info => tokens.info,
      UiBadgeVariant.secondary || UiBadgeVariant.outline => tokens.textMuted,
    };
    final statusColor = switch (variant) {
      UiBadgeVariant.primary => tokens.accent,
      UiBadgeVariant.secondary || UiBadgeVariant.outline => tokens.panelBorder,
      UiBadgeVariant.destructive => tokens.danger,
      UiBadgeVariant.success => tokens.success,
      UiBadgeVariant.warning => tokens.warning,
      UiBadgeVariant.info => tokens.info,
    };
    final statusBackground = switch (variant) {
      UiBadgeVariant.primary => tokens.accent,
      UiBadgeVariant.secondary => tokens.accentSoft,
      UiBadgeVariant.outline => tokens.panel,
      UiBadgeVariant.destructive ||
      UiBadgeVariant.success ||
      UiBadgeVariant.warning ||
      UiBadgeVariant.info => Color.alphaBlend(
        statusColor.withValues(alpha: 0.12),
        tokens.panel,
      ),
    };
    final borderColor = switch (variant) {
      UiBadgeVariant.primary => tokens.accent,
      UiBadgeVariant.secondary || UiBadgeVariant.outline => tokens.panelBorder,
      UiBadgeVariant.destructive ||
      UiBadgeVariant.success ||
      UiBadgeVariant.warning ||
      UiBadgeVariant.info => statusColor.withValues(alpha: 0.48),
    };
    final style = BoxStyler()
        .color(statusBackground)
        .borderRounded(AppRadius.pill)
        .borderAll(color: borderColor, width: AppBorder.thin)
        .padding(
          EdgeInsetsGeometryMix.value(
            const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
          ),
        );
    return MixScope.inherit(
      colors: AppMixTokens.colors(tokens),
      child: Semantics(
        label: label,
        child: Box(
          style: style,
          child: Text(
            label,
            maxLines: maxLines,
            overflow: overflow,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

Widget _buildInsetControl(BuildContext context, Widget child) {
  final tokens = context.appTokens;
  final style = AppStyles.pressedControl
      .color(AppMixTokens.panel())
      .borderRounded(tokens.controlRadius);
  return MixScope.inherit(
    colors: AppMixTokens.colors(tokens),
    child: Box(
      style: style,
      child: IconTheme.merge(
        data: const IconThemeData(size: 16),
        child: Material(color: Colors.transparent, child: child),
      ),
    ),
  );
}

class UiTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? initialValue;
  final String? label;
  final String? hint;
  final String? description;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final TextDirection? textDirection;
  final bool autocorrect;
  final bool enableSuggestions;
  final SpellCheckConfiguration? spellCheckConfiguration;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final bool autofocus;
  final bool enabled;
  final bool obscureText;
  final bool expands;
  final int? minLines;
  final int? maxLines;
  final int? maxLength;
  final TextAlign textAlign;
  final TextAlignVertical? textAlignVertical;
  final FocusNode? focusNode;
  final VoidCallback? onEditingComplete;
  final bool readOnly;
  final Widget? prefix;
  final Widget? suffix;
  final bool clearable;

  const UiTextField({
    this.controller,
    this.initialValue,
    this.label,
    this.hint,
    this.description,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.textDirection,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.spellCheckConfiguration,
    this.inputFormatters,
    this.autofillHints,
    this.autofocus = false,
    this.enabled = true,
    this.obscureText = false,
    this.expands = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.textAlign = TextAlign.start,
    this.textAlignVertical,
    this.focusNode,
    this.onEditingComplete,
    this.readOnly = false,
    this.prefix,
    this.suffix,
    this.clearable = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textController = controller;
    return _buildInsetControl(
      context,
      TextFormField(
        controller: textController,
        initialValue: textController == null ? initialValue : null,
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        keyboardType: keyboardType,
        textInputAction: textInputAction ?? TextInputAction.done,
        textCapitalization: textCapitalization,
        textDirection: textDirection,
        autocorrect: obscureText ? false : autocorrect,
        enableSuggestions: obscureText ? false : enableSuggestions,
        spellCheckConfiguration: spellCheckConfiguration,
        inputFormatters: inputFormatters,
        autofillHints: autofillHints,
        autofocus: autofocus,
        enabled: enabled,
        obscureText: obscureText,
        expands: expands,
        minLines: expands ? null : minLines,
        maxLines: expands ? null : maxLines,
        maxLength: maxLength,
        textAlign: textAlign,
        textAlignVertical: textAlignVertical ?? TextAlignVertical.center,
        focusNode: focusNode,
        onEditingComplete: onEditingComplete,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: description,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          constraints: expands
              ? null
              : const BoxConstraints(minHeight: AppControlSize.input),
          prefixIcon: prefix,
          suffixIcon:
              suffix ??
              (clearable && textController != null
                  ? IconButton(
                      tooltip: 'Clear',
                      onPressed: () {
                        textController.clear();
                        onChanged?.call('');
                      },
                      icon: const Icon(Icons.close),
                    )
                  : null),
        ),
      ),
    );
  }
}

class UiSelect<T> extends StatelessWidget {
  final Map<String, T> items;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String? label;
  final String? hint;
  final bool enabled;

  const UiSelect({
    required this.items,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.enabled = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return UiTextField(
        label: label,
        hint: hint ?? 'No options available',
        enabled: false,
        readOnly: true,
      );
    }
    final tokens = context.appTokens;
    final screenHeight = MediaQuery.sizeOf(context).height;
    return _buildInsetControl(
      context,
      DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        icon: const Icon(Icons.keyboard_arrow_down_rounded),
        iconSize: 18,
        iconEnabledColor: tokens.textMuted,
        iconDisabledColor: tokens.textMuted,
        elevation: 2,
        dropdownColor: tokens.panelElevated,
        borderRadius: BorderRadius.circular(tokens.panelRadius),
        menuMaxHeight: math.max(0.0, screenHeight - AppSpacing.xl),
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(color: tokens.text),
        decoration: InputDecoration(labelText: label, hintText: hint),
        items: [
          for (final item in items.entries)
            DropdownMenuItem<T>(
              value: item.value,
              child: Row(
                children: [
                  SizedBox(
                    width: AppControlSize.extraSmall,
                    child: item.value == value
                        ? Icon(Icons.check, size: 16, color: tokens.accent)
                        : null,
                  ),
                  Expanded(
                    child: Text(
                      item.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

class UiEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const UiEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: AppControlSize.regular, color: tokens.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textMuted),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class UiThemeModeButton extends ConsumerWidget {
  const UiThemeModeButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final icon = switch (mode) {
      ThemeMode.system => Icons.brightness_auto_outlined,
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
    };
    return UiIconButton(
      icon: icon,
      tooltip: 'Theme: ${themeModeLabel(mode)} (click to change)',
      onPressed: () =>
          ref.read(themeModeProvider.notifier).setMode(nextThemeMode(mode)),
    );
  }
}

class UiLoadingState extends StatelessWidget {
  final String label;

  const UiLoadingState({this.label = 'Loading', super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      label: label,
      liveRegion: true,
      child: const CircularProgressIndicator(),
    ),
  );
}

class UiDialogStyle {
  final TextStyle titleTextStyle;
  final TextStyle bodyTextStyle;

  const UiDialogStyle({
    required this.titleTextStyle,
    required this.bodyTextStyle,
  });
}

class UiDialog extends StatelessWidget {
  final String? semanticsLabel;
  final BoxConstraints? constraints;
  final Widget Function(BuildContext context, UiDialogStyle style) builder;

  const UiDialog({
    required this.builder,
    this.semanticsLabel,
    this.constraints,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final theme = Theme.of(context);
    final dialogContent = MixScope.inherit(
      colors: AppMixTokens.colors(tokens),
      child: Builder(
        builder: (dialogContext) => builder(
          dialogContext,
          UiDialogStyle(
            titleTextStyle: theme.textTheme.titleMedium ?? const TextStyle(),
            bodyTextStyle: theme.textTheme.bodyMedium ?? const TextStyle(),
          ),
        ),
      ),
    );
    final routeDialog = context
        .dependOnInheritedWidgetOfExactType<_UiDialogRouteScope>();
    return Semantics(
      label: semanticsLabel,
      scopesRoute: true,
      explicitChildNodes: true,
      child: routeDialog == null
          ? Dialog(
              insetPadding: const EdgeInsets.all(AppSpacing.md),
              constraints: constraints,
              backgroundColor: tokens.panel,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.dialog),
                side: BorderSide(
                  color: tokens.panelBorder,
                  width: AppBorder.thin,
                ),
              ),
              child: dialogContent,
            )
          : ConstrainedBox(
              constraints: constraints ?? const BoxConstraints(),
              child: dialogContent,
            ),
    );
  }
}

class _UiDialogRouteScope extends InheritedWidget {
  const _UiDialogRouteScope({required super.child});

  @override
  bool updateShouldNotify(_UiDialogRouteScope oldWidget) => false;
}

class UiSwitch extends StatelessWidget {
  final bool value;
  final bool enabled;
  final ValueChanged<bool>? onChange;
  final Widget? label;
  final Widget? description;
  final String? semanticsLabel;

  const UiSwitch({
    required this.value,
    required this.onChange,
    this.enabled = true,
    this.label,
    this.description,
    this.semanticsLabel,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final control = Semantics(
      label: semanticsLabel,
      toggled: value,
      child: Material(
        type: MaterialType.transparency,
        child: Switch.adaptive(
          value: value,
          onChanged: enabled ? onChange : null,
        ),
      ),
    );
    if (label == null && description == null) return control;
    return Row(
      children: [
        Expanded(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(
                context.appTokens.controlRadius,
              ),
              onTap: enabled && onChange != null
                  ? () => onChange!(!value)
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ?label,
                    if (description != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      DefaultTextStyle.merge(
                        style: TextStyle(color: context.appTokens.textMuted),
                        child: description!,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        control,
      ],
    );
  }
}

class UiCheckbox extends StatelessWidget {
  final bool value;
  final bool enabled;
  final ValueChanged<bool>? onChange;
  final String? semanticsLabel;

  const UiCheckbox({
    required this.value,
    required this.onChange,
    this.enabled = true,
    this.semanticsLabel,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    checked: value,
    child: Material(
      type: MaterialType.transparency,
      child: Checkbox.adaptive(
        value: value,
        onChanged: enabled && onChange != null
            ? (value) {
                if (value != null) onChange!(value);
              }
            : null,
      ),
    ),
  );
}

class UiProgressIndicator extends StatelessWidget {
  final String? semanticsLabel;
  final double? value;
  final double size;

  const UiProgressIndicator({
    this.semanticsLabel,
    this.value,
    this.size = 20,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    liveRegion: true,
    child: SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(value: value, strokeWidth: 2.4),
    ),
  );
}

class UiLinearProgressIndicator extends StatelessWidget {
  final String? semanticsLabel;
  final double? value;
  final double? height;

  const UiLinearProgressIndicator({
    this.semanticsLabel,
    this.value,
    this.height,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    liveRegion: true,
    child: LinearProgressIndicator(value: value, minHeight: height),
  );
}

class UiSlider extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final String? semanticsLabel;
  final String Function(double)? semanticValueFormatterCallback;
  final ValueChanged<double>? onChanged;

  const UiSlider({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.semanticsLabel,
    this.semanticValueFormatterCallback,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    child: Material(
      type: MaterialType.transparency,
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        semanticFormatterCallback: semanticValueFormatterCallback,
        onChanged: onChanged,
      ),
    ),
  );
}

class UiCard extends StatelessWidget {
  final Widget child;
  final Clip clipBehavior;
  final EdgeInsetsGeometry padding;

  const UiCard({
    required this.child,
    this.clipBehavior = Clip.none,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(context.appTokens.panelRadius);
    return UiSurface(
      borderRadius: radius,
      padding: padding,
      child: ClipRRect(
        borderRadius: radius,
        clipBehavior: clipBehavior,
        child: child,
      ),
    );
  }
}

class UiTabEntry {
  final Widget label;
  final Widget child;

  const UiTabEntry({required this.label, required this.child});
}

class UiTabs extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final List<UiTabEntry> tabs;
  final bool scrollable;
  final bool expands;

  const UiTabs({
    required this.index,
    required this.onChanged,
    required this.tabs,
    this.scrollable = false,
    this.expands = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) return const SizedBox.shrink();
    final selectedIndex = index.clamp(0, tabs.length - 1);
    return DefaultTabController(
      length: tabs.length,
      initialIndex: selectedIndex,
      animationDuration: AppMotion.durationFor(context, AppMotion.standard),
      child: _UiTabsContent(
        index: selectedIndex,
        onChanged: onChanged,
        tabs: tabs,
        scrollable: scrollable,
        expands: expands,
      ),
    );
  }
}

class _UiTabsContent extends StatefulWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final List<UiTabEntry> tabs;
  final bool scrollable;
  final bool expands;

  const _UiTabsContent({
    required this.index,
    required this.onChanged,
    required this.tabs,
    required this.scrollable,
    required this.expands,
  });

  @override
  State<_UiTabsContent> createState() => _UiTabsContentState();
}

class _UiTabsContentState extends State<_UiTabsContent> {
  @override
  void didUpdateWidget(covariant _UiTabsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == oldWidget.index) return;

    final controller = DefaultTabController.of(context);
    if (controller.index != widget.index) {
      controller.animateTo(
        widget.index,
        duration: AppMotion.durationFor(context, AppMotion.standard),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MixScope.inherit(
          colors: AppMixTokens.colors(tokens),
          child: Box(
            style: AppStyles.pressedControl
                .color(AppMixTokens.panel())
                .borderRounded(tokens.controlRadius)
                .padding(
                  EdgeInsetsGeometryMix.value(
                    const EdgeInsets.all(AppSpacing.xxs),
                  ),
                ),
            child: TabBar(
              isScrollable: widget.scrollable,
              onTap: widget.onChanged,
              labelColor: tokens.text,
              unselectedLabelColor: tokens.textMuted,
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.all(AppSpacing.xxs),
              indicator: BoxDecoration(
                color: tokens.panelElevated,
                borderRadius: BorderRadius.circular(tokens.controlRadius),
                border: Border.all(
                  color: tokens.panelBorder,
                  width: AppBorder.thin,
                ),
                boxShadow: [
                  BoxShadow(
                    color: tokens.raisedShadow,
                    offset: const Offset(
                      AppElevation.controlOffset,
                      AppElevation.controlOffset,
                    ),
                    blurRadius: AppElevation.controlBlur,
                  ),
                  BoxShadow(
                    color: tokens.pressedShadow,
                    offset: const Offset(
                      -AppElevation.controlOffset,
                      -AppElevation.controlOffset,
                    ),
                    blurRadius: AppElevation.controlBlur,
                  ),
                ],
              ),
              dividerColor: Colors.transparent,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              tabs: [for (final tab in widget.tabs) Tab(child: tab.label)],
            ),
          ),
        ),
        if (widget.expands)
          Expanded(
            child: TabBarView(
              children: [for (final tab in widget.tabs) tab.child],
            ),
          )
        else
          AnimatedSwitcher(
            duration: AppMotion.durationFor(context, AppMotion.standard),
            child: KeyedSubtree(
              key: ValueKey(widget.index),
              child: widget.tabs[widget.index].child,
            ),
          ),
      ],
    );
  }
}

class UiRadioChoice extends StatelessWidget {
  final bool value;
  final bool enabled;
  final String semanticsLabel;
  final Widget label;
  final Widget? description;
  final ValueChanged<bool> onChange;

  const UiRadioChoice({
    required this.value,
    required this.semanticsLabel,
    required this.label,
    required this.onChange,
    this.enabled = true,
    this.description,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticsLabel,
    inMutuallyExclusiveGroup: true,
    selected: value,
    enabled: enabled,
    onTap: enabled ? () => onChange(true) : null,
    child: ExcludeSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled ? () => onChange(true) : null,
          borderRadius: BorderRadius.circular(context.appTokens.controlRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                RadioGroup<bool>(
                  groupValue: value,
                  onChanged: (selected) {
                    if (enabled && selected != null) onChange(selected);
                  },
                  child: IgnorePointer(
                    ignoring: !enabled,
                    child: const Radio<bool>(value: true),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      label,
                      if (description != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        DefaultTextStyle.merge(
                          style: TextStyle(color: context.appTokens.textMuted),
                          child: description!,
                        ),
                      ],
                    ],
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

Future<T?> showUiDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext context) builder,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final tokens = context.appTokens;
  return showDialog<T>(
    context: context,
    useSafeArea: true,
    builder: (dialogContext) {
      final content = builder(dialogContext);
      return UncontrolledProviderScope(
        container: container,
        child: content is UiDialog
            ? content
            : Dialog(
                insetPadding: const EdgeInsets.all(AppSpacing.md),
                backgroundColor: tokens.panel,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.dialog),
                  side: BorderSide(
                    color: tokens.panelBorder,
                    width: AppBorder.thin,
                  ),
                ),
                child: _UiDialogRouteScope(child: content),
              ),
      );
    },
  );
}

Future<DateTime?> showUiDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  final boundedInitialDate = initialDate.isBefore(firstDate)
      ? firstDate
      : initialDate.isAfter(lastDate)
      ? lastDate
      : initialDate;
  return showDatePicker(
    context: context,
    initialDate: boundedInitialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    builder: _buildThemedPicker,
  );
}

Future<TimeOfDay?> showUiTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
}) => showTimePicker(
  context: context,
  initialTime: initialTime,
  builder: _buildThemedPicker,
);
Widget _buildThemedPicker(BuildContext context, Widget? child) {
  final tokens = context.appTokens;
  return Theme(
    data: Theme.of(context).copyWith(
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.panelRadius),
          side: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
        ),
      ),
    ),
    child: child ?? const SizedBox.shrink(),
  );
}

enum UiToastVariant { info, success, warning, error }

Color _contrastingForeground(Color background) =>
    background.computeLuminance() > 0.179 ? Colors.black : Colors.white;

void showUiToast(
  BuildContext context,
  String message, {
  UiToastVariant variant = UiToastVariant.info,
  Duration duration = const Duration(seconds: 4),
}) {
  final tokens = context.appTokens;
  final (background, foreground) = switch (variant) {
    UiToastVariant.info => (tokens.panelElevated, tokens.text),
    UiToastVariant.success => (
      tokens.success,
      _contrastingForeground(tokens.success),
    ),
    UiToastVariant.warning => (
      tokens.warning,
      _contrastingForeground(tokens.warning),
    ),
    UiToastVariant.error => (
      tokens.danger,
      _contrastingForeground(tokens.danger),
    ),
  };
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  try {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: TextStyle(color: foreground)),
          duration: duration,
          behavior: SnackBarBehavior.floating,
          backgroundColor: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.controlRadius),
            side: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
          ),
        ),
      );
  } on AssertionError {
    return;
  }
}
