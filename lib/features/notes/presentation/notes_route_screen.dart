import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varian/app/responsive.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/features/auth/state/auth_provider.dart';
import 'package:varian/features/canvas/state/open_document_tabs_provider.dart';
import 'package:varian/features/notes/presentation/notes_editor.dart';
import 'package:varian/features/notes/presentation/notes_workspace_screen.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';

class NotesRouteScreen extends ConsumerStatefulWidget {
  const NotesRouteScreen({
    required this.noteId,
    this.anchorFragment,
    super.key,
  });

  final String noteId;
  final String? anchorFragment;

  @override
  ConsumerState<NotesRouteScreen> createState() => _NotesRouteScreenState();
}

class _NotesRouteScreenState extends ConsumerState<NotesRouteScreen> {
  bool _checking = true;
  bool _available = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_checkNote());
  }

  @override
  void didUpdateWidget(covariant NotesRouteScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId) unawaited(_checkNote());
  }

  Future<void> _checkNote() async {
    final generation = ++_generation;
    final before = ref.read(workspaceNotesProvider);
    final accountId = before.accountId;
    final auth = ref.read(authUserProvider);
    if (auth.isLoading) {
      if (mounted && generation == _generation) {
        setState(() {
          _checking = true;
          _available = false;
        });
      }
      return;
    }
    final user = auth.asData?.value;
    final note =
        accountId != null && user?.id == accountId && user?.isAnonymous == false
        ? await ref
              .read(workspaceNotesProvider.notifier)
              .openNote(widget.noteId)
        : null;
    final beforeTabSelect = ref.read(workspaceNotesProvider);
    if (note != null &&
        (note.projectId != null || note.ownerUserId == accountId) &&
        beforeTabSelect.accountId == accountId) {
      await ref
          .read(activeDocumentTabControllerProvider)
          .select(OpenDocumentTab.note(note));
    }
    if (!mounted || generation != _generation) return;
    final current = ref.read(workspaceNotesProvider);
    setState(() {
      _checking = false;
      _available =
          note != null &&
          (note.projectId != null || note.ownerUserId == accountId) &&
          current.accountId == accountId;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(workspaceNotesProvider, (previous, next) {
      if (previous?.accountId != next.accountId) {
        setState(() {
          _checking = true;
          _available = false;
        });
        unawaited(_checkNote());
      }
    });
    ref.listen(authUserProvider, (previous, next) {
      if (previous?.value?.id != next.value?.id ||
          previous?.hasValue != next.hasValue ||
          previous?.isLoading != next.isLoading) {
        setState(() {
          _checking = true;
          _available = false;
        });
        if (!next.isLoading) unawaited(_checkNote());
      }
    });
    if (_available) {
      return NotesWorkspaceScreen(
        selectedNoteId: widget.noteId,
        selectedAnchorFragment: widget.anchorFragment,
      );
    }
    return UiPageScaffold(
      title: const Text('Private Note'),
      leading: IconButton(
        tooltip: 'Back to Canvas',
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/');
          }
        },
        icon: const Icon(Icons.arrow_back),
      ),
      childPad: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: AppResponsive.pagePadding(context),
            child: _checking
                ? const Center(child: UiLoadingState())
                : _available
                ? NotesEditor(
                    key: ValueKey('notes-editor-${widget.noteId}'),
                    noteId: widget.noteId,
                    anchorFragment: widget.anchorFragment,
                  )
                : const Center(
                    child: Text('This Note is unavailable for this account.'),
                  ),
          ),
        ),
      ),
    );
  }
}
