import '../../../../app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/responsive.dart';
import '../../../../app/widgets/ui_primitives.dart';
import '../../domain/command_palette.dart';

class CanvasCommandPalette extends StatefulWidget {
  final List<CanvasCommandDescriptor> commands;
  final List<String> recentToolIds;
  final ValueChanged<String> onSelected;

  const CanvasCommandPalette({
    super.key,
    required this.commands,
    this.recentToolIds = const [],
    required this.onSelected,
  });

  @override
  State<CanvasCommandPalette> createState() => _CanvasCommandPaletteState();
}

class _CanvasCommandPaletteState extends State<CanvasCommandPalette> {
  final _queryController = TextEditingController();
  final _focusNode = FocusNode();
  String _query = '';
  int _selectedIndex = 0;

  List<CanvasCommandDescriptor> get _results {
    final matches = widget.commands
        .where((command) => command.enabled && command.matches(_query))
        .toList(growable: false);
    final sorted = [...matches]
      ..sort((a, b) {
        final score = b.score(_query).compareTo(a.score(_query));
        if (score != 0) return score;
        if (_query.trim().isEmpty) {
          final aRecent = _recentToolIndex(a);
          final bRecent = _recentToolIndex(b);
          if (aRecent != bRecent) return aRecent.compareTo(bRecent);
        }
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    return sorted;
  }

  int _recentToolIndex(CanvasCommandDescriptor command) {
    if (!command.id.startsWith('tool.')) return 1000;
    final toolId = command.id.substring('tool.'.length);
    final index = widget.recentToolIds.indexOf(toolId);
    return index < 0 ? 999 : index;
  }

  @override
  void initState() {
    super.initState();
    _queryController.addListener(() {
      if (!mounted) return;
      setState(() {
        _query = _queryController.text;
        _selectedIndex = 0;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _selectCurrent() {
    final results = _results;
    if (results.isEmpty) return;
    final index = _selectedIndex.clamp(0, results.length - 1);
    Navigator.of(context).pop();
    widget.onSelected(results[index].id);
  }

  void _moveSelection(int delta) {
    final results = _results;
    if (results.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, results.length - 1);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _selectCurrent();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final theme = Theme.of(context);
    final maxWidth = AppResponsive.dialogWidth(context, preferred: 680);
    final maxHeight = AppResponsive.dialogHeight(context, preferred: 620);
    return UiDialog(
      semanticsLabel: 'Command palette',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
      builder: (dialogContext, style) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Focus(
          focusNode: _focusNode,
          onKeyEvent: _onKey,
          child: Padding(
            padding: AppResponsive.dialogPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('COMMAND PALETTE', style: style.titleTextStyle),
                const SizedBox(height: AppSpacing.md),
                UiTextField(
                  controller: _queryController,
                  autofocus: true,
                  label: 'Search commands',
                  hint: 'Search commands, tools, or shortcuts',
                  prefix: const Icon(Icons.search),
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: results.isEmpty
                      ? Center(
                          child: Text(
                            'No matching commands',
                            style: theme.textTheme.bodyMedium,
                          ),
                        )
                      : ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (context, index) {
                            final command = results[index];
                            final selected = index == _selectedIndex;
                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.xs + AppSpacing.xxs,
                              ),
                              child: Semantics(
                                container: true,
                                button: true,
                                selected: selected,
                                label: command.title,
                                onTap: () {
                                  Navigator.of(dialogContext).pop();
                                  widget.onSelected(command.id);
                                },
                                child: ExcludeSemantics(
                                  child: UiButton(
                                    variant: selected
                                        ? UiButtonVariant.primary
                                        : UiButtonVariant.ghost,
                                    size: UiButtonSize.md,
                                    mainAxisSize: MainAxisSize.max,
                                    prefix: Icon(_iconFor(command.category)),
                                    onPressed: () {
                                      Navigator.of(dialogContext).pop();
                                      widget.onSelected(command.id);
                                    },
                                    child: Flexible(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  command.title,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  command.description,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style:
                                                      theme.textTheme.bodySmall,
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (command.shortcut != null) ...[
                                            const SizedBox(
                                              width: AppSpacing.sm,
                                            ),
                                            Text(
                                              command.shortcut!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.labelSmall,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '↑ ↓ Navigate   Enter Select   Esc Close',
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(CanvasCommandCategory category) {
    return switch (category) {
      CanvasCommandCategory.navigation => Icons.navigation_outlined,
      CanvasCommandCategory.create => Icons.add_box_outlined,
      CanvasCommandCategory.edit => Icons.edit_outlined,
      CanvasCommandCategory.arrange => Icons.account_tree_outlined,
      CanvasCommandCategory.view => Icons.visibility_outlined,
      CanvasCommandCategory.history => Icons.history,
      CanvasCommandCategory.review => Icons.rate_review_outlined,
      CanvasCommandCategory.export => Icons.file_upload_outlined,
    };
  }
}
