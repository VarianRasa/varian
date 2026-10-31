import 'dart:convert';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';
import '../domain/workspace_note_attachments.dart';
import 'notes_local_database.dart';

class NotesLocalStore {
  NotesLocalStore({
    required this.database,
    FlutterSecureStorage? secureStorage,
    this._storageAvailability,
  }) : _secure = secureStorage ?? const FlutterSecureStorage();
  final NotesLocalDatabase database;
  final FlutterSecureStorage _secure;
  final Future<bool> Function()? _storageAvailability;
  bool _enabled = true;
  bool get isEnabled => _enabled;
  final Map<String, Future<String?>> _canvasReplicaIds = {};

  Future<void> saveNote({
    required String accountId,
    required String noteId,
    required String plaintext,
    required Uint8List key,
  }) async {
    if (!_validScope(accountId, noteId) ||
        key.length != 32 ||
        utf8.encode(plaintext).length > 10 * 1024 * 1024 ||
        !await _available()) {
      return;
    }
    final box = _seal(utf8.encode(plaintext), key, 'note:$accountId:$noteId');
    await database.customStatement(
      'INSERT OR REPLACE INTO notes_cache(account_id,note_id,ciphertext,nonce,updated_at) VALUES(?,?,?,?,?)',
      [
        accountId,
        noteId,
        box.$2,
        box.$1,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  Future<String?> readNote({
    required String accountId,
    required String noteId,
    required Uint8List key,
  }) async {
    if (!_validScope(accountId, noteId) || key.length != 32) {
      return null;
    }
    if (!await _available()) return null;
    final rows = await database
        .customSelect(
          'SELECT ciphertext,nonce FROM notes_cache WHERE account_id=? AND note_id=?',
          variables: [
            Variable.withString(accountId),
            Variable.withString(noteId),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    try {
      return utf8.decode(
        _open(
          rows.first.data['ciphertext'] as Uint8List,
          key,
          'note:$accountId:$noteId',
          rows.first.data['nonce'] as Uint8List,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAttachmentBytes({
    required String accountId,
    required String attachmentId,
    required String noteId,
    required String scopeId,
    required Uint8List bytes,
    required Uint8List key,
  }) async {
    if (!_validScope(accountId, attachmentId) ||
        !_validScope(accountId, noteId) ||
        !_validScope(accountId, scopeId) ||
        key.length != 32 ||
        detectWorkspaceNoteAttachmentType(bytes) == null ||
        !await _available()) {
      return;
    }
    final box = _seal(
      bytes,
      key,
      'attachment:$accountId:$noteId:$attachmentId:$scopeId',
    );
    await database.customStatement(
      'INSERT OR REPLACE INTO notes_attachment_cache(account_id,attachment_id,note_id,scope_id,ciphertext,nonce,updated_at) VALUES(?,?,?,?,?,?,?)',
      [
        accountId,
        attachmentId,
        noteId,
        scopeId,
        box.$2,
        box.$1,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  Future<Uint8List?> readAttachmentBytes({
    required String accountId,
    required String attachmentId,
    required String noteId,
    required String scopeId,
    required Uint8List key,
  }) async {
    if (!_validScope(accountId, attachmentId) ||
        !_validScope(accountId, noteId) ||
        !_validScope(accountId, scopeId) ||
        key.length != 32 ||
        !await _available()) {
      return null;
    }
    final rows = await database
        .customSelect(
          'SELECT ciphertext,nonce FROM notes_attachment_cache WHERE account_id=? AND attachment_id=? AND note_id=? AND scope_id=?',
          variables: [
            Variable.withString(accountId),
            Variable.withString(attachmentId),
            Variable.withString(noteId),
            Variable.withString(scopeId),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    try {
      final bytes = _open(
        rows.first.data['ciphertext'] as Uint8List,
        key,
        'attachment:$accountId:$noteId:$attachmentId:$scopeId',
        rows.first.data['nonce'] as Uint8List,
      );
      return detectWorkspaceNoteAttachmentType(bytes) == null ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> removeAttachmentBytes({
    required String accountId,
    required String attachmentId,
  }) async {
    if (!_validScope(accountId, attachmentId) || !await _available()) return;
    await database.customStatement(
      'DELETE FROM notes_attachment_cache WHERE account_id=? AND attachment_id=?',
      [accountId, attachmentId],
    );
  }

  Future<void> enqueue({
    required String accountId,
    required String operationId,
    required String payload,
    required Uint8List key,
  }) async {
    if (!_validScope(accountId, operationId) ||
        key.length != 32 ||
        utf8.encode(payload).length > 256 * 1024 ||
        !await _available()) {
      return;
    }
    final box = _seal(
      utf8.encode(payload),
      key,
      'outbox:$accountId:$operationId',
    );
    await database.customStatement(
      'INSERT OR REPLACE INTO notes_outbox(account_id,operation_id,ciphertext,nonce,created_at) VALUES(?,?,?,?,?)',
      [
        accountId,
        operationId,
        box.$2,
        box.$1,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  Future<void> saveCheckpoint({
    required String accountId,
    required String noteId,
    required String versionVectorJson,
    required Uint8List key,
  }) async {
    if (!_validScope(accountId, noteId) ||
        key.length != 32 ||
        utf8.encode(versionVectorJson).length > 64 * 1024 ||
        !await _available()) {
      return;
    }
    final box = _seal(
      utf8.encode(versionVectorJson),
      key,
      'checkpoint:$accountId:$noteId',
    );
    await database.customStatement(
      'INSERT OR REPLACE INTO notes_sync_checkpoints(account_id,note_id,ciphertext,nonce,updated_at) VALUES(?,?,?,?,?)',
      [
        accountId,
        noteId,
        box.$2,
        box.$1,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  Future<String?> readCheckpoint({
    required String accountId,
    required String noteId,
    required Uint8List key,
  }) async {
    if (!_validScope(accountId, noteId) ||
        key.length != 32 ||
        !await _available()) {
      return null;
    }
    final rows = await database
        .customSelect(
          'SELECT ciphertext,nonce FROM notes_sync_checkpoints WHERE account_id=? AND note_id=?',
          variables: [
            Variable.withString(accountId),
            Variable.withString(noteId),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    try {
      return utf8.decode(
        _open(
          rows.first.data['ciphertext'] as Uint8List,
          key,
          'checkpoint:$accountId:$noteId',
          rows.first.data['nonce'] as Uint8List,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> removeOutbox({
    required String accountId,
    required String operationId,
  }) async {
    if (!_validScope(accountId, operationId) || !await _available()) return;
    await database.customStatement(
      'DELETE FROM notes_outbox WHERE account_id=? AND operation_id=?',
      [accountId, operationId],
    );
  }

  Future<List<String>> pendingOutboxOperationIds({
    required String accountId,
    int limit = 1000,
  }) async {
    if (accountId.isEmpty || accountId.length > 256 || !await _available()) {
      return const [];
    }
    final rows = await database
        .customSelect(
          'SELECT operation_id FROM notes_outbox WHERE account_id=? ORDER BY created_at LIMIT ?',
          variables: [
            Variable.withString(accountId),
            Variable.withInt(limit.clamp(1, 10000).toInt()),
          ],
        )
        .get();
    return rows.map((row) => row.data['operation_id'] as String).toList();
  }

  Future<List<String>> readOutbox({
    required String accountId,
    required Uint8List key,
    int limit = 500,
  }) async {
    if (accountId.isEmpty || accountId.length > 256 || key.length != 32) {
      return const [];
    }
    if (!await _available()) return const [];
    final rows = await database
        .customSelect(
          'SELECT operation_id,ciphertext,nonce FROM notes_outbox WHERE account_id=? ORDER BY created_at LIMIT ?',
          variables: [
            Variable.withString(accountId),
            Variable.withInt(limit.clamp(1, 500).toInt()),
          ],
        )
        .get();
    return rows
        .map(
          (r) => utf8.decode(
            _open(
              r.data['ciphertext'] as Uint8List,
              key,
              'outbox:$accountId:${r.data['operation_id']}',
              r.data['nonce'] as Uint8List,
            ),
          ),
        )
        .toList();
  }

  Future<void> saveCanvasSnapshot({
    required String accountId,
    required String boardId,
    required String snapshot,
    required Uint8List key,
  }) async {
    if (!_validScope(accountId, boardId) ||
        key.length != 32 ||
        utf8.encode(snapshot).length > 20 * 1024 * 1024 ||
        !await _available()) {
      return;
    }
    final box = _seal(
      utf8.encode(snapshot),
      key,
      'canvas-snapshot:$accountId:$boardId',
    );
    await database.customStatement(
      'INSERT OR REPLACE INTO notes_canvas_cache(account_id,board_id,ciphertext,nonce,updated_at) VALUES(?,?,?,?,?)',
      [
        accountId,
        boardId,
        box.$2,
        box.$1,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  Future<String?> readCanvasSnapshot({
    required String accountId,
    required String boardId,
    required Uint8List key,
  }) async {
    if (!_validScope(accountId, boardId) ||
        key.length != 32 ||
        !await _available()) {
      return null;
    }
    final rows = await database
        .customSelect(
          'SELECT ciphertext,nonce FROM notes_canvas_cache WHERE account_id=? AND board_id=?',
          variables: [
            Variable.withString(accountId),
            Variable.withString(boardId),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    try {
      return utf8.decode(
        _open(
          rows.first.data['ciphertext'] as Uint8List,
          key,
          'canvas-snapshot:$accountId:$boardId',
          rows.first.data['nonce'] as Uint8List,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> enqueueCanvasOperation({
    required String accountId,
    required String boardId,
    required String operationId,
    required String payload,
    required Uint8List key,
  }) async {
    if (!_validScope(accountId, boardId) ||
        !_validScope(accountId, operationId) ||
        key.length != 32 ||
        utf8.encode(payload).length > 256 * 1024 ||
        !await _available()) {
      return;
    }
    final box = _seal(
      utf8.encode(payload),
      key,
      'canvas-outbox:$accountId:$boardId:$operationId',
    );
    await database.customStatement(
      'INSERT OR IGNORE INTO notes_canvas_outbox(account_id,board_id,operation_id,ciphertext,nonce,created_at) VALUES(?,?,?,?,?,?)',
      [
        accountId,
        boardId,
        operationId,
        box.$2,
        box.$1,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  Future<List<String>> pendingCanvasOutboxOperationIds({
    required String accountId,
    required String boardId,
    int limit = 1000,
  }) async {
    if (!_validScope(accountId, boardId) || !await _available()) {
      return const [];
    }
    final rows = await database
        .customSelect(
          'SELECT operation_id FROM notes_canvas_outbox WHERE account_id=? AND board_id=? ORDER BY created_at,rowid LIMIT ?',
          variables: [
            Variable.withString(accountId),
            Variable.withString(boardId),
            Variable.withInt(limit.clamp(1, 10000).toInt()),
          ],
        )
        .get();
    return rows.map((row) => row.data['operation_id'] as String).toList();
  }

  Future<List<String>> readCanvasOutbox({
    required String accountId,
    required String boardId,
    required Uint8List key,
    int limit = 500,
  }) async {
    if (!_validScope(accountId, boardId) || key.length != 32) {
      return const [];
    }
    if (!await _available()) return const [];
    final rows = await database
        .customSelect(
          'SELECT operation_id,ciphertext,nonce FROM notes_canvas_outbox WHERE account_id=? AND board_id=? ORDER BY created_at,rowid LIMIT ?',
          variables: [
            Variable.withString(accountId),
            Variable.withString(boardId),
            Variable.withInt(limit.clamp(1, 500).toInt()),
          ],
        )
        .get();
    return rows
        .map(
          (row) => utf8.decode(
            _open(
              row.data['ciphertext'] as Uint8List,
              key,
              'canvas-outbox:$accountId:$boardId:${row.data['operation_id']}',
              row.data['nonce'] as Uint8List,
            ),
          ),
        )
        .toList(growable: false);
  }

  Future<void> removeCanvasOutboxOperation({
    required String accountId,
    required String boardId,
    required String operationId,
  }) async {
    if (!_validScope(accountId, boardId) ||
        !_validScope(accountId, operationId) ||
        !await _available()) {
      return;
    }
    await database.customStatement(
      'DELETE FROM notes_canvas_outbox WHERE account_id=? AND board_id=? AND operation_id=?',
      [accountId, boardId, operationId],
    );
  }

  Future<bool> _available() async {
    try {
      if (_storageAvailability != null) {
        _enabled = _enabled && await _storageAvailability();
      } else {
        await _secure.read(key: 'notes-storage-probe');
      }
      return _enabled;
    } catch (_) {
      _enabled = false;
      return false;
    }
  }

  bool _validScope(String accountId, String recordId) =>
      accountId.isNotEmpty &&
      accountId.length <= 256 &&
      recordId.isNotEmpty &&
      recordId.length <= 256;

  Future<void> storeDeviceKey({
    required String accountId,
    required Uint8List key,
  }) async {
    if (!_validScope(accountId, 'device-key') ||
        key.length != 32 ||
        !await _available()) {
      return;
    }
    try {
      await _secure.write(
        key: 'notes-dek:$accountId',
        value: base64Encode(key),
      );
    } catch (_) {
      _enabled = false;
    }
  }

  Future<Uint8List?> loadDeviceKey({required String accountId}) async {
    if (!_validScope(accountId, 'device-key') || !await _available()) {
      return null;
    }
    try {
      final value = await _secure.read(key: 'notes-dek:$accountId');
      if (value == null) return null;
      final key = base64Decode(value);
      return key.length == 32 ? Uint8List.fromList(key) : null;
    } catch (_) {
      _enabled = false;
      return null;
    }
  }

  Future<String?> loadOrCreateCanvasReplicaId({required String accountId}) {
    if (!_validScope(accountId, 'canvas-replica')) {
      return Future.value(null);
    }
    return _canvasReplicaIds.putIfAbsent(
      accountId,
      () => _loadOrCreateCanvasReplicaId(accountId),
    );
  }

  Future<String?> _loadOrCreateCanvasReplicaId(String accountId) async {
    if (!await _available()) return null;
    final storageKey = 'notes-canvas-replica:$accountId';
    try {
      final existing = await _secure.read(key: storageKey);
      if (existing != null && _isUuid(existing)) return existing;
      final replicaId = const Uuid().v4();
      await _secure.write(key: storageKey, value: replicaId);
      return replicaId;
    } catch (_) {
      _enabled = false;
      return null;
    }
  }

  bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  Future<void> deleteDeviceKey({required String accountId}) async {
    if (!await _available()) return;
    try {
      await _secure.delete(key: 'notes-dek:$accountId');
    } catch (_) {
      _enabled = false;
    }
  }

  (Uint8List, Uint8List) _seal(List<int> plaintext, Uint8List key, String aad) {
    final nonce = Uint8List.fromList(
      List.generate(12, (_) => Random.secure().nextInt(256)),
    );
    final c = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), 128, nonce, utf8.encode(aad)),
      );
    return (nonce, c.process(Uint8List.fromList(plaintext)));
  }

  Uint8List _open(Uint8List bytes, Uint8List key, String aad, Uint8List nonce) {
    final c = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(key), 128, nonce, utf8.encode(aad)),
      );
    return c.process(bytes);
  }
}
