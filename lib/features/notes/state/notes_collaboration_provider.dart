import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notes_collaboration_transport.dart';

class NotesCollaborationState {
  const NotesCollaborationState({
    this.connection = NotesConnectionState.disconnected,
    this.cursors = const {},
  });
  final NotesConnectionState connection;
  final Map<String, NotesCursorAnchor?> cursors;
  NotesCollaborationState copyWith({
    NotesConnectionState? connection,
    Map<String, NotesCursorAnchor?>? cursors,
  }) => NotesCollaborationState(
    connection: connection ?? this.connection,
    cursors: cursors ?? this.cursors,
  );
}

final notesCollaborationProvider =
    StateNotifierProvider<
      NotesCollaborationController,
      NotesCollaborationState
    >((ref) {
      return NotesCollaborationController(
        ref.watch(notesCollaborationTransportProvider),
      );
    });

class NotesCollaborationController
    extends StateNotifier<NotesCollaborationState> {
  NotesCollaborationController(this.transport)
    : super(const NotesCollaborationState()) {
    transport.onState = (connection) =>
        state = state.copyWith(connection: connection);
    transport.onCursor = (userId, anchor) {
      final cursors = Map<String, NotesCursorAnchor?>.from(state.cursors);
      if (anchor == null) {
        cursors.remove(userId);
      } else {
        cursors[userId] = anchor;
      }
      state = state.copyWith(cursors: cursors);
    };
    transport.onRemoteOperation = (operation) =>
        onRemoteOperation?.call(operation);
  }
  final NotesCollaborationTransport transport;
  void Function(Map<String, dynamic> operation)? onRemoteOperation;
  String? _identity;

  Future<void> join({required String noteId, required String projectId}) async {
    final identity = '$noteId:$projectId';
    if (_identity != identity) {
      await transport.leave();
      state = const NotesCollaborationState(
        connection: NotesConnectionState.connecting,
      );
      _identity = identity;
    }
    try {
      await transport.join(noteId, projectId);
    } catch (_) {
      state = state.copyWith(connection: NotesConnectionState.denied);
      rethrow;
    }
  }

  Future<void> leave() async {
    _identity = null;
    await transport.leave();
    state = const NotesCollaborationState();
  }

  @override
  void dispose() {
    unawaited(transport.leave());
    super.dispose();
  }
}
