import 'package:flutter_test/flutter_test.dart';
import 'package:varian/data/remote/supabase_service.dart';

void main() {
  test('hashes share tokens with SHA-256 without retaining the raw token', () {
    const token = 'share-token-for-test';

    expect(
      CanvasShareLink.hashToken(token),
      equals(
        'ae9ed5935a217872b043e9568bcab1dcc0c25390d5ec78ee0b81a626347c60c9',
      ),
    );
  });

  test('generates URL-safe high-entropy token material', () {
    final token = CanvasShareLink.newToken();

    expect(token.length, greaterThanOrEqualTo(42));
    expect(token, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(token, isNot(contains('=')));
  });

  test('accepts object and single-row RPC response shapes', () {
    expect(CanvasShareLink.recordFromRpcResponse({'id': 'object-id'}), {
      'id': 'object-id',
    });
    expect(
      CanvasShareLink.recordFromRpcResponse([
        {'id': 'row-id'},
      ]),
      {'id': 'row-id'},
    );
    expect(CanvasShareLink.recordFromRpcResponse(const []), isNull);
  });

  test('accepts only six-digit collaboration room IDs', () {
    expect(CanvasRoom.isValidRoomCode('482917'), isTrue);
    expect(CanvasRoom.isValidRoomCode(' 482917 '), isTrue);
    expect(CanvasRoom.isValidRoomCode('48291'), isFalse);
    expect(CanvasRoom.isValidRoomCode('4829170'), isFalse);
    expect(CanvasRoom.isValidRoomCode('48A917'), isFalse);
  });

  test('parses collaboration room RPC payloads', () {
    final room = CanvasRoom.fromRpcResponse({
      'id': 'room-id',
      'project_id': 'project-id',
      'project_name': 'Shared board',
      'room_code': '482917',
      'role': 'editor',
    });

    expect(room.id, 'room-id');
    expect(room.projectId, 'project-id');
    expect(room.projectName, 'Shared board');
    expect(room.roomCode, '482917');
    expect(room.role, 'editor');
  });

  test('does not label non-auth share failures as sign-in failures', () {
    expect(
      createShareLinkErrorMessage(
        const SyncException('RPC function does not exist'),
      ),
      'Could not create a share link. Check the Supabase collaboration setup.',
    );
    expect(
      createShareLinkErrorMessage(
        const SyncException(
          'Sign in is required before writing cloud canvas data.',
        ),
      ),
      'Sign in is required to create a share link.',
    );
  });
}
