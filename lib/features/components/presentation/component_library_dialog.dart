import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/responsive.dart';
import '../../../app/theme.dart';
import '../../../app/widgets/ui_primitives.dart';
import '../../../domain/models/component_payload.dart';
import '../../../domain/models/node.dart';
import '../domain/component_library.dart';

class ComponentLibraryDialog extends StatefulWidget {
  final List<CanvasNode> nodes;
  final bool readOnly;
  final ValueChanged<CanvasNode>? onInsert;
  final ComponentLibrary? initialLibrary;
  final Future<void> Function(ComponentLibrary library)? onLibraryChanged;

  const ComponentLibraryDialog({
    required this.nodes,
    this.readOnly = false,
    this.onInsert,
    this.initialLibrary,
    this.onLibraryChanged,
    super.key,
  });

  @override
  State<ComponentLibraryDialog> createState() => _ComponentLibraryDialogState();
}

class _ComponentLibraryDialogState extends State<ComponentLibraryDialog> {
  final _queryController = TextEditingController();
  String _query = '';
  late ComponentLibrary _library;
  bool _publishedOnly = false;
  bool _pinnedOnly = false;

  @override
  void initState() {
    super.initState();
    final discovered = ComponentLibrary.discover(widget.nodes);
    _library = (widget.initialLibrary ?? const ComponentLibrary()).merge(
      discovered,
    );
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allEntries = _library.search(_query);
    final entries = _publishedOnly
        ? allEntries.where((entry) => entry.published).toList(growable: false)
        : allEntries;
    final visibleEntries = _pinnedOnly
        ? entries.where((entry) => entry.pinned).toList(growable: false)
        : entries;
    final width = AppResponsive.dialogWidth(context, preferred: 760);
    final height = AppResponsive.dialogHeight(context, preferred: 600);

    return UiDialog(
      key: const ValueKey('component-library-dialog'),
      semanticsLabel: 'Component library',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 760,
        maxHeight: 600,
      ),
      builder: (context, style) => SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: AppResponsive.dialogPadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final title = Row(
                    children: [
                      Icon(
                        Icons.widgets_outlined,
                        color: context.appTokens.accent,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Component Library',
                          style: style.titleTextStyle,
                        ),
                      ),
                      UiIconButton(
                        icon: Icons.close,
                        tooltip: 'Close component library',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  );
                  final count = UiBadge('${visibleEntries.length} components');
                  if (constraints.maxWidth < 420) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        title,
                        const SizedBox(height: AppSpacing.xs),
                        Align(alignment: Alignment.centerLeft, child: count),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: AppSpacing.sm),
                      count,
                    ],
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              UiSurface(
                color: context.appTokens.panelElevated,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    UiTextField(
                      controller: _queryController,
                      label: 'Search components',
                      hint: 'Name, description, or tag',
                      prefix: const Icon(Icons.search),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    UiSwitch(
                      key: const ValueKey('component-published-only'),
                      label: const Text('Show published only'),
                      semanticsLabel: 'Show published components only',
                      value: _publishedOnly,
                      onChange: (value) =>
                          setState(() => _publishedOnly = value),
                    ),
                    UiSwitch(
                      key: const ValueKey('component-pinned-only'),
                      label: const Text('Show pinned only'),
                      semanticsLabel: 'Show pinned components only',
                      value: _pinnedOnly,
                      onChange: (value) => setState(() => _pinnedOnly = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: visibleEntries.isEmpty
                    ? UiSurface(
                        color: context.appTokens.panelElevated,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: UiEmptyState(
                          icon: _pinnedOnly
                              ? Icons.push_pin_outlined
                              : Icons.widgets_outlined,
                          title: _pinnedOnly
                              ? 'NO PINNED COMPONENTS'
                              : _publishedOnly
                              ? 'NO PUBLISHED COMPONENTS'
                              : 'NO COMPONENTS FOUND',
                          message: _query.isEmpty
                              ? 'Try another filter to find a reusable component.'
                              : 'No components match “$_query”.',
                        ),
                      )
                    : ListView.separated(
                        itemCount: visibleEntries.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final entry = visibleEntries[index];
                          final source = widget.nodes
                              .where((node) => node.id == entry.sourceNodeId)
                              .firstOrNull;
                          final tokens = context.appTokens;
                          return UiSurface(
                            key: ValueKey('component-entry-${entry.id}'),
                            padding: const EdgeInsets.all(AppSpacing.md),
                            color: tokens.panelElevated,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.widgets_outlined,
                                      color: tokens.accent,
                                    ),
                                    const SizedBox(
                                      width: AppSpacing.md - AppSpacing.xxs,
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium!
                                                .copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(
                                            height: AppSpacing.xxs + 1,
                                          ),
                                          Text(
                                            '${entry.description.isEmpty ? 'Component' : entry.description} / v${entry.version} / Used ${ComponentLibrary.usageCount(widget.nodes, entry.id)}x${entry.tags.isEmpty ? '' : ' / ${entry.tags.join(', ')}'}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall!
                                                .copyWith(
                                                  color: tokens.textMuted,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Wrap(
                                  alignment: WrapAlignment.end,
                                  spacing: AppSpacing.sm,
                                  runSpacing: AppSpacing.sm,
                                  children: [
                                    UiIconButton(
                                      key: ValueKey(
                                        'component-pin-${entry.id}',
                                      ),
                                      icon: entry.pinned
                                          ? Icons.push_pin
                                          : Icons.push_pin_outlined,
                                      tooltip: entry.pinned
                                          ? 'Unpin component'
                                          : 'Pin component',
                                      selected: entry.pinned,
                                      onPressed: widget.readOnly
                                          ? null
                                          : () => unawaited(
                                              _setPinned(
                                                entry.id,
                                                !entry.pinned,
                                              ),
                                            ),
                                    ),
                                    UiBadge(
                                      entry.published ? 'Published' : 'Draft',
                                      variant: entry.published
                                          ? UiBadgeVariant.success
                                          : UiBadgeVariant.outline,
                                    ),
                                    if (!widget.readOnly && source != null)
                                      UiButton(
                                        key: ValueKey(
                                          'component-${entry.published ? 'un' : ''}publish-${entry.id}',
                                        ),
                                        onPressed: () => unawaited(
                                          _setPublished(
                                            entry.id,
                                            !entry.published,
                                          ),
                                        ),
                                        variant: UiButtonVariant.ghost,
                                        size: UiButtonSize.sm,
                                        child: Text(
                                          entry.published
                                              ? 'Unpublish'
                                              : 'Publish',
                                        ),
                                      ),
                                    if (entry.published &&
                                        !widget.readOnly &&
                                        source != null &&
                                        widget.onInsert != null)
                                      UiButton(
                                        key: ValueKey(
                                          'component-insert-${entry.id}',
                                        ),
                                        onPressed: () {
                                          final instance =
                                              ComponentInstanceFactory.createInstance(
                                                source,
                                                origin: const Offset(100, 100),
                                              );
                                          widget.onInsert!(instance);
                                          Navigator.of(context).pop();
                                        },
                                        size: UiButtonSize.sm,
                                        child: const Text('Insert'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: UiButton(
                  onPressed: () => Navigator.of(context).pop(),
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

  Future<void> _setPublished(String id, bool published) async {
    final next = _library.setPublished(id, published);
    if (next == _library) return;
    setState(() => _library = next);
    final callback = widget.onLibraryChanged;
    if (callback == null) return;
    try {
      await callback(next);
    } catch (error) {
      if (!mounted) return;
      showUiToast(
        context,
        'Component library save failed: $error',
        variant: UiToastVariant.error,
      );
    }
  }

  Future<void> _setPinned(String id, bool pinned) async {
    final next = _library.setPinned(id, pinned);
    if (next == _library) return;
    setState(() => _library = next);
    final callback = widget.onLibraryChanged;
    if (callback == null) return;
    try {
      await callback(next);
    } catch (error) {
      if (!mounted) return;
      showUiToast(
        context,
        'Component library save failed: $error',
        variant: UiToastVariant.error,
      );
    }
  }
}
