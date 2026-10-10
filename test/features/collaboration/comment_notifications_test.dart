import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/collaboration.dart';
import 'package:varian/features/collaboration/domain/comment_notifications.dart';

void main() {
  test('extracts unique mention tokens from comment text', () {
    expect(
      CommentNotificationFactory.extractMentions(
        'Review @amber and @amber with @design-team.',
      ),
      ['amber', 'design-team'],
    );
  });

  test('creates deterministic notifications for a remote comment change', () {
    final previous = CanvasComment(
      id: 'comment-1',
      authorId: 'local-id',
      authorName: 'Amber',
      text: 'Review',
      x: 10,
      y: 20,
      createdAt: DateTime.utc(2026, 9, 13),
    );
    final current = previous.copyWith(
      text: 'Review @amber',
      replies: [
        CommentReply(
          id: 'reply-1',
          authorId: 'remote-id',
          authorName: 'Calm Panda',
          text: 'I updated this.',
          createdAt: DateTime.utc(2026, 9, 13, 1),
        ),
      ],
      assigneeId: 'local-id',
      assigneeName: 'Amber',
      dueDate: DateTime.utc(2026, 9, 20),
      resolved: true,
    );
    final now = DateTime.utc(2026, 9, 13, 2);

    final notifications = CommentNotificationFactory.fromCommentChange(
      projectId: 'project-1',
      localUserId: 'local-id',
      localUserName: 'Amber',
      current: current,
      actorId: 'remote-id',
      actorName: 'Calm Panda',
      previous: previous,
      now: now,
    );
    final repeated = CommentNotificationFactory.fromCommentChange(
      projectId: 'project-1',
      localUserId: 'local-id',
      localUserName: 'Amber',
      current: current,
      actorId: 'remote-id',
      actorName: 'Calm Panda',
      previous: previous,
      now: now,
    );

    expect(notifications.map((notification) => notification.type).toSet(), {
      CommentNotificationType.mention,
      CommentNotificationType.reply,
      CommentNotificationType.assignment,
      CommentNotificationType.dueDate,
      CommentNotificationType.resolved,
    });
    expect(
      notifications.map((notification) => notification.id).toList(),
      repeated.map((notification) => notification.id).toList(),
    );
    expect(
      notifications.every(
        (notification) => notification.projectId == 'project-1',
      ),
      isTrue,
    );
  });

  test('does not notify the local actor about their own change', () {
    final comment = CanvasComment(
      id: 'comment-2',
      authorId: 'local-id',
      authorName: 'Amber',
      text: 'Review @amber',
      x: 0,
      y: 0,
      createdAt: DateTime.utc(2026, 9, 13),
    );

    expect(
      CommentNotificationFactory.fromCommentChange(
        projectId: 'project-1',
        localUserId: 'account-id',
        localUserName: 'Amber',
        localIdentityAliases: const ['local-id'],
        current: comment,
        actorId: 'local-id',
        actorName: 'Amber',
      ),
      isEmpty,
    );
  });
}
