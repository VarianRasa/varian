import 'package:drift/drift.dart';

class NotesLocalDatabase extends GeneratedDatabase {
  NotesLocalDatabase(super.executor);
  @override
  int get schemaVersion => 5;
  @override
  Iterable<TableInfo> get allTables => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE IF NOT EXISTS notes_cache (account_id TEXT NOT NULL, note_id TEXT NOT NULL, ciphertext BLOB NOT NULL, nonce BLOB NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY(account_id,note_id))',
      );
      await customStatement(
        'CREATE TABLE IF NOT EXISTS notes_outbox (account_id TEXT NOT NULL, operation_id TEXT NOT NULL, ciphertext BLOB NOT NULL, nonce BLOB NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY(account_id,operation_id))',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS notes_outbox_account_idx ON notes_outbox(account_id)',
      );
      await _createCheckpointTable();
      await _createCanvasTables();
      await _createAttachmentCache();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) await _createCheckpointTable();
      if (from < 3) await _createCanvasTables();
      if (from < 4) {
        await _createAttachmentCache();
      } else if (from < 5) {
        await customStatement(
          "ALTER TABLE notes_attachment_cache ADD COLUMN note_id TEXT NOT NULL DEFAULT ''",
        );
      }
    },
  );

  Future<void> _createAttachmentCache() => customStatement(
    'CREATE TABLE IF NOT EXISTS notes_attachment_cache (account_id TEXT NOT NULL, attachment_id TEXT NOT NULL, note_id TEXT NOT NULL, scope_id TEXT NOT NULL, ciphertext BLOB NOT NULL, nonce BLOB NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY(account_id,attachment_id))',
  );

  Future<void> _createCanvasTables() async {
    await customStatement(
      'CREATE TABLE IF NOT EXISTS notes_canvas_cache (account_id TEXT NOT NULL, board_id TEXT NOT NULL, ciphertext BLOB NOT NULL, nonce BLOB NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY(account_id,board_id))',
    );
    await customStatement(
      'CREATE TABLE IF NOT EXISTS notes_canvas_outbox (account_id TEXT NOT NULL, board_id TEXT NOT NULL, operation_id TEXT NOT NULL, ciphertext BLOB NOT NULL, nonce BLOB NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY(account_id,board_id,operation_id))',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS notes_canvas_outbox_account_board_idx ON notes_canvas_outbox(account_id,board_id,created_at)',
    );
  }

  Future<void> _createCheckpointTable() => customStatement(
    'CREATE TABLE IF NOT EXISTS notes_sync_checkpoints (account_id TEXT NOT NULL, note_id TEXT NOT NULL, ciphertext BLOB NOT NULL, nonce BLOB NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY(account_id,note_id))',
  );
}
