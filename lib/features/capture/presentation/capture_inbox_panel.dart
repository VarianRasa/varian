import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/canvas/state/autosave_controller.dart';
import 'package:varian/features/home/state/home_provider.dart';
import '../domain/capture_canvas_handoff.dart';

import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../../assets/data/asset_service.dart';
import '../data/capture_repository.dart';
import '../domain/capture_item.dart';
import '../state/capture_provider.dart';

class CaptureInboxPanel extends ConsumerStatefulWidget {
  const CaptureInboxPanel({this.initiallyExpanded = true, super.key});

  final bool initiallyExpanded;

  @override
  ConsumerState<CaptureInboxPanel> createState() => _CaptureInboxPanelState();
}

class _CaptureInboxPanelState extends ConsumerState<CaptureInboxPanel> {
  late final TextEditingController _inputController;
  late bool _expanded;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _captureText() async {
    final value = _inputController.text;
    if (value.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(captureItemsProvider.notifier).captureText(value);
      if (!mounted) return;
      _inputController.clear();
      showUiToast(context, 'Saved to this device’s Inbox.');
    } on CaptureFailure catch (failure) {
      if (mounted) {
        showUiToast(
          context,
          _safeMessage(failure),
          variant: UiToastVariant.error,
        );
      }
    } catch (_) {
      if (mounted) {
        showUiToast(
          context,
          'Could not save this capture locally.',
          variant: UiToastVariant.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addToCanvas(CaptureItem item) async {
    if (_busy) return;
    final projects =
        ref.read(homeProjectsProvider).asData?.value ??
        await ref.read(localStorageServiceProvider).getProjects();
    if (!mounted) return;
    // Cached collaboration roles are not an authoritative edit grant. Keep
    // this first local-only handoff scoped to projects that need no room check.
    final eligible = projects
        .where((project) => project.status == ProjectStatus.active)
        .where((project) => !project.isCollaborationRoom)
        .toList(growable: false);
    if (eligible.isEmpty) {
      showUiToast(
        context,
        'Create or open an editable project before adding a capture.',
        variant: UiToastVariant.error,
      );
      return;
    }

    final selected = await showUiDialog<LocalProjectMetadata>(
      context: context,
      builder: (dialogContext) => _CaptureProjectChooser(
        projects: eligible,
        onCancel: () => Navigator.of(dialogContext).pop(),
        onSelect: (project) => Navigator.of(dialogContext).pop(project),
      ),
    );
    if (!mounted || selected == null) return;

    final sync = ref.read(supabaseSyncServiceProvider);
    final handoff = CaptureCanvasHandoff(
      projectId: selected.id,
      accountId: sync.currentUserId,
      captureId: item.id,
    );
    await context.push<void>(
      Uri(pathSegments: ['', 'project', selected.id]).toString(),
      extra: handoff,
    );
  }

  Future<void> _pickFiles() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final files = await AssetService().pickAnyFiles();
      if (!mounted || files.isEmpty) return;
      final created = await ref
          .read(captureItemsProvider.notifier)
          .captureFiles(files);
      if (mounted) {
        showUiToast(context, _pickerMessage(files, created.length));
      }
    } on CaptureFailure catch (failure) {
      if (mounted) {
        showUiToast(
          context,
          _safeMessage(failure),
          variant: UiToastVariant.error,
        );
      }
    } catch (_) {
      if (mounted) {
        showUiToast(
          context,
          'Could not add the selected files.',
          variant: UiToastVariant.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _safeMessage(CaptureFailure failure) => switch (failure.code) {
    'CAPTURE_EMPTY' => 'Enter text or choose a non-empty file.',
    'CAPTURE_SIZE_LIMIT' => 'This capture exceeds the 50 MB limit.',
    'CAPTURE_INVALID_URL' => 'Check the URL and try again.',
    _ => 'Could not save this capture locally.',
  };

  String _pickerMessage(List<AssetPickerResult> files, int savedCount) {
    final skipped = files.length - savedCount;
    if (savedCount == 0) return 'No supported files were added.';
    if (skipped == 0) return '$savedCount file(s) saved to this device.';
    return '$savedCount file(s) saved; $skipped unsupported or unreadable file(s) skipped.';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final captures = ref.watch(captureItemsProvider);
    final compact = AppResponsive.isNarrow(context);
    final filter = ref.watch(captureFilterProvider);
    return UiSurface(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: UiSectionHeader(
                  title: 'CAPTURE INBOX',
                  trailing: Text(
                    'Saved locally',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
                  ),
                ),
              ),
              UiIconButton(
                key: const ValueKey('capture-inbox-toggle'),
                icon: _expanded ? Icons.expand_less : Icons.expand_more,
                color: tokens.textMuted,
                size: UiButtonSize.xs,
                tooltip: _expanded
                    ? 'Collapse Capture Inbox'
                    : 'Expand Capture Inbox',
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
            ],
          ),
          if (_expanded) ...[
            const SizedBox(height: AppSpacing.sm),
            _buildComposeArea(compact),
            Divider(height: AppBorder.thin, color: tokens.panelBorder),
            const SizedBox(height: AppSpacing.xs),
            _buildFilterMenu(filter),
            _buildCaptureList(context, captures, filter, compact),
          ],
        ],
      ),
    );
  }

  Widget _buildComposeArea(bool compact) {
    final input = UiTextField(
      key: const ValueKey('capture-inbox-input'),
      controller: _inputController,
      hint: 'Capture a note or paste an HTTPS link',
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      minLines: 1,
      maxLines: compact ? 3 : 2,
      autocorrect: true,
      enableSuggestions: true,
      enabled: !_busy,
    );
    final actions = Wrap(
      spacing: AppSpacing.xs,
      children: [
        UiIconButton(
          key: const ValueKey('capture-inbox-files'),
          onPressed: _busy ? null : _pickFiles,
          tooltip: 'Attach files',
          icon: Icons.attach_file,
        ),
        UiButton(
          key: const ValueKey('capture-inbox-submit'),
          onPressed: _busy ? null : _captureText,
          semanticsLabel: 'Save capture',
          prefix: _busy
              ? const UiProgressIndicator(
                  semanticsLabel: 'Saving capture',
                  size: 16,
                )
              : const Icon(Icons.add),
          child: Text(_busy ? 'Saving' : 'Save'),
        ),
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          input,
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          Align(alignment: Alignment.centerRight, child: actions),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: input),
        const SizedBox(width: AppSpacing.sm),
        actions,
      ],
    );
  }

  Widget _buildFilterMenu(CaptureFilter filter) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      UiMenuButton<CaptureFilter>(
        buttonKey: const ValueKey('capture-filter-menu'),
        tooltip: 'Filter captures',
        icon: Icons.filter_list,
        items: CaptureFilter.values
            .map(
              (value) => UiMenuAction<CaptureFilter>(
                value: value,
                label: _filterLabel(value),
                icon: _filterIcon(value),
                selected: filter == value,
              ),
            )
            .toList(),
        onSelected: (value) =>
            ref.read(captureFilterProvider.notifier).state = value,
      ),
      const SizedBox(width: AppSpacing.xs),
      Text(
        _filterLabel(filter),
        style: Theme.of(
          context,
        ).textTheme.labelSmall!.copyWith(color: context.appTokens.textMuted),
      ),
    ],
  );

  String _filterLabel(CaptureFilter filter) => switch (filter) {
    CaptureFilter.all => 'All captures',
    CaptureFilter.unread => 'Unread',
    CaptureFilter.favorites => 'Favorites',
    CaptureFilter.trash => 'Inbox trash',
  };

  IconData _filterIcon(CaptureFilter filter) => switch (filter) {
    CaptureFilter.all => Icons.inbox_outlined,
    CaptureFilter.unread => Icons.mark_email_unread_outlined,
    CaptureFilter.favorites => Icons.star_border,
    CaptureFilter.trash => Icons.delete_outline,
  };

  Widget _buildCaptureList(
    BuildContext context,
    AsyncValue<List<CaptureItem>> captures,
    CaptureFilter filter,
    bool compact,
  ) {
    final tokens = context.appTokens;
    return captures.when(
      loading: () => const SizedBox(
        height: 44,
        child: Center(
          child: UiProgressIndicator(
            semanticsLabel: 'Loading captures',
            size: 18,
          ),
        ),
      ),
      error: (_, _) => SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Could not load local captures.',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
              ),
            ),
            UiButton(
              onPressed: () => ref.read(captureItemsProvider.notifier).load(),
              variant: UiButtonVariant.outline,
              prefix: const Icon(Icons.refresh),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return SizedBox(
            height: 44,
            child: Center(
              child: Text(
                filter == CaptureFilter.trash
                    ? 'Trash is empty.'
                    : 'Your inbox is empty.',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
              ),
            ),
          );
        }

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: compact ? 200 : 176),
          child: ListView.separated(
            key: const ValueKey('capture-inbox-list'),
            shrinkWrap: true,
            itemCount: items.length,
            separatorBuilder: (_, _) =>
                Divider(height: AppBorder.thin, color: tokens.panelBorder),
            itemBuilder: (_, index) => _buildCaptureRow(items[index]),
          ),
        );
      },
    );
  }

  Widget _buildCaptureRow(CaptureItem item) => _CaptureRow(
    item: item,
    onRead: (value) => _runItemAction(
      () => ref.read(captureItemsProvider.notifier).setRead(item.id, value),
    ),
    onFavorite: () => _runItemAction(
      () => ref
          .read(captureItemsProvider.notifier)
          .setFavorite(item.id, !item.isFavorite),
    ),
    onDelete: () => _runItemAction(
      () => ref.read(captureItemsProvider.notifier).delete(item.id),
    ),
    onRestore: () => _runItemAction(
      () => ref.read(captureItemsProvider.notifier).restore(item.id),
    ),
    onPurge: () => _confirmPurge(item),
    onAddToCanvas: item.status == CaptureStatus.deleted
        ? null
        : () => _addToCanvas(item),
  );

  Future<void> _runItemAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        showUiToast(
          context,
          'Could not update this capture.',
          variant: UiToastVariant.error,
        );
      }
    }
  }

  Future<void> _confirmPurge(CaptureItem item) async {
    final confirmed = await showUiDialog<bool>(
      context: context,
      builder: (dialogContext) => _PurgeCaptureDialog(
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (!mounted || confirmed != true) return;
    await _runItemAction(
      () => ref.read(captureItemsProvider.notifier).purge(item.id),
    );
  }
}

enum _CaptureRowAction {
  addToCanvas,
  toggleRead,
  toggleFavorite,
  delete,
  restore,
  purge,
}

class _CaptureRow extends StatelessWidget {
  const _CaptureRow({
    required this.item,
    required this.onRead,
    required this.onFavorite,
    required this.onDelete,
    required this.onRestore,
    required this.onPurge,
    required this.onAddToCanvas,
  });

  final CaptureItem item;
  final ValueChanged<bool> onRead;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;
  final VoidCallback onRestore;
  final VoidCallback onPurge;
  final VoidCallback? onAddToCanvas;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final deleted = item.status == CaptureStatus.deleted;
    final title = item.title?.trim().isNotEmpty == true
        ? item.title!.trim()
        : item.sourceUri ?? item.text ?? 'Captured file';
    final preview = item.text != null && item.text != item.sourceUri
        ? item.text!
        : item.mimeType ?? item.kind.name.toUpperCase();
    final icon = switch (item.kind) {
      CaptureKind.text => Icons.notes_outlined,
      CaptureKind.link => Icons.link,
      CaptureKind.image || CaptureKind.screenshot => Icons.image_outlined,
      CaptureKind.audio => Icons.audio_file_outlined,
      CaptureKind.file => Icons.insert_drive_file_outlined,
    };
    return Semantics(
      container: true,
      label: '${item.isRead ? 'Read' : 'Unread'} capture: $title',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.xs - AppSpacing.xxs,
              ),
              child: Icon(icon, size: 18, color: tokens.textMuted),
            ),
            const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: tokens.text,
                      fontWeight: item.isRead
                          ? FontWeight.w500
                          : FontWeight.w800,
                    ),
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs - AppSpacing.xxs / 2),
                  Text(
                    _relativeTime(item.createdAt),
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: AppControlSize.minimumHitTarget,
              height: AppControlSize.minimumHitTarget,
              child: UiMenuButton<_CaptureRowAction>(
                tooltip: 'Capture actions',
                icon: Icons.more_horiz,
                items: deleted
                    ? [
                        const UiMenuAction(
                          value: _CaptureRowAction.restore,
                          label: 'Restore capture',
                          icon: Icons.restore_outlined,
                        ),
                        const UiMenuAction(
                          value: _CaptureRowAction.purge,
                          label: 'Purge capture permanently',
                          icon: Icons.delete_forever_outlined,
                          destructive: true,
                        ),
                      ]
                    : [
                        UiMenuAction(
                          value: _CaptureRowAction.addToCanvas,
                          label: 'Add to canvas',
                          icon: Icons.playlist_add,
                          enabled: onAddToCanvas != null,
                        ),
                        UiMenuAction(
                          value: _CaptureRowAction.toggleRead,
                          label: item.isRead ? 'Mark unread' : 'Mark read',
                          icon: item.isRead
                              ? Icons.mark_email_unread_outlined
                              : Icons.drafts_outlined,
                        ),
                        UiMenuAction(
                          value: _CaptureRowAction.toggleFavorite,
                          label: item.isFavorite
                              ? 'Remove favorite'
                              : 'Add favorite',
                          icon: item.isFavorite
                              ? Icons.star
                              : Icons.star_border,
                          selected: item.isFavorite,
                        ),
                        const UiMenuAction(
                          value: _CaptureRowAction.delete,
                          label: 'Move capture to Trash',
                          icon: Icons.delete_outline,
                          destructive: true,
                        ),
                      ],
                onSelected: (action) {
                  switch (action) {
                    case _CaptureRowAction.addToCanvas:
                      onAddToCanvas?.call();
                    case _CaptureRowAction.toggleRead:
                      onRead(!item.isRead);
                    case _CaptureRowAction.toggleFavorite:
                      onFavorite();
                    case _CaptureRowAction.delete:
                      onDelete();
                    case _CaptureRowAction.restore:
                      onRestore();
                    case _CaptureRowAction.purge:
                      onPurge();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime value) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}

class _CaptureProjectChooser extends StatelessWidget {
  const _CaptureProjectChooser({
    required this.projects,
    required this.onCancel,
    required this.onSelect,
  });

  final List<LocalProjectMetadata> projects;
  final VoidCallback onCancel;
  final ValueChanged<LocalProjectMetadata> onSelect;

  @override
  Widget build(BuildContext context) {
    final maxHeight =
        (MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).vertical -
                2 * AppSpacing.md)
            .clamp(0.0, 440.0)
            .toDouble();
    return UiDialog(
      constraints: BoxConstraints(
        minWidth: 0,
        maxWidth: AppResponsive.dialogWidth(context, preferred: 440),
        maxHeight: maxHeight,
      ),
      semanticsLabel: 'Choose a canvas project for this capture',
      builder: (context, style) => SingleChildScrollView(
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add capture to canvas', style: style.titleTextStyle),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Choose an active local project. The Inbox capture will remain saved on this device.',
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: context.appTokens.textMuted,
                ),
              ),
              const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
              for (final project in projects)
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: AppSpacing.xs + AppSpacing.xxs,
                  ),
                  child: UiButton(
                    key: ValueKey('capture-target-${project.id}'),
                    onPressed: () => onSelect(project),
                    variant: UiButtonVariant.outline,
                    semanticsLabel: 'Add capture to ${project.name}',
                    prefix: const Icon(Icons.dashboard_outlined),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        project.name.trim().isEmpty
                            ? 'Untitled Project'
                            : project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
              Align(
                alignment: Alignment.centerRight,
                child: UiButton(
                  onPressed: onCancel,
                  variant: UiButtonVariant.ghost,
                  child: const Text('CANCEL'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PurgeCaptureDialog extends StatelessWidget {
  const _PurgeCaptureDialog({required this.onCancel, required this.onConfirm});

  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => UiDialog(
    constraints: AppResponsive.dialogConstraints(
      context,
      maxWidth: 420,
      maxHeight: 420,
    ),
    semanticsLabel: 'Confirm permanent capture deletion',
    builder: (context, style) => Padding(
      padding: AppResponsive.dialogPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Purge this capture?', style: style.titleTextStyle),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'This removes the saved item and its local file from this device.',
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              UiButton(
                onPressed: onCancel,
                variant: UiButtonVariant.ghost,
                child: const Text('CANCEL'),
              ),
              UiButton(
                onPressed: onConfirm,
                variant: UiButtonVariant.destructive,
                semanticsLabel: 'Purge capture permanently',
                child: const Text('PURGE'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
