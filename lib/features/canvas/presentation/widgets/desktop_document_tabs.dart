import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';

/// The document-tab row used by the Windows title bar and non-Windows fallback.
class DesktopDocumentTabs extends ConsumerWidget {
  final String activeProjectId;
  final Future<void> Function(BuildContext context)? onCreateProject;
  final Future<void> Function(BuildContext context, OpenDocumentTab tab)?
  onSelectDocument;
  final Future<void> Function(
    BuildContext context,
    OpenDocumentTab tab,
    OpenDocumentTab? replacement,
    bool active,
  )?
  onCloseDocument;

  const DesktopDocumentTabs({
    super.key,
    required this.activeProjectId,
    this.onCreateProject,
    this.onSelectDocument,
    this.onCloseDocument,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) => DesktopDocumentTabStrip(
    activeProjectId: activeProjectId,
    onCreateProject: onCreateProject,
    onSelectDocument: onSelectDocument,
    onCloseDocument: onCloseDocument,
  );
}

/// A tab row that can either own its editor surface or sit inside the custom
/// Windows title bar.
class DesktopDocumentTabStrip extends ConsumerWidget {
  final String? activeProjectId;
  final Future<void> Function(BuildContext context)? onCreateProject;
  final Future<void> Function(BuildContext context, OpenDocumentTab tab)?
  onSelectDocument;
  final Future<void> Function(
    BuildContext context,
    OpenDocumentTab tab,
    OpenDocumentTab? replacement,
    bool active,
  )?
  onCloseDocument;
  final bool showHeading;
  final bool embedded;
  final bool titleBarStyle;
  final Widget? trailing;

  const DesktopDocumentTabStrip({
    super.key,
    this.activeProjectId,
    this.onCreateProject,
    this.onSelectDocument,
    this.onCloseDocument,
    this.showHeading = true,
    this.embedded = false,
    this.titleBarStyle = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.appTokens;
    final tabs = ref.watch(openDocumentTabsProvider);
    final compact = MediaQuery.sizeOf(context).width < 520;
    final mutedForeground = tokens.textMuted;

    final content = Row(
      children: [
        if (showHeading && !titleBarStyle && !compact) ...[
          const SizedBox(width: AppSpacing.md + AppSpacing.xxs),
          Text(
            'DOCUMENTS',
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
              color: mutedForeground,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        Flexible(
          fit: FlexFit.loose,
          child: ListView(
            scrollDirection: Axis.horizontal,
            shrinkWrap: true,
            padding: EdgeInsets.only(top: titleBarStyle ? AppSpacing.xxs : 5),
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < tabs.length; index++)
                    _DocumentTab(
                      key: ValueKey(
                        'document-tab-shell-${tabs[index].projectId}',
                      ),
                      tab: tabs[index],
                      active: tabs[index].projectId == activeProjectId,
                      titleBarStyle: titleBarStyle,
                      onPressed:
                          tabs[index].projectId == activeProjectId ||
                              onSelectDocument == null
                          ? null
                          : () => unawaited(
                              onSelectDocument!(context, tabs[index]),
                            ),
                      onClosePressed: onCloseDocument == null
                          ? null
                          : () => unawaited(
                              onCloseDocument!(
                                context,
                                tabs[index],
                                tabs.length <= 1
                                    ? null
                                    : index > 0
                                    ? tabs[index - 1]
                                    : tabs[index + 1],
                                tabs[index].projectId == activeProjectId,
                              ),
                            ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (onCreateProject != null || !titleBarStyle) ...[
          Container(
            width: AppBorder.thin,
            height: 22,
            color: tokens.panelBorder,
          ),
          _CreateDocumentButton(
            titleBarStyle: titleBarStyle,
            onPressed: onCreateProject == null
                ? null
                : () => unawaited(onCreateProject!(context)),
          ),
          SizedBox(width: titleBarStyle ? AppSpacing.xs : AppSpacing.sm),
        ],
        if (trailing != null) Expanded(child: trailing!),
      ],
    );

    if (embedded) return content;

    return DecoratedBox(
      key: const ValueKey('desktop-document-tab-strip'),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(
          bottom: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
        ),
      ),
      child: SizedBox(height: 42, child: content),
    );
  }
}

class DocumentBreadcrumbSwitcher extends ConsumerWidget {
  const DocumentBreadcrumbSwitcher({
    required this.activeProjectId,
    this.onCreateProject,
    this.onSelectDocument,
    this.onCloseDocument,
    super.key,
  });

  final String activeProjectId;
  final Future<void> Function(BuildContext context)? onCreateProject;
  final Future<void> Function(BuildContext context, OpenDocumentTab tab)?
  onSelectDocument;
  final Future<void> Function(
    BuildContext context,
    OpenDocumentTab tab,
    OpenDocumentTab? replacement,
    bool active,
  )?
  onCloseDocument;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageContext = context;
    final tabs = ref.watch(openDocumentTabsProvider);
    final tokens = context.appTokens;
    final compact = MediaQuery.sizeOf(context).width < 640;
    final menuController = MenuController();

    return MenuAnchor(
      key: const ValueKey('document-switcher-menu'),
      controller: menuController,
      alignmentOffset: const Offset(0, 8),
      menuChildren: [
        for (var index = 0; index < tabs.length; index++)
          MenuItemButton(
            onPressed:
                tabs[index].projectId == activeProjectId ||
                    onSelectDocument == null
                ? null
                : () => unawaited(() async {
                    menuController.close();
                    if (!pageContext.mounted) return;
                    await onSelectDocument!(pageContext, tabs[index]);
                  }()),
            leadingIcon: Icon(
              tabs[index].projectId == activeProjectId
                  ? Icons.description
                  : Icons.description_outlined,
            ),
            trailingIcon: onCloseDocument == null
                ? null
                : UiIconButton(
                    key: ValueKey(
                      'close-document-switcher-${tabs[index].projectId}',
                    ),
                    icon: Icons.close,
                    tooltip: 'Close ${tabs[index].name}',
                    size: UiButtonSize.xs,
                    onPressed: () => unawaited(() async {
                      menuController.close();
                      if (!pageContext.mounted) return;
                      await onCloseDocument!(
                        pageContext,
                        tabs[index],
                        tabs.length <= 1
                            ? null
                            : index > 0
                            ? tabs[index - 1]
                            : tabs[index + 1],
                        tabs[index].projectId == activeProjectId,
                      );
                    }()),
                  ),
            child: Text(
              tabs[index].name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (onCreateProject != null)
          MenuItemButton(
            leadingIcon: const Icon(Icons.add),
            onPressed: () => unawaited(() async {
              menuController.close();
              if (!pageContext.mounted) return;
              await onCreateProject!(pageContext);
            }()),
            child: const Text('New document'),
          ),
      ],
      builder: (context, controller, child) => UiButton(
        key: const ValueKey('document-switcher-button'),
        onPressed: controller.open,
        variant: UiButtonVariant.ghost,
        size: UiButtonSize.xs,
        semanticsLabel: 'Switch document',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (compact)
              Icon(
                Icons.folder_open_outlined,
                size: 16,
                color: tokens.textMuted,
              )
            else ...[
              Text(
                'Documents',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  color: tokens.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: AppSpacing.xxs),
            ],
            Icon(Icons.expand_more, size: 16, color: tokens.textMuted),
          ],
        ),
      ),
    );
  }
}

class _CreateDocumentButton extends StatelessWidget {
  final bool titleBarStyle;
  final VoidCallback? onPressed;

  const _CreateDocumentButton({
    required this.titleBarStyle,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    if (!titleBarStyle) {
      return UiIconButton(
        key: const ValueKey('create-project-tab'),
        icon: Icons.add,
        tooltip: 'Create new project',
        onPressed: onPressed,
      );
    }

    return SizedBox(
      width: AppControlSize.compact,
      height: AppControlSize.regular,
      child: UiIconButton(
        key: const ValueKey('create-project-tab'),
        icon: Icons.add,
        iconSize: 15,
        tooltip: 'Create new project',
        onPressed: onPressed,
        size: UiButtonSize.xs,
        color: tokens.text,
      ),
    );
  }
}

class _DocumentTab extends StatefulWidget {
  final OpenDocumentTab tab;
  final bool active;
  final bool titleBarStyle;
  final VoidCallback? onPressed;
  final VoidCallback? onClosePressed;

  const _DocumentTab({
    super.key,
    required this.tab,
    required this.active,
    required this.titleBarStyle,
    required this.onPressed,
    required this.onClosePressed,
  });

  @override
  State<_DocumentTab> createState() => _DocumentTabState();
}

class _DocumentTabState extends State<_DocumentTab> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureVisibleIfActive();
  }

  @override
  void didUpdateWidget(covariant _DocumentTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active &&
        (!oldWidget.active ||
            oldWidget.tab.projectId != widget.tab.projectId)) {
      _ensureVisibleIfActive();
    }
  }

  void _ensureVisibleIfActive() {
    if (!widget.active) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          context,
          alignment: 1,
          duration: Duration.zero,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final foreground = widget.titleBarStyle || widget.active
        ? tokens.text
        : tokens.textMuted;
    final background = tokens.panelElevated;
    final border = widget.titleBarStyle || widget.active
        ? tokens.panelBorder
        : Colors.transparent;

    return Padding(
      padding: EdgeInsets.only(
        right: widget.titleBarStyle ? AppSpacing.xxs : AppSpacing.xs,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.active ? background : Colors.transparent,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(
            widget.titleBarStyle ? 2 : AppRadius.control,
          ),
        ),
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: widget.titleBarStyle
                    ? widget.onClosePressed == null
                          ? 104
                          : 126
                    : widget.onClosePressed == null
                    ? 132
                    : 164,
                maxWidth: widget.titleBarStyle ? 190 : 220,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: widget.onPressed,
                        child: Semantics(
                          key: ValueKey('document-tab-${widget.tab.projectId}'),
                          label: 'Open document ${widget.tab.name}',
                          button: true,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: widget.titleBarStyle ? 8 : 11,
                              vertical: widget.titleBarStyle ? 4 : 6,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  widget.active
                                      ? Icons.description
                                      : Icons.description_outlined,
                                  size: widget.titleBarStyle ? 12 : 14,
                                  color: foreground,
                                ),
                                SizedBox(width: widget.titleBarStyle ? 5 : 7),
                                Expanded(
                                  child: Text(
                                    widget.tab.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall!
                                        .copyWith(
                                          color: foreground,
                                          fontWeight: widget.active
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.onClosePressed != null)
                    widget.titleBarStyle
                        ? _TitleBarIconButton(
                            key: ValueKey(
                              'close-document-tab-${widget.tab.projectId}',
                            ),
                            icon: Icons.close,
                            tooltip: 'Close ${widget.tab.name}',
                            onPressed: widget.onClosePressed,
                          )
                        : UiIconButton(
                            key: ValueKey(
                              'close-document-tab-${widget.tab.projectId}',
                            ),
                            icon: Icons.close,
                            tooltip: 'Close ${widget.tab.name}',
                            size: UiButtonSize.sm,
                            onPressed: widget.onClosePressed,
                          ),
                ],
              ),
            ),
            if (widget.active)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    height: widget.titleBarStyle ? 1 : 2,
                    color: tokens.accent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TitleBarIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _TitleBarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: AppControlSize.extraSmall,
    height: 30,
    child: UiIconButton(
      icon: icon,
      iconSize: 12,
      color: context.appTokens.textMuted,
      tooltip: tooltip,
      size: UiButtonSize.xs,
      onPressed: onPressed,
    ),
  );
}
