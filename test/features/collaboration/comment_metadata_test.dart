import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/collaboration.dart';
import 'package:varian/features/collaboration/domain/comment_notifications.dart';
import 'package:varian/features/collaboration/state/collaboration_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('comment metadata survives a JSON round trip', () {
    final dueDate = DateTime.utc(2026, 9, 20, 12);
    final createdAt = DateTime.utc(2026, 9, 13, 8);
    final comment = CanvasComment(
      id: 'comment-1',
      authorId: 'author-1',
      authorName: 'Bright Otter 01',
      text: 'Review the hero copy',
      x: 12,
      y: 24,
      createdAt: createdAt,
      labels: const ['copy', 'priority'],
      assigneeId: 'author-2',
      assigneeName: 'Calm Panda 02',
      dueDate: dueDate,
      watchers: const ['author-1', 'author-3'],
      attachments: [
        CommentAttachment(
          id: 'attachment-1',
          name: 'hero.png',
          mimeType: 'image/png',
          sizeBytes: 1024,
          assetId: 'asset-1',
          uri: 'https://cdn.example/hero.png',
          checksum: 'sha256:abc',
          createdAt: createdAt,
        ),
      ],
    );

    final restored = CanvasComment.fromJson(comment.toJson());

    expect(restored.labels, ['copy', 'priority']);
    expect(restored.assigneeId, 'author-2');
    expect(restored.assigneeName, 'Calm Panda 02');
    expect(restored.dueDate, dueDate);
    expect(restored.watchers, ['author-1', 'author-3']);
    expect(restored.attachments.single.name, 'hero.png');
    expect(restored.attachments.single.assetId, 'asset-1');
    expect(restored.attachments.single.checksum, 'sha256:abc');
  });

  test('comment metadata helpers normalize labels and due dates', () {
    final base = CanvasComment(
      id: 'comment-1',
      authorId: 'author-1',
      authorName: 'Bright Otter 01',
      text: 'Review',
      x: 0,
      y: 0,
      createdAt: DateTime.utc(2026, 9, 13),
    );

    final updated = base.copyWith(
      labels: const ['  copy ', 'copy', '', 'priority'],
      dueDate: DateTime.utc(2026, 9, 20),
    );

    expect(updated.normalizedLabels, ['copy', 'priority']);
    expect(updated.isOverdue(DateTime.utc(2026, 9, 21)), isTrue);
    expect(updated.isOverdue(DateTime.utc(2026, 9, 20)), isFalse);
  });

  test(
    'notification preferences filter event types and unresolved comments',
    () {
      const preferences = CommentNotificationPreferences(
        mentions: true,
        replies: false,
        assignments: true,
        dueDates: false,
        resolvedThreads: false,
        unresolvedOnly: true,
      );

      expect(preferences.allows(CommentNotificationType.mention), isTrue);
      expect(preferences.allows(CommentNotificationType.reply), isFalse);
      expect(preferences.allows(CommentNotificationType.assignment), isTrue);
      expect(preferences.allows(CommentNotificationType.dueDate), isFalse);
      expect(preferences.allows(CommentNotificationType.resolved), isFalse);
    },
  );

  test('notification center filters unread and unresolved notifications', () {
    final notifications = [
      CommentNotification(
        id: 'n-1',
        projectId: 'project-1',
        commentId: 'comment-1',
        type: CommentNotificationType.mention,
        actorId: 'author-2',
        actorName: 'Calm Panda 02',
        message: 'You were mentioned',
        createdAt: DateTime.utc(2026, 9, 13, 8),
      ),
      CommentNotification(
        id: 'n-2',
        projectId: 'project-1',
        commentId: 'comment-2',
        type: CommentNotificationType.reply,
        actorId: 'author-3',
        actorName: 'Kind Fox 03',
        message: 'New reply',
        createdAt: DateTime.utc(2026, 9, 13, 9),
        readAt: DateTime.utc(2026, 9, 13, 10),
      ),
    ];

    final center = CommentNotificationCenter(notifications);
    expect(center.unread.length, 1);
    expect(center.forComments(const {'comment-1'}).single.id, 'n-1');
    expect(center.toJson().length, 2);
  });

  test(
    'notification inbox persists, deduplicates, and marks notifications read',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const scope = CommentNotificationScope(
        projectId: 'project-1',
        userId: 'author-1',
      );
      final notifier = container.read(
        commentNotificationsProvider(scope).notifier,
      );
      await notifier.ready;

      final notification = CommentNotification(
        id: 'n-1',
        projectId: scope.projectId,
        commentId: 'comment-1',
        type: CommentNotificationType.mention,
        actorId: 'author-2',
        actorName: 'Calm Panda 02',
        message: 'You were mentioned',
        createdAt: DateTime.utc(2026, 9, 13, 8),
      );
      notifier.upsert(notification);
      notifier.upsert(notification);
      await notifier.markRead('n-1');

      expect(
        container.read(commentNotificationsProvider(scope)).notifications,
        hasLength(1),
      );
      expect(
        container
            .read(commentNotificationsProvider(scope))
            .notifications
            .single
            .isRead,
        isTrue,
      );

      final secondContainer = ProviderContainer();
      addTearDown(secondContainer.dispose);
      final secondNotifier = secondContainer.read(
        commentNotificationsProvider(scope).notifier,
      );
      await secondNotifier.ready;
      expect(
        secondContainer
            .read(commentNotificationsProvider(scope))
            .notifications
            .single
            .id,
        'n-1',
      );
    },
  );
}
