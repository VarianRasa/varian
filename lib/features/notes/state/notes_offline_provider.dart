import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varian/data/local/durable/durable_database_connection.dart';
import 'package:varian/data/remote/supabase_service.dart';
import 'package:varian/features/notes/data/notes_local_database.dart';
import 'package:varian/features/notes/data/notes_local_store.dart';
import 'package:varian/features/notes/data/notes_supabase_sync_transport.dart';
import 'package:varian/features/notes/data/notes_sync_repository.dart';

class NotesOfflineService {
  const NotesOfflineService({
    required this.store,
    required this.sync,
    required this.keyForAccount,
  });
  final NotesLocalStore store;
  final NotesSyncRepository sync;
  final Future<Uint8List?> Function(String accountId) keyForAccount;
}

final notesOfflineServiceProvider = Provider<NotesOfflineService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  final database = NotesLocalDatabase(
    openDurableDatabaseConnection(
      name: 'varian_notes_offline',
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
  final store = NotesLocalStore(database: database);
  final sync = NotesSyncRepository(
    store: store,
    transport: SupabaseNotesSyncTransport(client),
    keyForAccount: (accountId) => store.loadDeviceKey(accountId: accountId),
    currentAccountId: () async {
      final user = client.auth.currentUser;
      return user == null || user.isAnonymous ? null : user.id;
    },
  );
  ref.onDispose(() => unawaited(database.close()));
  return NotesOfflineService(
    store: store,
    sync: sync,
    keyForAccount: (accountId) => store.loadDeviceKey(accountId: accountId),
  );
});
