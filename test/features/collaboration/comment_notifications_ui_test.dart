import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/data/local/local_storage_service.dart';
import 'package:varian/features/collaboration/domain/comment_notifications.dart';
import 'package:varian/features/collaboration/presentation/widgets/comment_notifications_ui.dart';

import '../../test_app.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets('notification semantics announce read status', (tester) async {
    final storage = LocalStorageService();
    await storage.saveCommentNotifications('project-1', 'user-1', [
      CommentNotification(
        id: 'unread',
        projectId: 'project-1',
        commentId: 'comment-1',
        type: CommentNotificationType.mention,
        actorId: 'user-2',
        actorName: 'Remote One',
        message: 'Anda disebut.',
        createdAt: DateTime.utc(2026, 9, 13, 8),
      ),
      CommentNotification(
        id: 'read',
        projectId: 'project-1',
        commentId: 'comment-2',
        type: CommentNotificationType.reply,
        actorId: 'user-3',
        actorName: 'Remote Two',
        message: 'Balasan lama.',
        createdAt: DateTime.utc(2026, 9, 13, 7),
        readAt: DateTime.utc(2026, 9, 13, 7, 30),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          const CommentNotificationInboxButton(
            projectId: 'project-1',
            userId: 'user-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('canvas-comment-notifications')),
    );
    await tester.pumpAndSettle();
    final separators = tester.widgetList<Divider>(find.byType(Divider));
    expect(separators, isNotEmpty);
    final marker = find.descendant(
      of: find.byKey(const ValueKey('comment-notification-unread')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints?.minWidth == AppControlSize.compact &&
            widget.constraints?.minHeight == AppControlSize.compact,
      ),
    );
    expect(marker, findsOneWidget);
    expect(tester.getSize(marker), const Size(32, 32));
    expect(separators.every((divider) => divider.height == 1), isTrue);

    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('comment-notification-unread')),
          )
          .label,
      contains('Belum dibaca'),
    );
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('comment-notification-read')))
          .label,
      contains('Sudah dibaca'),
    );
  });
  testWidgets('filters the inbox to unread notifications', (tester) async {
    final storage = LocalStorageService();
    await storage.saveCommentNotifications('project-1', 'user-1', [
      CommentNotification(
        id: 'unread',
        projectId: 'project-1',
        commentId: 'comment-1',
        type: CommentNotificationType.mention,
        actorId: 'user-2',
        actorName: 'Remote One',
        message: 'Anda disebut.',
        createdAt: DateTime.utc(2026, 9, 13, 8),
      ),
      CommentNotification(
        id: 'read',
        projectId: 'project-1',
        commentId: 'comment-2',
        type: CommentNotificationType.reply,
        actorId: 'user-3',
        actorName: 'Remote Two',
        message: 'Balasan lama.',
        createdAt: DateTime.utc(2026, 9, 13, 7),
        readAt: DateTime.utc(2026, 9, 13, 7, 30),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          const CommentNotificationInboxButton(
            projectId: 'project-1',
            userId: 'user-1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('canvas-comment-notifications')),
    );
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Belum dibaca'));
    await tester.pumpAndSettle();

    expect(find.text('Anda disebut.'), findsOneWidget);
    expect(find.text('Balasan lama.'), findsNothing);
  });
}
