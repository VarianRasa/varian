import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/canvas/presentation/widgets/pdf/pdf_annotation_layer.dart';

void _ignoreTextComment(PdfTextComment _) {}

enum PdfSidebarTab { thumbnails, outline, annotations }

class PdfSidebar extends StatelessWidget {
  final PdfViewerController pdfController;
  final PdfSidebarTab activeTab;
  final ValueChanged<PdfSidebarTab> onTabChanged;
  final List<PdfOutlineNode>? outlineNodes;
  final List<PdfStickyNote> stickyNotes;
  final List<PdfTextComment> textComments;
  final int currentPage;
  final int pageCount;
  final bool isDarkTheme;
  final VoidCallback onClose;
  final ValueChanged<int> onPageSelected;
  final ValueChanged<PdfDest> onDestSelected;
  final ValueChanged<PdfStickyNote> onNoteSelected;
  final ValueChanged<PdfStickyNote> onNoteDeleted;
  final ValueChanged<PdfTextComment> onTextCommentSelected;
  final ValueChanged<PdfTextComment> onTextCommentDeleted;

  const PdfSidebar({
    super.key,
    required this.pdfController,
    required this.activeTab,
    required this.onTabChanged,
    required this.outlineNodes,
    required this.stickyNotes,
    this.textComments = const [],
    required this.currentPage,
    required this.pageCount,
    required this.isDarkTheme,
    required this.onClose,
    required this.onPageSelected,
    required this.onDestSelected,
    required this.onNoteSelected,
    required this.onNoteDeleted,
    this.onTextCommentSelected = _ignoreTextComment,
    this.onTextCommentDeleted = _ignoreTextComment,
  });

  AppTokens get _tokens => isDarkTheme ? AppTokens.dark : AppTokens.light;

  @override
  Widget build(BuildContext context) {
    final tokens = _tokens;

    return Container(
      key: const ValueKey('pdf-sidebar-frame'),
      width: AppResponsive.isNarrow(context) ? 240 : 280,
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(
          right: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
        ),
      ),
      child: Column(
        children: [
          _buildSidebarHeader(context),
          _buildTabBar(),
          Expanded(child: _buildActiveTabContent(context)),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader(BuildContext context) {
    final tokens = _tokens;
    return Container(
      key: const ValueKey('pdf-sidebar-header'),
      height: AppControlSize.minimumHitTarget + AppBorder.thin,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: tokens.panelBorder, width: AppBorder.thin),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'NAVIGATION PANEL',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: tokens.textMuted,
              ),
            ),
          ),
          SizedBox(
            width: AppControlSize.minimumHitTarget,
            height: AppControlSize.minimumHitTarget,
            child: UiIconButton(
              icon: Icons.close,
              tooltip: 'Close Sidebar',
              size: UiButtonSize.lg,
              onPressed: onClose,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final tokens = _tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(color: tokens.accentSoft),
      child: Row(
        children: [
          _buildTabButton(
            tab: PdfSidebarTab.thumbnails,
            icon: Icons.grid_view_rounded,
            label: 'Pages',
          ),
          const SizedBox(width: AppSpacing.xs),
          _buildTabButton(
            tab: PdfSidebarTab.outline,
            icon: Icons.format_list_bulleted_rounded,
            label: 'Bookmarks',
          ),
          const SizedBox(width: AppSpacing.xs),
          _buildTabButton(
            tab: PdfSidebarTab.annotations,
            icon: Icons.edit_note_rounded,
            label: 'Notes',
            badgeCount: stickyNotes.length,
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required PdfSidebarTab tab,
    required IconData icon,
    required String label,
    int? badgeCount,
  }) {
    final isSelected = activeTab == tab;
    return Expanded(
      child: UiButton(
        onPressed: () => onTabChanged(tab),
        variant: isSelected ? UiButtonVariant.primary : UiButtonVariant.ghost,
        size: UiButtonSize.sm,
        prefix: Icon(icon, size: 14),
        child: Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
              if (badgeCount != null && badgeCount > 0)
                UiBadge('$badgeCount', variant: UiBadgeVariant.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTabContent(BuildContext context) {
    switch (activeTab) {
      case PdfSidebarTab.thumbnails:
        return _buildThumbnailsTab(context);
      case PdfSidebarTab.outline:
        return _buildOutlineTab(context);
      case PdfSidebarTab.annotations:
        return _buildAnnotationsTab(context);
    }
  }

  Widget _buildThumbnailsTab(BuildContext context) {
    final tokens = _tokens;
    if (pageCount <= 0) {
      return Center(
        child: Text(
          'No pages found',
          style: Theme.of(
            context,
          ).textTheme.bodySmall!.copyWith(color: tokens.textMuted),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.page,
        vertical: AppSpacing.md,
      ),
      itemCount: pageCount,
      itemBuilder: (context, index) {
        final pageNum = index + 1;
        final isCurrent = pageNum == currentPage;

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onPageSelected(pageNum),
                child: Semantics(
                  button: true,
                  label: 'Page $pageNum',
                  selected: isCurrent,
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: tokens.panelElevated,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(
                        color: isCurrent ? tokens.accent : tokens.panelBorder,
                        width: isCurrent ? AppBorder.focus : AppBorder.thin,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isCurrent
                              ? tokens.accent.withValues(alpha: 0.2)
                              : tokens.text.withValues(alpha: 0.08),
                          blurRadius: isCurrent ? 8 : 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: AspectRatio(
                      aspectRatio: 1 / 1.414, // Standard A4 ratio
                      child: Container(
                        color: tokens.accentSoft,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 28,
                                color: isCurrent
                                    ? tokens.accent
                                    : tokens.textMuted,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                'PAGE $pageNum',
                                style: Theme.of(context).textTheme.labelSmall!
                                    .copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: isCurrent
                                          ? tokens.accent
                                          : tokens.textMuted,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
              Text(
                '$pageNum',
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  color: isCurrent ? tokens.accent : tokens.textMuted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOutlineTab(BuildContext context) {
    final tokens = _tokens;
    if (outlineNodes == null || outlineNodes!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageWide),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bookmark_border_rounded,
                size: 36,
                color: tokens.textMuted,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'No Bookmarks / Outline',
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  fontWeight: FontWeight.bold,
                  color: tokens.text,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'This PDF does not contain an embedded document outline.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.sm),
      children: outlineNodes!
          .map((node) => _buildOutlineNodeItem(node, 0))
          .toList(),
    );
  }

  Widget _buildOutlineNodeItem(PdfOutlineNode node, int depth) {
    final hasChildren = node.children.isNotEmpty;

    Widget titleRow = Padding(
      padding: EdgeInsets.only(left: depth * AppSpacing.md),
      child: Semantics(
        label: 'Bookmark ${node.title}',
        button: true,
        child: ListTile(
          dense: true,
          visualDensity: const VisualDensity(vertical: -3),
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          title: Text(
            node.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          leading: const Icon(Icons.bookmark_outline, size: 16),
          onTap: node.dest == null ? null : () => onDestSelected(node.dest!),
        ),
      ),
    );

    if (hasChildren) {
      return Padding(
        padding: EdgeInsets.only(left: depth * AppSpacing.md),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          title: Row(
            children: [
              const Icon(Icons.folder_outlined, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  node.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          children: [
            Column(
              children: node.children
                  .map((child) => _buildOutlineNodeItem(child, depth + 1))
                  .toList(),
            ),
          ],
        ),
      );
    }

    return titleRow;
  }

  Widget _buildAnnotationsTab(BuildContext context) {
    final tokens = _tokens;
    if (stickyNotes.isEmpty && textComments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageWide),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sticky_note_2_outlined,
                size: 36,
                color: tokens.textMuted,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'No Sticky Notes Added',
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                  fontWeight: FontWeight.bold,
                  color: tokens.text,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Use the Note tool in the top toolbar to click and attach sticky notes to pages.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: stickyNotes.length + textComments.length,
      itemBuilder: (context, index) {
        if (index >= stickyNotes.length) {
          final comment = textComments[index - stickyNotes.length];
          final firstPage = comment.anchors.isEmpty
              ? 1
              : comment.anchors.first.pageNumber;
          return UiSurface(
            padding: const EdgeInsets.all(AppSpacing.md - AppSpacing.xxs),
            color: tokens.panelElevated,
            child: Row(
              children: [
                UiIconButton(
                  icon: Icons.format_quote,
                  tooltip: 'Open comment',
                  onPressed: () => onTextCommentSelected(comment),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: GestureDetector(
                    onTap: () => onTextCommentSelected(comment),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Page $firstPage · ${comment.comment}'),
                        Text(
                          comment.quote,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                UiIconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete comment',
                  variant: UiButtonVariant.destructive,
                  onPressed: () => onTextCommentDeleted(comment),
                ),
              ],
            ),
          );
        }
        final note = stickyNotes[index];
        return UiSurface(
          padding: const EdgeInsets.all(AppSpacing.md - AppSpacing.xxs),
          color: tokens.panelElevated,
          child: GestureDetector(
            onTap: () => onNoteSelected(note),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: note.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                        Text(
                          'Page ${note.pageNumber}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: tokens.accent,
                          ),
                        ),
                      ],
                    ),
                    UiIconButton(
                      icon: Icons.delete_outline,
                      tooltip: 'Delete Note',
                      variant: UiButtonVariant.destructive,
                      onPressed: () => onNoteDeleted(note),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                Text(note.text, maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        );
      },
    );
  }
}
