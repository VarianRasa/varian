import 'package:flutter_test/flutter_test.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/domain/models/collaboration.dart';
import 'package:varian/domain/models/drawing_payload.dart';
import 'package:varian/domain/models/node.dart';
import 'package:varian/domain/models/node_payload.dart';

void main() {
  group('Collaboration & Freehand Drawing Tests', () {
    test('display names are stable and replace placeholder names', () {
      final first = CollaborationDisplayNameGenerator.generate('account-a');
      final repeat = CollaborationDisplayNameGenerator.generate('account-a');
      final second = CollaborationDisplayNameGenerator.generate('account-b');

      expect(first, repeat);
      expect(first, isNotEmpty);
      expect(first, isNot(CollaborationDisplayNameGenerator.generate('')));
      expect(second, isNotEmpty);
      expect(
        CollaborationDisplayNameGenerator.resolve(
          stableId: 'account-a',
          preferredName: 'Collaborator',
        ),
        first,
      );
    });

    test('generated display names use a readable Google Docs-style format', () {
      final name = CollaborationDisplayNameGenerator.generate('account-a');

      expect(name, matches(RegExp(r'^[A-Za-z]+ [A-Za-z]+ \d{2}$')));
      expect(
        CollaborationDisplayNameGenerator.resolve(
          stableId: 'account-a',
          preferredName: 'Architect',
        ),
        name,
      );
      expect(
        CollaborationDisplayNameGenerator.resolve(
          stableId: 'account-a',
          preferredName: 'Amber Fox',
        ),
        'Amber Fox',
      );
    });

    test(
      'display name validation normalizes safe names and rejects invalid ones',
      () {
        expect(
          CollaborationDisplayNameGenerator.validate('  Amber   Fox 42 '),
          'Amber Fox 42',
        );
        expect(
          () => CollaborationDisplayNameGenerator.validate('A'),
          throwsFormatException,
        );
        expect(
          () => CollaborationDisplayNameGenerator.validate('Amber\nFox'),
          throwsFormatException,
        );
      },
    );

    test('collaboration notices expose member activity in readable text', () {
      final notice = CollaborationNotice(
        id: 'notice-1',
        userId: 'account-a',
        displayName: 'Amber Fox 42',
        kind: CollaborationNoticeKind.joined,
        createdAt: DateTime.utc(2026, 9, 9),
      );

      expect(notice.message, 'Amber Fox 42 joined the room.');
    });

    test('member without a profile receives a generated display name', () {
      final member = CanvasMember.fromJson({
        'project_id': 'project-1',
        'user_id': 'account-a',
        'role': 'viewer',
        'display_name': 'Collaborator',
      });

      expect(member.displayName, isNot('Collaborator'));
      expect(member.displayName, contains(' '));
    });

    test('role permissions distinguish host and guest capabilities', () {
      const host = CollaborationPermissions(CollaborationRole.owner);
      const editor = CollaborationPermissions(CollaborationRole.editor);
      const commenter = CollaborationPermissions(CollaborationRole.commenter);
      const viewer = CollaborationPermissions(CollaborationRole.viewer);

      expect(host.canManageMembers, isTrue);
      expect(host.canManageRoom, isTrue);
      expect(editor.canEditCanvas, isTrue);
      expect(editor.canComment, isTrue);
      expect(commenter.canEditCanvas, isFalse);
      expect(commenter.canComment, isTrue);
      expect(viewer.canComment, isFalse);
      expect(viewer.canEditCanvas, isFalse);
    });

    test('control event round-trips with validated payload', () {
      final event = CollaborationControlEvent(
        eventId: 'evt-1',
        projectId: 'project-1',
        actorId: 'user-1',
        targetUserId: 'user-2',
        type: CollaborationControlEventType.followRequest,
        payload: const {'requestId': 'req-1'},
        createdAt: DateTime.utc(2026, 9, 9),
      );

      final restored = CollaborationControlEvent.tryParse(event.toJson());

      expect(restored, isNotNull);
      expect(restored!.type, CollaborationControlEventType.followRequest);
      expect(restored.targetUserId, 'user-2');
      expect(restored.payload['requestId'], 'req-1');
    });

    test('member profile preserves role and activity metadata', () {
      final member = CanvasMember.fromJson({
        'project_id': 'project-1',
        'user_id': 'user-2',
        'role': 'commenter',
        'display_name': 'Guest Two',
        'avatar_url': 'https://example.test/avatar.png',
        'last_seen_at': '2026-09-09T10:00:00Z',
        'online': true,
        'cursor_active': true,
      });

      expect(member.collaborationRole, CollaborationRole.commenter);
      expect(member.displayName, 'Guest Two');
      expect(member.avatarUrl, 'https://example.test/avatar.png');
      expect(member.online, isTrue);
      expect(member.cursorActive, isTrue);
      expect(member.lastSeenAt, isNotNull);
    });

    test('control event rejects invalid or missing payloads', () {
      expect(
        CollaborationControlEvent.tryParse({
          'eventId': 'evt-1',
          'projectId': 'project-1',
          'actorId': 'user-1',
          'type': 'follow_request',
          'payload': null,
        }),
        isNull,
      );
      expect(
        CollaborationControlEvent.tryParse({
          'eventId': 'evt-1',
          'projectId': 'project-1',
          'actorId': 'user-1',
          'type': 'unknown',
          'payload': const {},
        }),
        isNull,
      );
    });

    test('DrawingPayload points serialization and bounds', () {
      final drawingNode = CanvasNode(
        id: 'brush_1',
        type: NodeType.drawing,
        x: 10,
        y: 20,
        width: 100,
        height: 80,
        payload: DrawingPayload(
          points: const [Offset(0, 0), Offset(50, 40), Offset(100, 80)],
        ),
      );

      final json = drawingNode.toJson();
      final deserialized = CanvasNode.fromJson(json);

      expect(deserialized.type, NodeType.drawing);
      expect((deserialized.payload as DrawingPayload).points.length, 3);
      expect(
        (deserialized.payload as DrawingPayload).points[1],
        const Offset(50, 40),
      );
    });

    test('CanvasComment model serialization', () {
      final comment = CanvasComment(
        id: 'c1',
        feedbackThreadId: 'thread-1',
        authorId: 'u1',
        authorName: 'Alex',
        text: 'Needs color tweak',
        x: 120,
        y: 240,
        createdAt: DateTime.now(),
      );

      final json = comment.toJson();
      final restored = CanvasComment.fromJson(json);

      expect(restored.authorName, 'Alex');
      expect(restored.text, 'Needs color tweak');
      expect(restored.resolved, false);
      expect(restored.feedbackThreadId, 'thread-1');
      expect(restored.feedbackThreadKey, 'thread-1');

      final legacyJson = Map<String, dynamic>.from(json)
        ..remove('feedbackThreadId');
      final legacyComment = CanvasComment.fromJson(legacyJson);
      expect(legacyComment.feedbackThreadId, isNull);
      expect(legacyComment.feedbackThreadKey, 'c1');
    });
  });
}
