import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';

enum QuickCaptureAction {
  text,
  stickyNote,
  frame,
  rectangle,
  image,
  link,
  document,
  undo,
  redo,
  search,
}

class QuickCaptureCommand {
  final QuickCaptureAction action;
  final String label;
  final String description;
  final IconData icon;
  final String? shortcut;
  final bool enabled;

  const QuickCaptureCommand({
    required this.action,
    required this.label,
    required this.description,
    required this.icon,
    this.shortcut,
    this.enabled = true,
  });
}

class QuickCapturePalette extends StatefulWidget {
  final bool readOnly;
  final bool canUndo;
  final bool canRedo;
  final ValueChanged<QuickCaptureAction> onSelected;

  const QuickCapturePalette({
    super.key,
    required this.onSelected,
    this.readOnly = false,
    this.canUndo = true,
    this.canRedo = true,
  });

  @override
  State<QuickCapturePalette> createState() => _QuickCapturePaletteState();
}

class _QuickCapturePaletteState extends State<QuickCapturePalette> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  int _selectedIndex = 0;
  bool _closing = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<QuickCaptureCommand> get _commands {
    final safe = <QuickCaptureCommand>[
      const QuickCaptureCommand(
        action: QuickCaptureAction.search,
        label: 'Search canvas',
        description: 'Find canvas objects and projects',
        icon: Icons.search,
        shortcut: 'Ctrl+F',
      ),
    ];
    if (widget.readOnly) return safe;

    return [
      const QuickCaptureCommand(
        action: QuickCaptureAction.text,
        label: 'Add text',
        description: 'Insert a text object at the viewport center',
        icon: Icons.text_fields,
        shortcut: 'T',
      ),
      const QuickCaptureCommand(
        action: QuickCaptureAction.stickyNote,
        label: 'Add sticky note',
        description: 'Insert a sticky note at the viewport center',
        icon: Icons.sticky_note_2_outlined,
        shortcut: 'N',
      ),
      const QuickCaptureCommand(
        action: QuickCaptureAction.frame,
        label: 'Add frame',
        description: 'Insert a frame at the viewport center',
        icon: Icons.crop_free,
        shortcut: 'F',
      ),
      const QuickCaptureCommand(
        action: QuickCaptureAction.rectangle,
        label: 'Add rectangle',
        description: 'Insert a rectangle at the viewport center',
        icon: Icons.crop_square,
        shortcut: 'R',
      ),
      const QuickCaptureCommand(
        action: QuickCaptureAction.image,
        label: 'Add image',
        description: 'Choose an image and place it at the viewport center',
        icon: Icons.image_outlined,
        shortcut: 'I',
      ),
      const QuickCaptureCommand(
        action: QuickCaptureAction.link,
        label: 'Add link',
        description: 'Insert a link card at the viewport center',
        icon: Icons.link_outlined,
      ),
      const QuickCaptureCommand(
        action: QuickCaptureAction.document,
        label: 'Add document',
        description: 'Insert a document at the viewport center',
        icon: Icons.description_outlined,
      ),
      QuickCaptureCommand(
        action: QuickCaptureAction.undo,
        label: 'Undo',
        description: 'Undo the most recent canvas change',
        icon: Icons.undo,
        shortcut: 'Ctrl+Z',
        enabled: widget.canUndo,
      ),
      QuickCaptureCommand(
        action: QuickCaptureAction.redo,
        label: 'Redo',
        description: 'Redo the most recently undone canvas change',
        icon: Icons.redo,
        shortcut: 'Ctrl+Y',
        enabled: widget.canRedo,
      ),
      ...safe,
    ];
  }

  List<QuickCaptureCommand> get _filteredCommands {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _commands;
    return _commands
        .where(
          (command) =>
              command.label.toLowerCase().contains(query) ||
              command.description.toLowerCase().contains(query) ||
              (command.shortcut?.toLowerCase().contains(query) ?? false),
        )
        .toList();
  }

  void _select(QuickCaptureCommand command) {
    if (_closing || !command.enabled) return;
    _closing = true;
    final action = command.action;
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onSelected(action);
    });
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  void _moveSelection(int delta) {
    final commands = _filteredCommands;
    if (commands.isEmpty) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, commands.length - 1);
    });
  }

  void _activateSelected() {
    final commands = _filteredCommands;
    if (commands.isEmpty || _selectedIndex >= commands.length) return;
    _select(commands[_selectedIndex]);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      if (_filteredCommands.isNotEmpty) setState(() => _selectedIndex = 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      final count = _filteredCommands.length;
      if (count > 0) setState(() => _selectedIndex = count - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      _activateSelected();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final commands = _filteredCommands;
    if (commands.isEmpty) _selectedIndex = 0;
    if (_selectedIndex >= commands.length && commands.isNotEmpty) {
      _selectedIndex = commands.length - 1;
    }

    final width = AppResponsive.dialogWidth(context, preferred: 480);
    final height = AppResponsive.dialogHeight(context, preferred: 520);

    return UiDialog(
      semanticsLabel: 'Quick capture command palette',
      constraints: AppResponsive.dialogConstraints(
        context,
        maxWidth: 480,
        maxHeight: 520,
      ),
      builder: (context, style) => Focus(
        onKeyEvent: _handleKeyEvent,
        child: SizedBox(
          width: width,
          height: height,
          child: Padding(
            padding: AppResponsive.dialogPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.bolt_outlined, color: tokens.accent, size: 22),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text('QUICK CAPTURE', style: style.titleTextStyle),
                    ),
                    UiIconButton(
                      icon: Icons.close,
                      tooltip: 'Close quick capture',
                      onPressed: _close,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                UiTextField(
                  controller: _searchController,
                  hint: 'Search commands...',
                  autofocus: true,
                  onChanged: (value) => setState(() {
                    _query = value;
                    _selectedIndex = 0;
                  }),
                  onSubmitted: (_) => _activateSelected(),
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: commands.isEmpty
                      ? const UiEmptyState(
                          icon: Icons.search_off,
                          title: 'NO COMMANDS',
                          message: 'Try another command name.',
                        )
                      : ListView.builder(
                          itemCount: commands.length,
                          itemBuilder: (context, index) {
                            final command = commands[index];
                            final selected = index == _selectedIndex;
                            final shortcut = command.shortcut;
                            return Focus(
                              onFocusChange: (focused) {
                                if (focused && mounted) {
                                  setState(() => _selectedIndex = index);
                                }
                              },
                              canRequestFocus: command.enabled,
                              child: Semantics(
                                button: true,
                                selected: selected,
                                enabled: command.enabled,
                                label: shortcut == null
                                    ? '${command.label}. ${command.description}'
                                    : '${command.label}. ${command.description}. $shortcut',
                                child: UiButton(
                                  onPressed: command.enabled
                                      ? () => _select(command)
                                      : null,
                                  variant: selected
                                      ? UiButtonVariant.primary
                                      : UiButtonVariant.ghost,
                                  prefix: Icon(
                                    command.icon,
                                    size: 18,
                                    color: command.enabled
                                        ? (selected
                                              ? tokens.accentForeground
                                              : tokens.accent)
                                        : tokens.textMuted,
                                  ),
                                  suffix: shortcut == null
                                      ? null
                                      : Text(
                                          shortcut,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall!
                                              .copyWith(
                                                color: selected
                                                    ? tokens.accentForeground
                                                          .withValues(
                                                            alpha: 0.72,
                                                          )
                                                    : tokens.textMuted,
                                              ),
                                        ),
                                  child: Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          command.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium!
                                              .copyWith(
                                                color: command.enabled
                                                    ? (selected
                                                          ? tokens
                                                                .accentForeground
                                                          : tokens.text)
                                                    : tokens.textMuted,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        Text(
                                          command.description,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall!
                                              .copyWith(
                                                color: selected
                                                    ? tokens.accentForeground
                                                          .withValues(
                                                            alpha: 0.72,
                                                          )
                                                    : tokens.textMuted,
                                              ),
                                        ),
                                      ],
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
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall!.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
