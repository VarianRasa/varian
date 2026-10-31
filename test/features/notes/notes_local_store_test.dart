import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/data/notes_local_database.dart';
import 'package:varian/features/notes/data/notes_local_store.dart';

void main() {
  late NotesLocalDatabase database;
  late NotesLocalStore store;
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
  setUp(() {
    database = NotesLocalDatabase(NativeDatabase.memory());
    store = NotesLocalStore(
      database: database,
      storageAvailability: () async => true,
    );
  });
  tearDown(() => database.close());

  test('disables persistence when secure storage is unavailable', () async {
    final unavailable = NotesLocalStore(
      database: database,
      storageAvailability: () async => false,
    );
    await unavailable.saveNote(
      accountId: 'account-a',
      noteId: 'note-1',
      plaintext: 'must not persist',
      key: key,
    );
    expect(unavailable.isEnabled, isFalse);
    expect(
      await unavailable.readNote(
        accountId: 'account-a',
        noteId: 'note-1',
        key: key,
      ),
      isNull,
    );
    final rows = await database.customSelect('SELECT * FROM notes_cache').get();
    expect(rows, isEmpty);
  });

  test('stores encrypted account-scoped note and outbox payloads', () async {
    const text = '# private note content';
    await store.saveNote(
      accountId: 'account-a',
      noteId: 'note-1',
      plaintext: text,
      key: key,
    );
    await store.enqueue(
      accountId: 'account-a',
      operationId: 'op-1',
      payload: text,
      key: key,
    );
    expect(
      await store.readNote(accountId: 'account-a', noteId: 'note-1', key: key),
      text,
    );
    expect(
      await store.readNote(accountId: 'account-b', noteId: 'note-1', key: key),
      isNull,
    );
    final rows = await database
        .customSelect('SELECT ciphertext FROM notes_cache')
        .get();
    expect(
      utf8.decode(
        rows.single.data['ciphertext'] as Uint8List,
        allowMalformed: true,
      ),
      isNot(contains(text)),
    );
    expect(await store.readOutbox(accountId: 'account-a', key: key), [text]);
  });
}
