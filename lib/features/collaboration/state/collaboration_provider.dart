import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/data/local/local_storage_service.dart';
import '../../../domain/models/collaboration.dart';
import '../domain/comment_notifications.dart';

class CollaborationProjectionScope {
  final String projectId;
  final String accountId;

  const CollaborationProjectionScope({
    required this.projectId,
    required this.accountId,
  });

  @override
  bool operator ==(Object other) =>
      other is CollaborationProjectionScope &&
      other.projectId == projectId &&
      other.accountId == accountId;

  @override
  int get hashCode => Object.hash(projectId, accountId);
}

final remoteCursorsProvider =
    StateNotifierProvider<RemoteCursorsNotifier, List<RemoteCursor>>((ref) {
      return RemoteCursorsNotifier();
    });

final collaborationRemoteCursorsProvider =
    StateNotifierProvider.family<
      RemoteCursorsNotifier,
      List<RemoteCursor>,
      CollaborationProjectionScope
    >((ref, _) => RemoteCursorsNotifier());

class RemoteCursorsNotifier extends StateNotifier<List<RemoteCursor>> {
  RemoteCursorsNotifier() : super([]);

  void updateCursor(
    String userId,
    String userName,
    Color userColor,
    double x,
    double y, {
    String? selectedNodeId,
    Set<String> selectedNodeIds = const {},
  }) {
    final existingIndex = state.indexWhere((c) => c.userId == userId);
    if (existingIndex >= 0) {
      final updated = [...state];
      updated[existingIndex] = updated[existingIndex].copyWith(
        userName: userName,
        userColor: userColor,
        x: x,
        y: y,
        selectedNodeId: selectedNodeId,
        selectedNodeIds: selectedNodeIds,
        lastActive: DateTime.now(),
      );
      state = updated;
    } else {
      state = [
        ...state,
        RemoteCursor(
          userId: userId,
          userName: userName,
          userColor: userColor,
          x: x,
          y: y,
          selectedNodeId: selectedNodeId,
          selectedNodeIds: selectedNodeIds,
          lastActive: DateTime.now(),
        ),
      ];
    }
  }

  void removeCursor(String userId) {
    state = state.where((c) => c.userId != userId).toList();
  }

  void clearCursors() {
    state = [];
  }
}

final commentsProvider =
    StateNotifierProvider<CommentsNotifier, List<CanvasComment>>((ref) {
      return CommentsNotifier();
    });

final collaborationCommentsProvider =
    StateNotifierProvider.family<
      CommentsNotifier,
      List<CanvasComment>,
      CollaborationProjectionScope
    >((ref, _) => CommentsNotifier());

class CommentsNotifier extends StateNotifier<List<CanvasComment>> {
  CommentsNotifier() : super([]);

  void addComment(CanvasComment comment) {
    upsertComment(comment);
  }

  void upsertComment(CanvasComment comment) {
    final index = state.indexWhere((c) => c.id == comment.id);
    if (index < 0) {
      state = [...state, comment];
      return;
    }
    final updated = [...state]..[index] = comment;
    state = updated;
  }

  void reconcile(Iterable<CanvasComment> comments) {
    state = List<CanvasComment>.unmodifiable(comments);
  }

  void deleteForNodes(Iterable<String> nodeIds) {
    final ids = nodeIds.toSet();
    state = state
        .where(
          (comment) => comment.nodeId == null || !ids.contains(comment.nodeId),
        )
        .toList();
  }

  void resolveComment(String id) {
    state = state
        .map((c) => c.id == id ? c.copyWith(resolved: true) : c)
        .toList();
  }

  void deleteComment(String id) {
    state = state.where((c) => c.id != id).toList();
  }

  void clear() {
    state = [];
  }
}

class CommentNotificationScope {
  final String projectId;
  final String userId;

  const CommentNotificationScope({
    required this.projectId,
    required this.userId,
  });

  @override
  bool operator ==(Object other) =>
      other is CommentNotificationScope &&
      other.projectId == projectId &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(projectId, userId);
}

class CommentNotificationInboxState {
  final List<CommentNotification> notifications;
  final CommentNotificationPreferences preferences;
  final bool isLoading;
  final String? errorMessage;

  const CommentNotificationInboxState({
    this.notifications = const [],
    this.preferences = const CommentNotificationPreferences(),
    this.isLoading = true,
    this.errorMessage,
  });

  int get unreadCount =>
      notifications.where((notification) => !notification.isRead).length;

  CommentNotificationInboxState copyWith({
    List<CommentNotification>? notifications,
    CommentNotificationPreferences? preferences,
    bool? isLoading,
    Object? errorMessage = _unset,
  }) => CommentNotificationInboxState(
    notifications: notifications ?? this.notifications,
    preferences: preferences ?? this.preferences,
    isLoading: isLoading ?? this.isLoading,
    errorMessage: errorMessage == _unset
        ? this.errorMessage
        : errorMessage as String?,
  );

  static const Object _unset = Object();
}

final commentNotificationsProvider =
    StateNotifierProvider.family<
      CommentNotificationInboxNotifier,
      CommentNotificationInboxState,
      CommentNotificationScope
    >((ref, scope) => CommentNotificationInboxNotifier(scope));

class CommentNotificationInboxNotifier
    extends StateNotifier<CommentNotificationInboxState> {
  final CommentNotificationScope scope;
  final LocalStorageService _storage;
  late final Future<void> ready;

  CommentNotificationInboxNotifier(this.scope, {LocalStorageService? storage})
    : _storage = storage ?? LocalStorageService(),
      super(const CommentNotificationInboxState()) {
    ready = _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait<Object>([
        _storage.loadCommentNotifications(scope.projectId, scope.userId),
        _storage.loadCommentNotificationPreferences(scope.userId),
      ]);
      if (!mounted) return;
      state = state.copyWith(
        notifications: List<CommentNotification>.from(values[0] as List),
        preferences: values[1] as CommentNotificationPreferences,
        isLoading: false,
        errorMessage: null,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, errorMessage: error.toString());
    }
  }

  void upsert(CommentNotification notification) {
    if (!state.preferences.allows(notification.type)) return;
    final next = [...state.notifications];
    final index = next.indexWhere((item) => item.id == notification.id);
    if (index < 0) {
      next.add(notification);
    } else {
      next[index] = notification;
    }
    next.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    state = state.copyWith(notifications: next, errorMessage: null);
    unawaited(_persistNotifications());
  }

  Future<void> markRead(String notificationId) async {
    final now = DateTime.now();
    final next = state.notifications
        .map(
          (notification) => notification.id == notificationId
              ? notification.copyWith(readAt: now)
              : notification,
        )
        .toList(growable: false);
    state = state.copyWith(notifications: next);
    await _persistNotifications();
  }

  Future<void> markAllRead() async {
    final now = DateTime.now();
    state = state.copyWith(
      notifications: state.notifications
          .map(
            (notification) => notification.isRead
                ? notification
                : notification.copyWith(readAt: now),
          )
          .toList(growable: false),
    );
    await _persistNotifications();
  }

  Future<void> remove(String notificationId) async {
    state = state.copyWith(
      notifications: state.notifications
          .where((notification) => notification.id != notificationId)
          .toList(growable: false),
    );
    await _persistNotifications();
  }

  Future<void> setPreferences(
    CommentNotificationPreferences preferences,
  ) async {
    state = state.copyWith(preferences: preferences);
    await _storage.saveCommentNotificationPreferences(
      scope.userId,
      preferences,
    );
  }

  List<CommentNotification> filtered({
    CommentNotificationType? type,
    bool unreadOnly = false,
    Iterable<String>? commentIds,
  }) => CommentNotificationCenter(
    state.notifications,
  ).filtered(type: type, unreadOnly: unreadOnly, commentIds: commentIds);

  Future<void> _persistNotifications() => _storage.saveCommentNotifications(
    scope.projectId,
    scope.userId,
    state.notifications,
  );
}
