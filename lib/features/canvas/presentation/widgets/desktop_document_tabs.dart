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
  final Future<void> Function(BuildContext context)? onCreateCanvas;
  final Future<void> Function(BuildContext context)? onCreateNote;
  final Future<void> Function(BuildContext context)? onOpenSavedCanvas;
  final Future<void> Function(BuildContext context)? onOpenSavedNote;
  final OpenDocumentTab? activeTab;
  final Future<void> Function(BuildContext context, OpenDocumentTab tab)?
  onSelectTypedTab;
  final Future<void> Function(
    BuildContext context,
    OpenDocumentTab tab,
    OpenDocumentTab? replacement,
    bool active,
  )?
  onCloseTypedTab;

  const DesktopDocumentTabs({
    super.key,
    required this.activeProjectId,
    this.onCreateProject,
    this.onSelectDocument,
    this.onCloseDocument,
    this.onCreateCanvas,
    this.onCreateNote,
    this.onOpenSavedCanvas,
    this.onOpenSavedNote,
    this.activeTab,
    this.onSelectTypedTab,
    this.onCloseTypedTab,
    this.legacyCreateUsesNewMenu = false,
  });

  final bool legacyCreateUsesNewMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DesktopDocumentTabStrip(
    activeProjectId: activeProjectId,
    onCreateProject: onCreateProject,
    onSelectDocument: onSelectDocument,
    onCloseDocument: onCloseDocument,
    onCreateCanvas: onCreateCanvas,
    onCreateNote: onCreateNote,
    onOpenSavedCanvas: onOpenSavedCanvas,
    onOpenSavedNote: onOpenSavedNote,
    activeTab: activeTab,
    onSelectTypedTab: onSelectTypedTab,
    onCloseTypedTab: onCloseTypedTab,
    legacyCreateUsesNewMenu: legacyCreateUsesNewMenu,
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
  final bool legacyCreateUsesNewMenu;
  final Future<void> Function(BuildContext context)? onCreateCanvas;
  final Future<void> Function(BuildContext context)? onCreateNote;
  final Future<void> Function(BuildContext context)? onOpenSavedCanvas;
  final Future<void> Function(BuildContext context)? onOpenSavedNote;
  final OpenDocumentTab? activeTab;
  final Future<void> Function(BuildContext context, OpenDocumentTab tab)?
  onSelectTypedTab;
  final Future<void> Function(
    BuildContext context,
    OpenDocumentTab tab,
    OpenDocumentTab? replacement,
    bool active,
  )?
  onCloseTypedTab;

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
    this.legacyCreateUsesNewMenu = false,
    this.onCreateCanvas,
    this.onCreateNote,
    this.onOpenSavedCanvas,
    this.onOpenSavedNote,
    this.activeTab,
    this.onSelectTypedTab,
    this.onCloseTypedTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.appTokens;
    final tabs = openDocumentTabsFor(ref);
    final selectedTab = ref.watch(activeDocumentTabProvider);
    final currentTab =
        activeTab ??
        selectedTab ??
        tabs
            .where((tab) => tab.isCanvas && tab.documentId == activeProjectId)
            .firstOrNull;
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
                        'document-tab-shell-${tabs[index].identity}',
                      ),
                      tab: tabs[index],
                      active: tabs[index].identity == currentTab?.identity,
                      titleBarStyle: titleBarStyle,
                      onPressed:
                          tabs[index].identity == currentTab?.identity ||
                              (tabs[index].isCanvas &&
                                  onSelectDocument == null &&
                                  onSelectTypedTab == null) ||
                              (tabs[index].isNote && onSelectTypedTab == null)
                          ? null
                          : () => unawaited(
                              tabs[index].isCanvas
                                  ? onSelectDocument?.call(
                                          context,
                                          tabs[index],
                                        ) ??
                                        onSelectTypedTab!.call(
                                          context,
                                          tabs[index],
                                        )
                                  : onSelectTypedTab!.call(
                                      context,
                                      tabs[index],
                                    ),
                            ),
                      onClosePressed:
                          onCloseDocument == null && onCloseTypedTab == null
                          ? null
                          : () => unawaited(
                              (tabs[index].isCanvas
                                  ? onCloseDocument?.call(
                                          context,
                                          tabs[index],
                                          tabs.length <= 1
                                              ? null
                                              : tabs[index > 0
                                                    ? index - 1
                                                    : index + 1],
                                          tabs[index].identity ==
                                              currentTab?.identity,
                                        ) ??
                                        onCloseTypedTab!.call(
                                          context,
                                          tabs[index],
                                          tabs.length <= 1
                                              ? null
                                              : tabs[index > 0
                                                    ? index - 1
                                                    : index + 1],
                                          tabs[index].identity ==
                                              currentTab?.identity,
                                        )
                                  : onCloseTypedTab!.call(
                                      context,
                                      tabs[index],
                                      tabs.length <= 1
                                          ? null
                                          : tabs[index > 0
                                                ? index - 1
                                                : index + 1],
                                      tabs[index].identity ==
                                          currentTab?.identity,
                                    )),
                            ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (onCreateCanvas != null ||
            onCreateNote != null ||
            onOpenSavedCanvas != null ||
            onOpenSavedNote != null ||
            (legacyCreateUsesNewMenu && onCreateProject != null)) ...[
          Container(
            width: AppBorder.thin,
            height: 22,
            color: tokens.panelBorder,
          ),
          _CreateDocumentButton(
            titleBarStyle: titleBarStyle,
            onPressed: () => unawaited(_showCreateMenu(context)),
            legacyCreateUsesNewMenu: legacyCreateUsesNewMenu,
          ),
          SizedBox(width: titleBarStyle ? AppSpacing.xs : AppSpacing.sm),
        ] else if (onCreateProject != null || !titleBarStyle) ...[
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

  Future<void> _showCreateMenu(BuildContext context) async {
    if (legacyCreateUsesNewMenu &&
        onCreateCanvas == null &&
        onCreateNote == null &&
        onOpenSavedCanvas == null &&
        onOpenSavedNote == null) {
      await onCreateProject?.call(context);
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy + box.size.height,
        screen.width - origin.dx - box.size.width,
        screen.height - origin.dy,
      ),
      items: const [
        PopupMenuItem(value: 'new_canvas', child: Text('New blank Canvas')),
        PopupMenuItem(value: 'new_note', child: Text('New blank Notes')),
        PopupMenuItem(value: 'open_canvas', child: Text('Open saved Canvas')),
        PopupMenuItem(value: 'open_note', child: Text('Open saved Notes')),
      ],
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'new_canvas':
        await (onCreateCanvas ?? onCreateProject)?.call(context);
      case 'new_note':
        await onCreateNote?.call(context);
      case 'open_canvas':
        await onOpenSavedCanvas?.call(context);
      case 'open_note':
        await onOpenSavedNote?.call(context);
    }
  }
}

class DocumentBreadcrumbSwitcher extends ConsumerWidget {
  const DocumentBreadcrumbSwitcher({
    required this.activeProjectId,
    this.onCreateProject,
    this.onSelectDocument,
    this.onCloseDocument,
    this.onSelectTypedTab,
    this.onCloseTypedTab,
    this.onCreateCanvas,
    this.onCreateNote,
    this.onOpenSavedCanvas,
    this.onOpenSavedNote,
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
  final Future<void> Function(BuildContext context, OpenDocumentTab tab)?
  onSelectTypedTab;
  final Future<void> Function(
    BuildContext context,
    OpenDocumentTab tab,
    OpenDocumentTab? replacement,
    bool active,
  )?
  onCloseTypedTab;
  final Future<void> Function(BuildContext context)? onCreateCanvas;
  final Future<void> Function(BuildContext context)? onCreateNote;
  final Future<void> Function(BuildContext context)? onOpenSavedCanvas;
  final Future<void> Function(BuildContext context)? onOpenSavedNote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageContext = context;
    final tabs = openDocumentTabsFor(ref);
    final activeTab = ref.watch(activeDocumentTabProvider);
    final tokens = context.appTokens;
    final compact = MediaQuery.sizeOf(context).width < 640;
    final menuController = MenuController();
    void runAction(Future<void> Function(BuildContext context)? action) {
      if (action == null) return;
      unawaited(() async {
        menuController.close();
        if (!pageContext.mounted) return;
        await action(pageContext);
      }());
    }

    return MenuAnchor(
      key: const ValueKey('document-switcher-menu'),
      controller: menuController,
      alignmentOffset: const Offset(0, 8),
      menuChildren: [
        for (var index = 0; index < tabs.length; index++)
          MenuItemButton(
            onPressed:
                tabs[index].identity == activeTab?.identity ||
                    (tabs[index].isCanvas &&
                        onSelectDocument == null &&
                        onSelectTypedTab == null) ||
                    (tabs[index].isNote && onSelectTypedTab == null)
                ? null
                : () => unawaited(() async {
                    menuController.close();
                    if (!pageContext.mounted) return;
                    if (tabs[index].isCanvas && onSelectDocument != null) {
                      await onSelectDocument!(pageContext, tabs[index]);
                    } else {
                      await onSelectTypedTab?.call(pageContext, tabs[index]);
                    }
                  }()),
            leadingIcon: Icon(
              tabs[index].isNote
                  ? Icons.sticky_note_2_outlined
                  : Icons.description_outlined,
            ),
            trailingIcon: onCloseDocument == null && onCloseTypedTab == null
                ? null
                : UiIconButton(
                    key: ValueKey(
                      'close-document-switcher-${tabs[index].identity}',
                    ),
                    icon: Icons.close,
                    tooltip: 'Close ${tabs[index].name}',
                    size: UiButtonSize.xs,
                    onPressed: () => unawaited(() async {
                      menuController.close();
                      if (!pageContext.mounted) return;
                      final close = tabs[index].isCanvas
                          ? onCloseDocument ?? onCloseTypedTab
                          : onCloseTypedTab;
                      await close?.call(
                        pageContext,
                        tabs[index],
                        tabs.length <= 1
                            ? null
                            : tabs[index > 0 ? index - 1 : index + 1],
                        tabs[index].identity == activeTab?.identity,
                      );
                    }()),
                  ),
            child: Text(
              tabs[index].name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (onCreateCanvas != null || onCreateProject != null)
          MenuItemButton(
            key: const ValueKey('switcher-create-canvas'),
            leadingIcon: const Icon(Icons.add),
            onPressed: () => runAction(onCreateCanvas ?? onCreateProject),
            child: const Text('New blank Canvas'),
          ),
        if (onCreateNote != null)
          MenuItemButton(
            key: const ValueKey('switcher-create-note'),
            leadingIcon: const Icon(Icons.note_add_outlined),
            onPressed: () => runAction(onCreateNote),
            child: const Text('New blank Notes'),
          ),
        if (onOpenSavedCanvas != null)
          MenuItemButton(
            key: const ValueKey('switcher-open-saved-canvas'),
            leadingIcon: const Icon(Icons.folder_open_outlined),
            onPressed: () => runAction(onOpenSavedCanvas),
            child: const Text('Open saved Canvas'),
          ),
        if (onOpenSavedNote != null)
          MenuItemButton(
            key: const ValueKey('switcher-open-saved-note'),
            leadingIcon: const Icon(Icons.sticky_note_2_outlined),
            onPressed: () => runAction(onOpenSavedNote),
            child: const Text('Open saved Notes'),
          ),
        if (onCreateProject != null &&
            onCreateCanvas == null &&
            onCreateNote == null &&
            onOpenSavedCanvas == null &&
            onOpenSavedNote == null)
          MenuItemButton(
            leadingIcon: const Icon(Icons.add),
            onPressed: () => runAction(onCreateProject),
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
  final bool legacyCreateUsesNewMenu;

  const _CreateDocumentButton({
    required this.titleBarStyle,
    required this.onPressed,
    this.legacyCreateUsesNewMenu = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    if (!titleBarStyle) {
      return UiIconButton(
        key: const ValueKey('create-project-tab'),
        icon: Icons.add,
        tooltip: legacyCreateUsesNewMenu
            ? 'Create or open document'
            : 'Create new project',
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
        tooltip: legacyCreateUsesNewMenu
            ? 'Create or open document'
            : 'Create new project',
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
        (!oldWidget.active || oldWidget.tab.identity != widget.tab.identity)) {
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
                          key: ValueKey('document-tab-${widget.tab.identity}'),
                          label:
                              'Open ${widget.tab.isNote ? 'note' : 'document'} ${widget.tab.name}',
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
                              'close-document-tab-${widget.tab.identity}',
                            ),
                            icon: Icons.close,
                            tooltip: 'Close ${widget.tab.name}',
                            onPressed: widget.onClosePressed,
                          )
                        : UiIconButton(
                            key: ValueKey(
                              'close-document-tab-${widget.tab.identity}',
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
