import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/app/theme.dart';
import 'package:varian/app/widgets/ui_primitives.dart';
import 'package:varian/domain/models/collaboration.dart';

import 'package:varian/features/collaboration/presentation/widgets/comment_thread_dialog.dart';
import 'package:varian/features/collaboration/presentation/widgets/comment_ui.dart';
import '../../test_app.dart';

void main() {
  final comment = CanvasComment(
    id: 'comment-1',
    authorId: 'author-1',
    authorName: 'Amber Otter 01',
    text: 'Need a second pass on this frame.',
    x: 12,
    y: 18,
    createdAt: DateTime.utc(2026, 1, 9, 10, 15),
    replies: [
      CommentReply(
        id: 'reply-1',
        authorId: 'author-2',
        authorName: 'Bright Fox 02',
        text: 'I will update it before review.',
        createdAt: DateTime.utc(2026, 1, 9, 11, 30),
      ),
    ],
  );

  testWidgets('avatar foreground contrasts with its token color', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        CommentAvatar(name: 'Ada', color: AppTokens.dark.info),
        data: AppTheme.darkTheme,
      ),
    );

    final avatarText = tester.widget<Text>(find.text('A'));
    expect(avatarText.style?.color, AppTokens.light.accentForeground);
  });
  testWidgets('comment card prioritizes message and collaborator metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          SizedBox(
            width: 380,
            child: CanvasCommentCard(
              comment: comment,
              readOnly: true,
              onReply: (_) {},
              onEdit: (_) {},
              onReaction: (_) {},
              onResolve: (_) {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Amber Otter 01'), findsOneWidget);
    expect(find.text('Need a second pass on this frame.'), findsOneWidget);
    expect(find.text('Bright Fox 02'), findsOneWidget);
    expect(find.text('I will update it before review.'), findsOneWidget);
    expect(find.text('1 balasan'), findsOneWidget);
    expect(find.textContaining('·'), findsAtLeastNWidgets(2));
  });
  testWidgets('comment card shell uses the shared surface primitive', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          SizedBox(
            width: 380,
            child: CanvasCommentCard(
              comment: comment,
              readOnly: true,
              onReply: (_) {},
              onEdit: (_) {},
              onReaction: (_) {},
              onResolve: (_) {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(UiSurface), findsAtLeastNWidgets(1));
    expect(find.text(comment.text), findsOneWidget);
  });
  testWidgets('comment panel fits a compact viewport', (tester) async {
    tester.view.physicalSize = const Size(280, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          CanvasCommentCard(
            comment: comment,
            readOnly: true,
            onReply: (_) {},
            onEdit: (_) {},
            onReaction: (_) {},
            onResolve: (_) {},
            onDelete: () {},
          ),
        ),
      ),
    );

    expect(
      tester.getRect(find.byType(UiSurface).first).right,
      lessThanOrEqualTo(280),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('comment card exposes editable review metadata', (tester) async {
    CanvasComment? updated;
    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          SizedBox(
            width: 380,
            child: CanvasCommentCard(
              comment: comment,
              readOnly: false,
              onReply: (_) {},
              onEdit: (_) {},
              onReaction: (_) {},
              onResolve: (_) {},
              onDelete: () {},
              onMetadataChanged: (value) => updated = value,
              onPickAttachment: () async => null,
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('comment-metadata-comment-1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('comment-add-label-comment-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('comment-label-field')),
      'handoff',
    );
    await tester.tap(find.byKey(const ValueKey('comment-label-save')));
    await tester.pumpAndSettle();

    expect(updated?.normalizedLabels, ['handoff']);
  });

  testWidgets(
    'comment actions stay inline instead of opening a thread dialog',
    (tester) async {
      String? replyText;
      String? editedText;
      String? reaction;
      var deleted = false;

      await tester.pumpWidget(
        ProviderScope(
          child: testApp(
            SizedBox(
              width: 380,
              child: CanvasCommentCard(
                comment: comment,
                readOnly: false,
                onReply: (value) => replyText = value,
                onEdit: (value) => editedText = value,
                onReaction: (value) => reaction = value,
                onResolve: (_) {},
                onDelete: () => deleted = true,
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('comment-reply-field-comment-1')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('comment-menu-comment-1')));
      await tester.pumpAndSettle();

      expect(find.text('Balas'), findsOneWidget);
      expect(find.text('Beri reaksi'), findsOneWidget);
      expect(find.text('Komentar baru'), findsNothing);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Hapus'), findsOneWidget);

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('comment-edit-field-comment-1')),
        'Updated comment text',
      );
      await tester.tap(
        find.byKey(const ValueKey('comment-edit-save-comment-1')),
      );
      await tester.pumpAndSettle();
      expect(editedText, equals('Updated comment text'));

      await tester.tap(find.byKey(const ValueKey('comment-menu-comment-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Balas'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('comment-reply-field-comment-1')),
        'Inline reply',
      );
      await tester.tap(
        find.byKey(const ValueKey('comment-reply-send-comment-1')),
      );
      await tester.pumpAndSettle();
      expect(replyText, equals('Inline reply'));

      await tester.tap(find.byKey(const ValueKey('comment-menu-comment-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beri reaksi'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('comment-reaction-option-comment-1-🚀')),
      );
      await tester.pumpAndSettle();
      expect(reaction, equals('🚀'));

      await tester.tap(find.byKey(const ValueKey('comment-menu-comment-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hapus'));
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
    },
  );

  testWidgets('reply actions support inline edit and delete', (tester) async {
    String? editedReplyText;
    var deletedReply = false;

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          SizedBox(
            width: 380,
            child: CanvasCommentCard(
              comment: comment,
              readOnly: false,
              onReply: (_) {},
              onEdit: (_) {},
              onReaction: (_) {},
              onResolve: (_) {},
              onDelete: () {},
              onEditReply: (reply, text) => editedReplyText = text,
              onDeleteReply: (_) => deletedReply = true,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('reply-menu-reply-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reply-menu-reply-1')));
    await tester.pumpAndSettle();
    expect(find.text('Edit balasan'), findsOneWidget);
    expect(find.text('Hapus balasan'), findsOneWidget);

    await tester.tap(find.text('Edit balasan'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('reply-edit-field-reply-1')),
      'Balasan yang sudah diperbarui',
    );
    await tester.tap(find.byKey(const ValueKey('reply-edit-save-reply-1')));
    await tester.pumpAndSettle();
    expect(editedReplyText, equals('Balasan yang sudah diperbarui'));

    await tester.tap(find.byKey(const ValueKey('reply-menu-reply-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus balasan'));
    await tester.pumpAndSettle();
    expect(deletedReply, isTrue);
  });

  testWidgets('edited and resolved comments show their visual state', (
    tester,
  ) async {
    final resolvedComment = comment.copyWith(
      editedAt: DateTime.utc(2026, 1, 9, 12, 45),
      resolved: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          SizedBox(
            width: 380,
            child: CanvasCommentCard(
              comment: resolvedComment,
              readOnly: true,
              onReply: (_) {},
              onEdit: (_) {},
              onReaction: (_) {},
              onResolve: (_) {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Edited'), findsOneWidget);
    final message = tester.widget<Text>(
      find.text('Need a second pass on this frame.'),
    );
    expect(message.style?.decoration, TextDecoration.lineThrough);
    expect(message.style?.color, isNot(AppTokens.dark.text));
  });
  testWidgets('comment thread dialog fits a short narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      testApp(
        CommentThreadDialog(
          comment: comment,
          localUserId: 'local-user',
          localUserName: 'Local user',
          readOnly: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dialog = find.byType(Dialog);
    final dialogRect = tester.getRect(dialog);
    final closeControl = find.byTooltip('Tutup thread komentar');
    final body = find.descendant(
      of: dialog,
      matching: find.byType(SingleChildScrollView),
    );
    expect(dialogRect.left, greaterThanOrEqualTo(0));
    expect(dialogRect.right, lessThanOrEqualTo(320));
    expect(dialogRect.top, greaterThanOrEqualTo(0));
    expect(dialogRect.bottom, lessThanOrEqualTo(480));
    expect(closeControl, findsOneWidget);
    expect(tester.getRect(closeControl).bottom, lessThanOrEqualTo(480));
    expect(body, findsOneWidget);
    final bodyViewport = tester.getRect(body);
    final readOnlyMessage = find.text(
      'Mode hanya baca. Anda tetap dapat melihat seluruh riwayat komentar.',
    );
    expect(
      tester.getRect(readOnlyMessage).top,
      greaterThanOrEqualTo(bodyViewport.bottom),
    );
    await tester.ensureVisible(find.text('I will update it before review.'));
    await tester.pumpAndSettle();
    final replyRect = tester.getRect(
      find.text('I will update it before review.'),
    );
    expect(replyRect.top, greaterThanOrEqualTo(tester.getRect(body).top));
    expect(replyRect.bottom, lessThanOrEqualTo(tester.getRect(body).bottom));
    expect(tester.takeException(), isNull);
  });
  testWidgets('comment thread reactions expose the current user state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final reactedComment = comment.copyWith(reactions: {'👍': 1, '❤️': 2});
    await tester.pumpWidget(
      testApp(
        CommentThreadDialog(
          comment: reactedComment,
          localUserId: 'local-user',
          localUserName: 'Local user',
          readOnly: true,
          isReactionActive: (emoji) => emoji == '❤️',
        ),
      ),
    );
    final dividers = tester.widgetList<Divider>(find.byType(Divider));
    expect(dividers, hasLength(1));
    expect(dividers.single.height, 1);

    final inactiveReaction = tester.getSemantics(
      find.bySemanticsLabel('👍 reaction, 1 not selected'),
    );
    final activeReaction = tester.getSemantics(
      find.bySemanticsLabel('❤️ reaction, 2 selected'),
    );
    expect(inactiveReaction.flagsCollection.isSelected, ui.Tristate.isFalse);
    expect(activeReaction.flagsCollection.isSelected, ui.Tristate.isTrue);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
  testWidgets('comment reply card uses a one-pixel app border', (tester) async {
    await tester.pumpWidget(
      testApp(
        CommentThreadDialog(
          comment: comment,
          localUserId: 'local-user',
          localUserName: 'Local user',
          readOnly: true,
        ),
      ),
    );

    final replyText = find.text('I will update it before review.');
    expect(replyText, findsOneWidget);
    final replyCard = tester.widget<Container>(
      find.ancestor(of: replyText, matching: find.byType(Container)).first,
    );
    final border = (replyCard.decoration! as BoxDecoration).border! as Border;
    expect(border.top.width, AppBorder.thin);
    expect(border.top.color, AppTokens.dark.panelBorder);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new top-level comments stay in the same feedback frame', (
    tester,
  ) async {
    String? newCommentText;
    final secondComment = comment.copyWith(
      id: 'comment-2',
      feedbackThreadId: comment.feedbackThreadKey,
      authorId: 'author-3',
      authorName: 'Calm Panda 03',
      text: 'A separate comment in this feedback.',
      createdAt: DateTime.utc(2026, 1, 9, 12, 30),
      replies: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          SizedBox(
            width: 380,
            child: CanvasCommentThreadCard(
              comments: [comment, secondComment],
              readOnly: false,
              onReply: (_, _) {},
              onEdit: (_, _) {},
              onReaction: (_, _) {},
              onResolve: (_, _) {},
              onDelete: (_) {},
              onCreateNewComment: (text) => newCommentText = text,
            ),
          ),
        ),
      ),
    );
    final dividers = tester.widgetList<Divider>(find.byType(Divider));
    expect(dividers, hasLength(1));
    expect(dividers.single.height, AppBorder.thin);

    expect(find.text('Feedback'), findsOneWidget);
    expect(find.text('2 komentar'), findsOneWidget);
    expect(find.text('Komentar baru'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('comment-menu-comment-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('comment-menu-comment-2')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('comment-new-field-comment-1')),
      'Komentar utama baru',
    );
    await tester.tap(find.byKey(const ValueKey('comment-new-send-comment-1')));
    await tester.pumpAndSettle();

    expect(newCommentText, equals('Komentar utama baru'));
  });
}
