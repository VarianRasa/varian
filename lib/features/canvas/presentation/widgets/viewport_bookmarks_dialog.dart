import 'package:flutter/material.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/canvas/domain/canvas_navigation.dart';

typedef CreateViewportBookmark =
    Future<ViewportBookmark?> Function(String name);
typedef RenameViewportBookmark =
    Future<ViewportBookmark?> Function(ViewportBookmark bookmark, String name);
typedef DeleteViewportBookmark =
    Future<bool> Function(ViewportBookmark bookmark);

class ViewportBookmarksDialog extends StatefulWidget {
  final List<ViewportBookmark> bookmarks;
  final bool readOnly;
  final CreateViewportBookmark? onCreate;
  final RenameViewportBookmark? onRename;
  final DeleteViewportBookmark? onDelete;
  final ValueChanged<ViewportBookmark> onSelect;

  const ViewportBookmarksDialog({
    super.key,
    required this.bookmarks,
    required this.onSelect,
    this.readOnly = false,
    this.onCreate,
    this.onRename,
    this.onDelete,
  });

  @override
  State<ViewportBookmarksDialog> createState() =>
      _ViewportBookmarksDialogState();
}

class _ViewportBookmarksDialogState extends State<ViewportBookmarksDialog> {
  late List<ViewportBookmark> _bookmarks;
  late final TextEditingController _nameController;
  String? _editingId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bookmarks = _sorted(widget.bookmarks);
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  List<ViewportBookmark> _sorted(Iterable<ViewportBookmark> bookmarks) =>
      bookmarks.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  ViewportBookmark? get _editingBookmark {
    final id = _editingId;
    if (id == null) return null;
    for (final bookmark in _bookmarks) {
      if (bookmark.id == id) return bookmark;
    }
    return null;
  }

  void _startCreate() {
    if (widget.readOnly || widget.onCreate == null) return;
    setState(() {
      _editingId = null;
      _nameController
        ..text = ''
        ..selection = const TextSelection.collapsed(offset: 0);
    });
  }

  void _startRename(ViewportBookmark bookmark) {
    if (widget.readOnly || widget.onRename == null) return;
    setState(() {
      _editingId = bookmark.id;
      _nameController
        ..text = bookmark.name
        ..selection = TextSelection.collapsed(offset: bookmark.name.length);
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingId = null;
      _nameController.clear();
    });
  }

  Future<void> _saveName() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final editing = _editingBookmark;
    if (editing == null && widget.onCreate == null) return;
    if (editing != null && widget.onRename == null) return;

    setState(() => _saving = true);
    try {
      final saved = editing == null
          ? await widget.onCreate!(name)
          : await widget.onRename!(editing, name);
      if (!mounted || saved == null) return;
      setState(() {
        if (editing == null) {
          _bookmarks = _sorted([saved, ..._bookmarks]);
        } else {
          _bookmarks = _sorted(
            _bookmarks.map((item) => item.id == saved.id ? saved : item),
          );
        }
        _editingId = null;
        _nameController.clear();
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(ViewportBookmark bookmark) async {
    if (_saving || widget.readOnly || widget.onDelete == null) return;
    final confirmed = await showUiDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final maxWidth = AppResponsive.dialogWidth(
          dialogContext,
          preferred: 420,
        );
        final maxHeight = AppResponsive.dialogHeight(
          dialogContext,
          preferred: 240,
        );
        return UiDialog(
          semanticsLabel: 'Delete viewport bookmark',
          constraints: AppResponsive.dialogConstraints(
            dialogContext,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
          ),
          builder: (context, style) => ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              child: Padding(
                padding: AppResponsive.dialogPadding(context),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Delete bookmark?', style: style.titleTextStyle),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '“${bookmark.name}” will be removed from this project.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        UiButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          variant: UiButtonVariant.ghost,
                          child: const Text('Cancel'),
                        ),
                        UiButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          variant: UiButtonVariant.destructive,
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      if (await widget.onDelete!(bookmark) && mounted) {
        setState(() {
          _bookmarks.removeWhere((item) => item.id == bookmark.id);
          if (_editingId == bookmark.id) {
            _editingId = null;
            _nameController.clear();
          }
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = AppResponsive.dialogWidth(context, preferred: 520);
    final height = AppResponsive.dialogHeight(context, preferred: 560);
    final editing = _editingBookmark;
    final canEdit =
        !widget.readOnly &&
        (widget.onCreate != null || widget.onRename != null);

    return UiDialog(
      semanticsLabel: 'Viewport bookmarks',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: width,
        maxHeight: height,
      ),
      builder: (context, style) => SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Viewport bookmarks',
                      style: style.titleTextStyle,
                    ),
                  ),
                  if (canEdit)
                    UiIconButton(
                      icon: Icons.add,
                      tooltip: 'Save current viewport',
                      onPressed: _startCreate,
                    ),
                  UiIconButton(
                    icon: Icons.close,
                    tooltip: 'Close bookmarks',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
              Text(
                'Save named camera positions and restore them anytime.',
                style: style.bodyTextStyle,
              ),
              if (editing != null || (canEdit && _editingId == null)) ...[
                const SizedBox(
                  height: AppSpacing.sm + AppSpacing.xs + AppSpacing.xxs,
                ),
                Row(
                  children: [
                    Expanded(
                      child: UiTextField(
                        controller: _nameController,
                        autofocus: true,
                        label: editing == null
                            ? 'New bookmark'
                            : 'Rename bookmark',
                        hint: 'e.g. Hero section',
                        onSubmitted: (_) => _saveName(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    UiIconButton(
                      icon: Icons.check,
                      tooltip: 'Save bookmark name',
                      onPressed: _saving ? null : _saveName,
                    ),
                    UiIconButton(
                      icon: Icons.close,
                      tooltip: 'Cancel edit',
                      onPressed: _saving ? null : _cancelEdit,
                    ),
                  ],
                ),
              ],
              Expanded(
                child: _bookmarks.isEmpty
                    ? SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.bookmark_border, size: 24),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'NO BOOKMARKS YET',
                              style: style.titleTextStyle,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Save the current viewport to create a reusable view.',
                              style: style.bodyTextStyle,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _bookmarks.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.xs),
                        itemBuilder: (context, index) {
                          final bookmark = _bookmarks[index];
                          return UiButton(
                            mainAxisSize: MainAxisSize.max,
                            onPressed: () {
                              widget.onSelect(bookmark);
                              Navigator.pop(context);
                            },
                            variant: UiButtonVariant.ghost,
                            prefix: const Icon(
                              Icons.bookmark_outline,
                              size: 18,
                            ),
                            child: Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          bookmark.name,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '${(bookmark.viewport.zoom * 100).round()}% zoom · ${bookmark.selectedNodeIds.length} selected',
                                          style: style.bodyTextStyle.copyWith(
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (canEdit) ...[
                                    UiIconButton(
                                      icon: Icons.edit_outlined,
                                      tooltip: 'Rename ${bookmark.name}',
                                      onPressed: () => _startRename(bookmark),
                                    ),
                                    UiIconButton(
                                      icon: Icons.delete_outline,
                                      tooltip: 'Delete ${bookmark.name}',
                                      onPressed: () => _delete(bookmark),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
              Align(
                alignment: Alignment.centerRight,
                child: UiButton(
                  onPressed: () => Navigator.pop(context),
                  variant: UiButtonVariant.ghost,
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
