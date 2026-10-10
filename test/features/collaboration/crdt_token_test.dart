import 'package:flutter_test/flutter_test.dart';
import 'package:varian/domain/models/design_tokens.dart';
import 'package:varian/domain/models/document.dart';
import 'package:varian/features/collaboration/domain/crdt_engine.dart';

DesignToken _token({String id = 'color.brand', Object value = '#ff5500'}) =>
    DesignToken(
      id: id,
      name: 'Brand color',
      type: DesignTokenType.color,
      value: value,
      modeValues: const {'dark': '#ff8844'},
      updatedAt: DateTime.utc(2026, 9, 11),
    );

void main() {
  test('token upserts and deletes converge across sessions', () {
    final document = CanvasDocument(
      projectId: 'tokens-project',
      tokens: const DesignTokenSet(modes: ['base', 'dark']),
      updatedAt: DateTime.utc(2026, 9, 11),
    );
    final owner = CrdtDocumentSession.fromDocument(document, actorId: 'owner');
    final guest = CrdtDocumentSession.fromDocument(document, actorId: 'guest');

    final upsert = owner.upsertToken(
      _token(),
      modes: const ['base', 'dark'],
      version: 2,
    );
    expect(guest.applyRemote(upsert), CrdtApplyStatus.applied);
    expect(guest.document.tokens['color.brand']?.resolve('dark'), '#ff8844');
    expect(guest.document.tokens.modes, ['base', 'dark']);
    expect(guest.document.tokens.version, 2);

    final delete = owner.deleteToken('color.brand');
    expect(guest.applyRemote(delete), CrdtApplyStatus.applied);
    expect(guest.document.tokens['color.brand'], isNull);
  });

  test('token dots and tombstones survive snapshot round trips', () {
    final document = CanvasDocument(
      projectId: 'tokens-snapshot',
      updatedAt: DateTime.utc(2026, 9, 11),
    );
    final source = CrdtDocumentSession.fromDocument(document, actorId: 'owner');
    source.upsertToken(_token());
    source.deleteToken('color.brand');
    final restored = CrdtDocumentSession.fromSnapshot(
      document: document,
      actorId: 'guest',
      version: source.version,
      state: source.snapshotState(),
    );

    expect(restored.document.tokens['color.brand'], isNull);
    final stale = CrdtDocumentSession.fromDocument(document, actorId: 'other');
    expect(stale.applyRemote(source.drainOutbound().first), isNotNull);
  });
}
