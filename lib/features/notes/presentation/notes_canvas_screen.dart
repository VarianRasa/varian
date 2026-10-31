import 'dart:async';

import 'package:characters/characters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:varian/features/auth/state/auth_provider.dart';
import 'package:varian/features/notes/data/notes_canvas_repository.dart';
import 'package:varian/features/notes/domain/notes_canvas_board.dart';
import 'package:varian/features/notes/domain/notes_canvas_board_state.dart';
import 'package:varian/features/notes/domain/notes_canvas_document.dart';
import 'package:varian/features/notes/domain/notes_canvas_operation.dart';
import 'package:varian/features/notes/domain/workspace_note.dart';
import 'package:varian/features/notes/state/notes_canvas_provider.dart';
import 'package:varian/features/notes/state/notes_offline_provider.dart';
import 'package:varian/features/notes/state/workspace_notes_provider.dart';

class NotesCanvasScreen extends ConsumerStatefulWidget {
  const NotesCanvasScreen({this.boardId, this.projectId, super.key});

  final String? boardId;
  final String? projectId;

  @override
  ConsumerState<NotesCanvasScreen> createState() => _NotesCanvasScreenState();
}

class _NotesCanvasScreenState extends ConsumerState<NotesCanvasScreen> {
  NotesCanvasBoard? _board;
  NotesCanvasDocument? _document;
  NotesCanvasCard? _lastDeletedCard;
  String? _accountId;
  String? _canvasReplicaId;
  Object? _error;
  bool _hasEncryptionKey = false;
  bool _loadingBoard = false;
  bool _saving = false;
  final Set<String> _selectedCardIds = {};
  final Map<String, Offset> _dragOffsets = {};

  @override
  void initState() {
    super.initState();
    if (widget.boardId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadBoard());
    }
  }

  @override
  void didUpdateWidget(covariant NotesCanvasScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.boardId != widget.boardId ||
        oldWidget.projectId != widget.projectId) {
      _board = null;
      _document = null;
      _accountId = null;
      _canvasReplicaId = null;
      _hasEncryptionKey = false;
      _loadingBoard = false;
      _error = null;
      _selectedCardIds.clear();
      _dragOffsets.clear();
      if (widget.boardId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _loadBoard());
      }
    }
  }

  Future<void> _loadBoard() async {
    final boardId = widget.boardId;
    final projectId = widget.projectId;
    final accountId = ref.read(authUserProvider).valueOrNull?.id;
    if (boardId == null || accountId == null) return;
    setState(() {
      _accountId = accountId;
      _canvasReplicaId = null;
      _hasEncryptionKey = false;
      _loadingBoard = true;
      _error = null;
    });
    try {
      final board = await ref
          .read(notesCanvasRepositoryProvider)
          .getBoard(boardId: boardId, expectedAccountId: accountId);
      if (!_isCurrentBoardRequest(accountId, boardId, projectId)) return;
      if (board.projectId != projectId) {
        throw const NotesCanvasUnavailableException();
      }
      var document = NotesCanvasDocument.fromSnapshot(board.crdtSnapshot);
      final offline = ref.read(notesOfflineServiceProvider);
      String? replicaId;
      var hasEncryptionKey = false;
      Object? localStorageError;
      if (offline != null) {
        try {
          final key = await offline.keyForAccount(accountId);
          replicaId = await offline.store.loadOrCreateCanvasReplicaId(
            accountId: accountId,
          );
          hasEncryptionKey = key?.length == 32 && replicaId != null;
          if (key?.length == 32 && replicaId == null) {
            localStorageError = StateError(
              'Encrypted Notes storage is unavailable.',
            );
          }
        } catch (error) {
          localStorageError = error;
        }
      }
      if (!_isCurrentBoardRequest(accountId, boardId, projectId)) return;
      setState(() {
        _board = board;
        _canvasReplicaId = replicaId;
        _hasEncryptionKey = hasEncryptionKey;
        _error = localStorageError;
      });

      if (hasEncryptionKey) {
        final sync = ref.read(notesCanvasSyncRepositoryProvider);
        if (sync != null) {
          try {
            final synced = await sync.synchronizeBoard(
              accountId: accountId,
              boardId: board.id,
            );
            if (!_isCurrentBoardRequest(accountId, boardId, projectId)) return;
            document = NotesCanvasDocument.fromSnapshot(synced.crdtSnapshot);
            setState(() => _board = synced);
          } catch (error) {
            final cached = await sync.readCachedDocument(
              accountId: accountId,
              boardId: board.id,
            );
            if (!_isCurrentBoardRequest(accountId, boardId, projectId)) return;
            if (cached != null) document = cached;
            setState(() => _error = error);
          }
        }
      }
      if (!_isCurrentBoardRequest(accountId, boardId, projectId)) return;
      setState(() {
        _document = document;
        _loadingBoard = false;
      });
    } catch (error) {
      if (!_isCurrentBoardRequest(accountId, boardId, projectId)) return;
      setState(() {
        _board = null;
        _document = null;
        _canvasReplicaId = null;
        _hasEncryptionKey = false;
        _error = error;
        _loadingBoard = false;
      });
    }
  }

  bool _isCurrent(String accountId) =>
      mounted && ref.read(authUserProvider).valueOrNull?.id == accountId;

  bool _isCurrentBoardRequest(
    String accountId,
    String boardId,
    String? projectId,
  ) =>
      _isCurrent(accountId) &&
      widget.boardId == boardId &&
      widget.projectId == projectId;

  String _replicaFor(String accountId) {
    final replicaId = _canvasReplicaId;
    if (!_hasEncryptionKey || _accountId != accountId || replicaId == null) {
      throw StateError('Encrypted Notes storage is unavailable.');
    }
    return replicaId;
  }

  Future<void> _createBoard() async {
    final accountId = ref.read(authUserProvider).valueOrNull?.id;
    if (accountId == null) return;
    final title = await _requestText(
      title: 'New Notes Canvas',
      label: 'Board name',
      initialValue: 'Untitled Canvas',
    );
    if (!mounted || title == null || title.trim().isEmpty) return;
    final boardId = const Uuid().v4();
    final document = NotesCanvasDocument.fromState(
      boardId,
      NotesCanvasBoardState.empty(),
    );
    try {
      await ref
          .read(notesCanvasRepositoryProvider)
          .createBoard(
            boardId: boardId,
            title: title.trim(),
            projectId: widget.projectId,
            document: document,
            expectedAccountId: accountId,
          );
      if (!_isCurrent(accountId)) return;
      ref.invalidate(notesCanvasBoardsProvider((accountId, widget.projectId)));
      _goToBoard(boardId);
    } catch (error) {
      if (!mounted) return;
      _showMessage(_failureMessage(error));
    }
  }

  Future<String?> _requestText({
    required String title,
    required String label,
    required String initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 120,
            decoration: InputDecoration(labelText: label),
            onSubmitted: (_) =>
                Navigator.of(dialogContext).pop(controller.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _addTextCard() async {
    final document = _document;
    final accountId = _accountId;
    if (document == null || accountId == null) return;
    final markdown = await _requestText(
      title: 'Add text card',
      label: 'Markdown',
      initialValue: '',
    );
    if (!mounted || markdown == null || !_isCurrent(accountId)) return;
    await _commitEdits(
      (current) => current.createTextCard(
        replicaId: _replicaFor(accountId),
        card: NotesCanvasTextCard(
          id: const Uuid().v4(),
          markdown: markdown,
          x: 80 + (current.boardState.cards.length % 5) * 340,
          y: 80 + (current.boardState.cards.length ~/ 5) * 240,
          width: 300,
          height: 180,
        ),
      ),
    );
  }

  Future<void> _addNoteCard() async {
    final document = _document;
    final accountId = _accountId;
    if (document == null || accountId == null) return;
    final notes = ref
        .read(workspaceNotesProvider)
        .notes
        .where((note) => _isInScope(note, accountId))
        .toList(growable: false);
    if (notes.isEmpty) {
      _showMessage('No readable notes are available in this scope.');
      return;
    }
    final note = await showDialog<WorkspaceNote>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Link a note'),
        content: SizedBox(
          width: 480,
          height: 360,
          child: ListView.builder(
            itemCount: notes.length,
            itemBuilder: (context, index) {
              final item = notes[index];
              return ListTile(
                title: Text(item.title),
                subtitle: Text(item.id),
                onTap: () => Navigator.of(dialogContext).pop(item),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!mounted || note == null || !_isCurrent(accountId)) return;
    await _commitEdit(
      (current) => current.createCard(
        replicaId: _replicaFor(accountId),
        card: NotesCanvasNoteCard(
          id: const Uuid().v4(),
          noteId: note.id,
          x: 80 + (current.boardState.cards.length % 5) * 340,
          y: 80 + (current.boardState.cards.length ~/ 5) * 240,
          width: 300,
          height: 180,
        ),
      ),
    );
  }

  bool _isInScope(WorkspaceNote note, String accountId) =>
      note.deletedAt == null &&
      (widget.projectId == null
          ? note.projectId == null && note.ownerUserId == accountId
          : note.projectId == widget.projectId);

  Future<void> _editTextCard(NotesCanvasTextCard card) async {
    final document = _document;
    final accountId = _accountId;
    if (document == null || accountId == null) return;
    final markdown = await _requestText(
      title: 'Edit text card',
      label: 'Markdown',
      initialValue: card.markdown,
    );
    if (!mounted || markdown == null || !_isCurrent(accountId)) return;
    await _commitEdits(
      (current) => [
        ...current.deleteText(
          replicaId: _replicaFor(accountId),
          cardId: card.id,
          start: 0,
          end: current.boardState.cards
              .whereType<NotesCanvasTextCard>()
              .firstWhere((item) => item.id == card.id)
              .markdown
              .characters
              .length,
        ),
        ...current.insertText(
          replicaId: _replicaFor(accountId),
          cardId: card.id,
          offset: 0,
          text: markdown,
        ),
      ],
    );
  }

  Future<void> _moveCard(String cardId, Offset delta) async {
    final accountId = _accountId;
    if (accountId == null || delta == Offset.zero) return;
    await _commitEdit(
      (document) => document.moveCard(
        replicaId: _replicaFor(accountId),
        cardId: cardId,
        dx: delta.dx,
        dy: delta.dy,
      ),
    );
  }

  Future<void> _deleteCard(String cardId) async {
    final card = _document?.boardState.cards
        .where((item) => item.id == cardId)
        .firstOrNull;
    final accountId = _accountId;
    if (card == null || accountId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove card?'),
        content: const Text(
          'This removes the card from this board. The linked note remains unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove card'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_isCurrent(accountId)) return;
    _lastDeletedCard = card;
    await _commitEdit(
      (document) => document.tombstoneCard(
        replicaId: _replicaFor(accountId),
        cardId: cardId,
      ),
    );
    if (mounted) setState(() => _selectedCardIds.remove(cardId));
  }

  Future<void> _restoreLastCard() async {
    final card = _lastDeletedCard;
    final accountId = _accountId;
    if (card == null || accountId == null) return;
    final restored = switch (card) {
      NotesCanvasNoteCard() => NotesCanvasNoteCard(
        id: const Uuid().v4(),
        noteId: card.noteId,
        x: card.x,
        y: card.y,
        width: card.width,
        height: card.height,
      ),
      NotesCanvasTextCard() => NotesCanvasTextCard(
        id: const Uuid().v4(),
        markdown: '',
        x: card.x,
        y: card.y,
        width: card.width,
        height: card.height,
      ),
    };
    await _commitEdits((document) {
      final replicaId = _replicaFor(accountId);
      final create = document.createCard(replicaId: replicaId, card: restored);
      if (card case final NotesCanvasTextCard textCard
          when textCard.markdown.isNotEmpty) {
        return [
          create,
          ...document.insertText(
            replicaId: replicaId,
            cardId: restored.id,
            offset: 0,
            text: textCard.markdown,
          ),
        ];
      }
      return [create];
    });
    _lastDeletedCard = null;
  }

  Future<void> _connectSelectedCards() async {
    final accountId = _accountId;
    if (accountId == null || _selectedCardIds.length != 2) return;
    final endpoints = _selectedCardIds.toList()..sort();
    await _commitEdit(
      (document) => document.createEdge(
        replicaId: _replicaFor(accountId),
        edge: NotesCanvasEdge(
          id: const Uuid().v4(),
          fromCardId: endpoints.first,
          toCardId: endpoints.last,
        ),
      ),
    );
    if (mounted) setState(_selectedCardIds.clear);
  }

  Future<void> _commitEdit(
    NotesCanvasOperation Function(NotesCanvasDocument) edit,
  ) async => _commitEdits((document) => [edit(document)]);

  Future<void> _commitEdits(
    List<NotesCanvasOperation> Function(NotesCanvasDocument) edit,
  ) async {
    final before = _document;
    final accountId = _accountId;
    final board = _board;
    final projectId = widget.projectId;
    if (before == null ||
        board == null ||
        accountId == null ||
        !_hasEncryptionKey ||
        _canvasReplicaId == null ||
        _saving) {
      return;
    }
    final previousSnapshot = before.snapshotState();
    List<NotesCanvasOperation> operations;
    try {
      operations = edit(before);
      if (operations.isEmpty) return;
      setState(() {
        _saving = true;
        _error = null;
      });
      final sync = ref.read(notesCanvasSyncRepositoryProvider);
      if (sync == null) {
        throw StateError('Encrypted Notes storage is unavailable.');
      }
      for (final operation in operations) {
        await sync.queueOperation(
          accountId: accountId,
          boardId: board.id,
          document: before,
          operation: operation,
        );
      }
      if (!_isCurrentBoardRequest(accountId, board.id, projectId)) return;
      setState(() => _document = before);
      try {
        final synced = await sync.synchronizeBoard(
          accountId: accountId,
          boardId: board.id,
        );
        if (!_isCurrentBoardRequest(accountId, board.id, projectId)) return;
        setState(() {
          _board = synced;
          _document = NotesCanvasDocument.fromSnapshot(synced.crdtSnapshot);
        });
      } catch (error) {
        if (!_isCurrentBoardRequest(accountId, board.id, projectId)) return;
        setState(() => _error = error);
        _showMessage(
          'Change encrypted on this device. Sync will retry when available.',
        );
      }
    } catch (error) {
      if (_isCurrentBoardRequest(accountId, board.id, projectId)) {
        setState(() {
          _document = NotesCanvasDocument.fromSnapshot(previousSnapshot);
          _error = error;
        });
        _showMessage(_failureMessage(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _goToBoard(String boardId) {
    final uri = Uri(
      path: '/notes/canvas/${Uri.encodeComponent(boardId)}',
      queryParameters: widget.projectId == null
          ? null
          : {'projectId': widget.projectId},
    );
    context.go(uri.toString());
  }

  String _failureMessage(Object error) {
    if (error is NotesCanvasUnavailableException) {
      return 'This board or one of its linked notes is unavailable in this scope.';
    }
    if (error is NotesCanvasRevisionConflictException) {
      return 'The board changed elsewhere. Reload and retry your edit.';
    }
    if (error is StateError && error.message.contains('Project edit')) {
      return 'Project editors only can change this board.';
    }
    if (error is StateError && error.message.contains('Encrypted Notes')) {
      return 'Set up or unlock encrypted Notes storage before editing this board.';
    }
    return 'Canvas could not sync. The encrypted edit remains queued when available.';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).valueOrNull;
    if (user?.id == null || user!.isAnonymous) {
      return const Scaffold(
        body: Center(child: Text('Sign in to access Notes Canvas.')),
      );
    }
    if (widget.boardId == null) return _buildBoardLibrary(user.id);
    return _buildBoardEditor(user.id);
  }

  Widget _buildBoardLibrary(String accountId) {
    final boards = ref.watch(
      notesCanvasBoardsProvider((accountId, widget.projectId)),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes Canvas'),
        leading: IconButton(
          tooltip: 'Back to Notes',
          onPressed: () => context.go('/notes'),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            key: const ValueKey('notes-canvas-create-board'),
            tooltip: 'Create board',
            onPressed: _createBoard,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: boards.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _CanvasErrorState(
          message: _failureMessage(error),
          onRetry: () => ref.invalidate(
            notesCanvasBoardsProvider((accountId, widget.projectId)),
          ),
        ),
        data: (items) => items.isEmpty
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.dashboard_customize_outlined, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        widget.projectId == null
                            ? 'No private boards yet.'
                            : 'No boards in this project yet.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _createBoard,
                        icon: const Icon(Icons.add),
                        label: const Text('Create board'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final board = items[index];
                  return Card(
                    child: ListTile(
                      key: ValueKey('notes-canvas-board-${board.id}'),
                      leading: const Icon(Icons.dashboard_outlined),
                      title: Text(board.title),
                      subtitle: Text(
                        '${board.state.cards.length} cards · revision ${board.revision}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _goToBoard(board.id),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: boards.valueOrNull?.isNotEmpty == true
          ? FloatingActionButton.extended(
              onPressed: _createBoard,
              icon: const Icon(Icons.add),
              label: const Text('New board'),
            )
          : null,
    );
  }

  Widget _buildBoardEditor(String accountId) {
    if (_accountId != accountId || _document == null) {
      if (!_loadingBoard && _accountId != accountId) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _loadBoard());
      }
      if (_error != null && !_loadingBoard) {
        return Scaffold(
          appBar: AppBar(title: const Text('Notes Canvas')),
          body: _CanvasErrorState(
            message: _failureMessage(_error!),
            onRetry: _loadBoard,
          ),
        );
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final document = _document!;
    final board = _board;
    final scopedNotes = ref
        .watch(workspaceNotesProvider)
        .notes
        .where((note) => _isInScope(note, accountId))
        .toList(growable: false);
    final hasKey = _hasEncryptionKey && _canvasReplicaId != null;
    final selected = _selectedCardIds;

    return Scaffold(
      appBar: AppBar(
        title: Text(board?.title ?? 'Notes Canvas'),
        leading: IconButton(
          tooltip: 'Boards',
          onPressed: () => context.go(
            Uri(
              path: '/notes/canvas',
              queryParameters: widget.projectId == null
                  ? null
                  : {'projectId': widget.projectId},
            ).toString(),
          ),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            key: const ValueKey('notes-canvas-add-note'),
            tooltip: 'Add note card',
            onPressed: _saving || !hasKey ? null : _addNoteCard,
            icon: const Icon(Icons.note_add_outlined),
          ),
          IconButton(
            key: const ValueKey('notes-canvas-add-text'),
            tooltip: 'Add text card',
            onPressed: _saving || !hasKey ? null : _addTextCard,
            icon: const Icon(Icons.text_fields),
          ),
          IconButton(
            key: const ValueKey('notes-canvas-connect-cards'),
            tooltip: 'Connect selected cards',
            onPressed: _saving || !hasKey || selected.length != 2
                ? null
                : _connectSelectedCards,
            icon: const Icon(Icons.device_hub_outlined),
          ),
          IconButton(
            key: const ValueKey('notes-canvas-undo-delete'),
            tooltip: 'Restore last removed card as a new card',
            onPressed: _saving || !hasKey || _lastDeletedCard == null
                ? null
                : _restoreLastCard,
            icon: const Icon(Icons.undo),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!hasKey)
            MaterialBanner(
              content: const Text(
                'Set up or unlock encrypted Notes storage to edit and sync this board.',
              ),
              leading: const Icon(Icons.lock_outline),
              actions: [
                TextButton(
                  onPressed: () => context.go('/notes'),
                  child: const Text('Open Notes setup'),
                ),
              ],
            ),
          if (_error != null)
            MaterialBanner(
              content: Text(_failureMessage(_error!)),
              leading: const Icon(Icons.sync_problem_outlined),
              actions: [
                TextButton(onPressed: _loadBoard, child: const Text('Retry')),
              ],
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    constrained: false,
                    minScale: 0.35,
                    maxScale: 2.5,
                    boundaryMargin: const EdgeInsets.all(200),
                    child: SizedBox(
                      width: 2400,
                      height: 1600,
                      child: CustomPaint(
                        painter: _NotesCanvasEdgesPainter(
                          cards: document.boardState.cards,
                          edges: document.boardState.edges,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        child: Stack(
                          children: [
                            for (final card in document.visibleCards)
                              Positioned(
                                left: card.x + (_dragOffsets[card.id]?.dx ?? 0),
                                top: card.y + (_dragOffsets[card.id]?.dy ?? 0),
                                width: card.width,
                                height: card.height,
                                child: _buildCard(
                                  card,
                                  scopedNotes,
                                  selected.contains(card.id),
                                  hasKey,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_saving)
                  const Positioned(
                    top: 12,
                    right: 12,
                    child: Chip(
                      avatar: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      label: Text('Saving'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(
    NotesCanvasCard card,
    List<WorkspaceNote> notes,
    bool selected,
    bool hasKey,
  ) {
    final content = switch (card) {
      NotesCanvasNoteCard() => _buildNoteCard(card, notes),
      NotesCanvasTextCard() => _buildTextCard(card),
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      color: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggleSelection(card.id),
            onPanUpdate: hasKey
                ? (details) => setState(() {
                    final previous = _dragOffsets[card.id] ?? Offset.zero;
                    _dragOffsets[card.id] = previous + details.delta;
                  })
                : null,
            onPanEnd: hasKey
                ? (_) {
                    final delta = _dragOffsets.remove(card.id) ?? Offset.zero;
                    setState(() {});
                    unawaited(_moveCard(card.id, delta));
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    card is NotesCanvasNoteCard
                        ? Icons.note_outlined
                        : Icons.text_snippet_outlined,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      card is NotesCanvasNoteCard ? 'Note' : 'Text',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove card',
                    visualDensity: VisualDensity.compact,
                    onPressed: hasKey ? () => _deleteCard(card.id) : null,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildNoteCard(NotesCanvasNoteCard card, List<WorkspaceNote> notes) {
    final note = notes.where((item) => item.id == card.noteId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                note?.title ?? 'Unavailable note',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          Text(
            note?.id ?? card.noteId,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: note == null
                  ? null
                  : () => context.go('/notes/${Uri.encodeComponent(note.id)}'),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open note'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextCard(NotesCanvasTextCard card) => Padding(
    padding: const EdgeInsets.all(10),
    child: Stack(
      children: [
        Positioned.fill(
          right: 30,
          child: SingleChildScrollView(
            child: SelectableText(
              card.markdown.isEmpty ? 'Empty text card' : card.markdown,
            ),
          ),
        ),
        Align(
          alignment: Alignment.topRight,
          child: IconButton(
            tooltip: 'Edit Markdown',
            onPressed: !_hasEncryptionKey || _canvasReplicaId == null
                ? null
                : () => _editTextCard(card),
            icon: const Icon(Icons.edit_outlined, size: 18),
          ),
        ),
      ],
    ),
  );

  void _toggleSelection(String cardId) {
    setState(() {
      if (!_selectedCardIds.add(cardId)) _selectedCardIds.remove(cardId);
      if (_selectedCardIds.length > 2) {
        _selectedCardIds.remove(_selectedCardIds.first);
      }
    });
  }
}

String notesCanvasRoute({required String? projectId, String? boardId}) => Uri(
  path: boardId == null
      ? '/notes/canvas'
      : '/notes/canvas/${Uri.encodeComponent(boardId)}',
  queryParameters: projectId == null ? null : {'projectId': projectId},
).toString();

class _CanvasErrorState extends StatelessWidget {
  const _CanvasErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

class _NotesCanvasEdgesPainter extends CustomPainter {
  const _NotesCanvasEdgesPainter({
    required this.cards,
    required this.edges,
    required this.color,
  });

  final List<NotesCanvasCard> cards;
  final List<NotesCanvasEdge> edges;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final byId = {for (final card in cards) card.id: card};
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final edge in edges.where((item) => !item.tombstoned)) {
      final from = byId[edge.fromCardId];
      final to = byId[edge.toCardId];
      if (from == null || to == null || from.tombstoned || to.tombstoned) {
        continue;
      }
      canvas.drawLine(
        Offset(from.x + from.width / 2, from.y + from.height / 2),
        Offset(to.x + to.width / 2, to.y + to.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NotesCanvasEdgesPainter oldDelegate) =>
      !identical(cards, oldDelegate.cards) ||
      !identical(edges, oldDelegate.edges) ||
      color != oldDelegate.color;
}
