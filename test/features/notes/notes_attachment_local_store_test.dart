import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varian/features/notes/data/notes_local_database.dart';
import 'package:varian/features/notes/data/notes_local_store.dart';

void main() {
  late NotesLocalDatabase database;
  late NotesLocalStore store;
  final key = Uint8List.fromList(List<int>.generate(32, (index) => index));
  const accountId = 'account-attachments-a';
  const attachmentId = '123e4567-e89b-12d3-a456-426614174000';
  const noteId = '223e4567-e89b-12d3-a456-426614174001';
  const privateScopeId = 'private:account-attachments-a';
  final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 1, 2]);

  setUp(() {
    database = NotesLocalDatabase(NativeDatabase.memory());
    store = NotesLocalStore(
      database: database,
      storageAvailability: () async => true,
    );
  });

  tearDown(() => database.close());

  test(
    'stores bytes encrypted and binds cache reads to account and scope',
    () async {
      await store.saveAttachmentBytes(
        accountId: accountId,
        attachmentId: attachmentId,
        noteId: noteId,
        scopeId: privateScopeId,
        bytes: png,
        key: key,
      );

      expect(
        await store.readAttachmentBytes(
          accountId: accountId,
          attachmentId: attachmentId,
          noteId: noteId,
          scopeId: privateScopeId,
          key: key,
        ),
        png,
      );
      expect(
        await store.readAttachmentBytes(
          accountId: 'account-attachments-b',
          attachmentId: attachmentId,
          noteId: noteId,
          scopeId: privateScopeId,
          key: key,
        ),
        isNull,
      );
      expect(
        await store.readAttachmentBytes(
          accountId: accountId,
          attachmentId: attachmentId,
          noteId: noteId,
          scopeId: 'project:other-project',
          key: key,
        ),
        isNull,
      );

      final rows = await database
          .customSelect('SELECT ciphertext FROM notes_attachment_cache')
          .get();
      expect(
        utf8.decode(
          rows.single.data['ciphertext'] as Uint8List,
          allowMalformed: true,
        ),
        isNot(contains(String.fromCharCodes(png))),
      );
    },
  );

  test(
    'rejects oversized bytes and mismatched attachment signatures',
    () async {
      final oversized = Uint8List(25 * 1024 * 1024 + 1)
        ..setRange(0, 8, png.take(8));
      await store.saveAttachmentBytes(
        accountId: accountId,
        attachmentId: attachmentId,
        noteId: noteId,
        scopeId: privateScopeId,
        bytes: oversized,
        key: key,
      );
      await store.saveAttachmentBytes(
        accountId: accountId,
        attachmentId: attachmentId,
        noteId: noteId,
        scopeId: privateScopeId,
        bytes: Uint8List.fromList('not a supported attachment'.codeUnits),
        key: key,
      );

      expect(
        await database
            .customSelect('SELECT * FROM notes_attachment_cache')
            .get(),
        isEmpty,
      );
    },
  );

  test('removes one attachment cache row for the current account', () async {
    await store.saveAttachmentBytes(
      accountId: accountId,
      attachmentId: attachmentId,
      noteId: noteId,
      scopeId: privateScopeId,
      bytes: png,
      key: key,
    );
    await store.removeAttachmentBytes(
      accountId: accountId,
      attachmentId: attachmentId,
    );

    expect(
      await database.customSelect('SELECT * FROM notes_attachment_cache').get(),
      isEmpty,
    );
  });
}
