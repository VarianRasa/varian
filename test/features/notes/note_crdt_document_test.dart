import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/collaboration/domain/crdt_primitives.dart';
import 'package:varian/features/notes/domain/note_crdt_document.dart';
import 'package:varian/features/notes/domain/note_crdt_operation.dart';

void main() {
  test('concurrent inserts converge regardless of delivery order', () {
    final left = NoteCrdtDocument.fromMarkdown('note-a', 'ab');
    final right = NoteCrdtDocument.fromMarkdown('note-a', 'ab');
    final leftOp = left.applyLocalEdit(replicaId: 'left', markdown: 'aLb')!;
    final rightOp = right.applyLocalEdit(replicaId: 'right', markdown: 'aRb')!;

    left.applyRemoteOperation(rightOp);
    right.applyRemoteOperation(leftOp);

    expect(left.visibleMarkdown, 'aLRb');
    expect(left.visibleMarkdown, right.visibleMarkdown);
  });

  test('diffs Unicode by grapheme and preserves exact Markdown', () {
    const original = 'A👨‍👩‍👧‍👦B\n';
    final document = NoteCrdtDocument.fromMarkdown('note-a', original);
    const edited = 'A👨‍👩‍👧‍👦!B\n';

    final operation = document.applyLocalEdit(
      replicaId: 'device-a',
      markdown: edited,
    );

    expect(operation, isNotNull);
    expect(document.visibleMarkdown, edited);
    expect(operation!.insertions.single.value, '!');
  });

  test('duplicate operation delivery is idempotent', () {
    final source = NoteCrdtDocument.fromMarkdown('note-a', 'abc');
    final operation = source.applyLocalEdit(
      replicaId: 'device-a',
      markdown: 'aXbc',
    )!;
    expect(operation.opId, 'note-a:device-a:${operation.dot.counter}');
    final target = NoteCrdtDocument.fromMarkdown('note-a', 'abc');

    expect(target.applyRemoteOperation(operation), CrdtApplyStatus.applied);
    expect(target.applyRemoteOperation(operation), CrdtApplyStatus.duplicate);
    expect(target.visibleMarkdown, 'aXbc');
  });

  test('buffers causally dependent operations until prerequisites arrive', () {
    final source = NoteCrdtDocument.fromMarkdown('note-a', 'x');
    final first = source.applyLocalEdit(replicaId: 'device-a', markdown: 'x1')!;
    final second = source.applyLocalEdit(
      replicaId: 'device-a',
      markdown: 'x12',
    )!;
    final target = NoteCrdtDocument.fromMarkdown('note-a', 'x');

    expect(target.applyRemoteOperation(second), CrdtApplyStatus.buffered);
    expect(target.visibleMarkdown, 'x');
    expect(target.applyRemoteOperation(first), CrdtApplyStatus.applied);
    expect(target.visibleMarkdown, 'x12');
  });

  test('snapshot restores causally buffered operations', () {
    final source = NoteCrdtDocument.fromMarkdown('note-a', 'x');
    final first = source.applyLocalEdit(replicaId: 'device-a', markdown: 'x1')!;
    final second = source.applyLocalEdit(
      replicaId: 'device-a',
      markdown: 'x12',
    )!;
    final receiver = NoteCrdtDocument.fromMarkdown('note-a', 'x');
    receiver.applyRemoteOperation(second);
    final restored = NoteCrdtDocument.fromSnapshot(receiver.snapshotState());

    expect(restored.applyRemoteOperation(first), CrdtApplyStatus.applied);
    expect(restored.visibleMarkdown, 'x12');
  });

  test('snapshot retains tombstones and version vector', () {
    final source = NoteCrdtDocument.fromMarkdown('note-a', 'abc');
    source.applyLocalEdit(replicaId: 'device-a', markdown: 'ac');
    final restored = NoteCrdtDocument.fromSnapshot(source.snapshotState());

    expect(restored.visibleMarkdown, 'ac');
    expect(restored.versionVector, source.versionVector);
    expect(restored.snapshotState()['sequence']['atoms'], hasLength(3));
  });

  test('rejects operations for another note or missing atom anchors', () {
    final target = NoteCrdtDocument.fromMarkdown('note-a', 'a');
    final missingAnchor = NoteCrdtOperation(
      noteId: 'note-a',
      replicaId: 'device-b',
      dot: CrdtDot(actorId: 'device-b', counter: 1),
      dependencies: CrdtVersionVector(),
      insertions: [
        NoteCrdtInsertion(
          id: CrdtDot(actorId: 'device-b', counter: 1),
          after: CrdtDot(actorId: 'missing', counter: 9),
          value: 'x',
        ),
      ],
    );
    final wrongNote = NoteCrdtOperation(
      noteId: 'note-b',
      replicaId: 'device-b',
      dot: CrdtDot(actorId: 'device-b', counter: 1),
      dependencies: CrdtVersionVector(),
    );

    expect(
      target.applyRemoteOperation(missingAnchor),
      CrdtApplyStatus.rejected,
    );
    expect(target.applyRemoteOperation(wrongNote), CrdtApplyStatus.rejected);
    expect(target.visibleMarkdown, 'a');
  });
}
