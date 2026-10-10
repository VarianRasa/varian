import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/domain/models/collaboration.dart';
import 'package:varian/features/collaboration/presentation/widgets/comment_metadata_ui.dart';

import '../../test_app.dart';

void main() {
  testWidgets('metadata editor renders and updates labels and assignee', (
    tester,
  ) async {
    final comment = CanvasComment(
      id: 'comment-1',
      authorId: 'author-1',
      authorName: 'Amber Otter 01',
      text: 'Review',
      x: 0,
      y: 0,
      createdAt: DateTime.utc(2026, 9, 13),
      labels: const ['copy'],
    );
    CanvasComment? updated;

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          CommentMetadataPanel(
            comment: comment,
            readOnly: false,
            onChanged: (value) => updated = value,
            onPickAttachment: () async => null,
          ),
        ),
      ),
    );

    expect(find.text('copy'), findsOneWidget);
    expect(find.text('Belum ditugaskan'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('comment-add-label-comment-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('comment-label-field')),
      'review',
    );
    await tester.tap(find.byKey(const ValueKey('comment-label-save')));
    await tester.pumpAndSettle();
    expect(updated?.normalizedLabels, ['copy', 'review']);

    await tester.tap(find.byKey(const ValueKey('comment-assign-comment-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('comment-assignee-field')),
      'Calm Panda 02',
    );
    await tester.tap(find.byKey(const ValueKey('comment-assignee-save')));
    await tester.pumpAndSettle();
    expect(updated?.assigneeName, 'Calm Panda 02');
  });

  testWidgets('metadata editor adds an attachment through the picker', (
    tester,
  ) async {
    final comment = CanvasComment(
      id: 'comment-2',
      authorId: 'author-1',
      authorName: 'Amber Otter 01',
      text: 'Review',
      x: 0,
      y: 0,
      createdAt: DateTime.utc(2026, 9, 13),
    );
    CanvasComment? updated;

    await tester.pumpWidget(
      ProviderScope(
        child: testApp(
          CommentMetadataPanel(
            comment: comment,
            readOnly: false,
            onChanged: (value) => updated = value,
            onPickAttachment: () async => CommentAttachment(
              id: 'attachment-1',
              name: 'brief.pdf',
              mimeType: 'application/pdf',
              sizeBytes: 2048,
              createdAt: DateTime.utc(2026, 9, 13),
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('comment-add-attachment-comment-2')),
    );
    await tester.pumpAndSettle();

    expect(updated?.attachments.single.name, 'brief.pdf');
  });
}
